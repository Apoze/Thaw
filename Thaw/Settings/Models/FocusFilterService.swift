//
//  FocusFilterService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents
import Combine
import Foundation

enum FocusFilterState: Equatable {
    case inactive
    case active(UUID)
    case notConfigured
}

enum FocusFilterConstants {
    static let requestedProfileIDKey = "FocusFilterRequestedProfileID"
    static let hasKnownConfigurationKey = "FocusFilterHasKnownConfiguration"
    static let activationNotification = Notification.Name("com.stonerl.Thaw.focusFilterActivated")
    static let deactivationNotification = Notification.Name("com.stonerl.Thaw.focusFilterDeactivated")
}

protocol FocusFilterCurrentAction {
    var requestedProfileID: UUID? { get }
    func perform() async throws
}

protocol FocusFilterCurrentProviding {
    func currentAction() async throws -> any FocusFilterCurrentAction
}

struct AppIntentFocusFilterCurrentProvider: FocusFilterCurrentProviding {
    func currentAction() async throws -> any FocusFilterCurrentAction {
        AppIntentFocusFilterCurrentAction(intent: try await ThawFocusFilter.current)
    }
}

private struct AppIntentFocusFilterCurrentAction: FocusFilterCurrentAction {
    let intent: ThawFocusFilter

    var requestedProfileID: UUID? {
        guard let id = intent.profile?.id else {
            return nil
        }
        return UUID(uuidString: id)
    }

    func perform() async throws {
        _ = try await intent.perform()
    }
}

@MainActor
final class FocusFilterService {
    private let diagLog = DiagLog(category: .focus)
    private let defaults: UserDefaults
    private let currentProvider: FocusFilterCurrentProviding
    private let notificationCenter: DistributedNotificationCenter
    private let stateSubject = PassthroughSubject<FocusFilterState, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var profileExists: ((UUID) -> Bool)?
    private var didReceiveDeactivationSinceSetup = false
    private var hasCompletedSetup = false
    private var hasPublishedState = false
    private var resyncTask: Task<Void, Never>?

    private(set) var state: FocusFilterState = .notConfigured

    init(
        defaults: UserDefaults = .standard,
        currentProvider: FocusFilterCurrentProviding = AppIntentFocusFilterCurrentProvider(),
        notificationCenter: DistributedNotificationCenter = .default()
    ) {
        self.defaults = defaults
        self.currentProvider = currentProvider
        self.notificationCenter = notificationCenter
    }

    var statePublisher: AnyPublisher<FocusFilterState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    func performSetup(profileExists: @escaping (UUID) -> Bool) {
        self.profileExists = profileExists
        guard !hasCompletedSetup else {
            return
        }

        hasCompletedSetup = true
        subscribeToNotifications()
        resolveBootstrapState()
        scheduleResyncIfNeeded()
    }

    func clearRequestedProfileIfInvalid(_ profileID: UUID) {
        let mirroredProfileID = requestedProfileIDFromMirror()
        let isCurrentFocusProfile =
            mirroredProfileID == profileID ||
            state == .active(profileID)

        guard isCurrentFocusProfile else {
            return
        }

        clearRequestedProfileMirror()
        publishState(.inactive)
    }

    func handleActivationNotification(_ notification: Notification? = nil) {
        didReceiveDeactivationSinceSetup = false
        markKnownConfiguration()

        let requestedProfileID =
            requestedProfileID(from: notification?.userInfo) ??
            requestedProfileIDFromMirror()

        guard let requestedProfileID else {
            diagLog.debug("Focus activation arrived without a requested profile mirror")
            return
        }

        guard isKnownProfile(requestedProfileID) else {
            diagLog.warning("Focus requested missing profile \(requestedProfileID); clearing mirror")
            clearRequestedProfileIfInvalid(requestedProfileID)
            return
        }

        publishState(.active(requestedProfileID))
    }

    func handleDeactivationNotification() {
        didReceiveDeactivationSinceSetup = true
        markKnownConfiguration()
        clearRequestedProfileMirror()
        publishState(.inactive)
    }

    func resyncIfNeeded() async {
        guard shouldAttemptResync else {
            return
        }

        do {
            let currentAction = try await currentProvider.currentAction()

            guard let requestedProfileID = currentAction.requestedProfileID else {
                diagLog.debug("Focus resync found no active profile")
                publishState(.inactive)
                return
            }

            guard isKnownProfile(requestedProfileID) else {
                diagLog.warning("Focus resync found deleted or unreadable profile \(requestedProfileID); clearing mirror")
                clearRequestedProfileMirror()
                publishState(.inactive)
                return
            }

            diagLog.debug("Focus resync restoring active profile \(requestedProfileID)")
            try await currentAction.perform()
            handleActivationNotification(
                Notification(
                    name: FocusFilterConstants.activationNotification,
                    object: nil,
                    userInfo: ["profileID": requestedProfileID.uuidString]
                )
            )
        } catch {
            if isNotConfiguredError(error) {
                defaults.set(false, forKey: FocusFilterConstants.hasKnownConfigurationKey)
                diagLog.debug("Focus resync resolved to notConfigured")
                publishState(.notConfigured)
                return
            }

            diagLog.warning("Focus resync failed: \(error)")
        }
    }

    private func subscribeToNotifications() {
        notificationCenter
            .publisher(for: FocusFilterConstants.activationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleActivationNotification(notification)
            }
            .store(in: &cancellables)

        notificationCenter
            .publisher(for: FocusFilterConstants.deactivationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDeactivationNotification()
            }
            .store(in: &cancellables)
    }

    private func resolveBootstrapState() {
        if let requestedProfileID = requestedProfileIDFromMirror() {
            markKnownConfiguration()

            guard isKnownProfile(requestedProfileID) else {
                diagLog.warning("Focus bootstrap found stale requested profile \(requestedProfileID); clearing mirror")
                clearRequestedProfileMirror()
                publishState(.inactive)
                return
            }

            publishState(.active(requestedProfileID))
            return
        }

        publishState(hasKnownConfiguration ? .inactive : .notConfigured)
    }

    private func scheduleResyncIfNeeded() {
        guard shouldAttemptResync else {
            return
        }

        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            await Task.yield()
            await self?.resyncIfNeeded()
        }
    }

    private var shouldAttemptResync: Bool {
        hasKnownConfiguration &&
            requestedProfileIDFromMirror() == nil &&
            !didReceiveDeactivationSinceSetup
    }

    private var hasKnownConfiguration: Bool {
        defaults.bool(forKey: FocusFilterConstants.hasKnownConfigurationKey)
    }

    private func markKnownConfiguration() {
        defaults.set(true, forKey: FocusFilterConstants.hasKnownConfigurationKey)
    }

    private func publishState(_ newState: FocusFilterState) {
        guard !hasPublishedState || state != newState else {
            return
        }
        state = newState
        hasPublishedState = true
        stateSubject.send(newState)
    }

    private func requestedProfileIDFromMirror() -> UUID? {
        guard let rawValue = defaults.string(forKey: FocusFilterConstants.requestedProfileIDKey) else {
            return nil
        }

        guard let profileID = UUID(uuidString: rawValue) else {
            clearRequestedProfileMirror()
            return nil
        }

        return profileID
    }

    private func requestedProfileID(from userInfo: [AnyHashable: Any]?) -> UUID? {
        guard let rawValue = userInfo?["profileID"] as? String else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func clearRequestedProfileMirror() {
        defaults.removeObject(forKey: FocusFilterConstants.requestedProfileIDKey)
    }

    private func isKnownProfile(_ profileID: UUID) -> Bool {
        profileExists?(profileID) ?? false
    }

    private func isNotConfiguredError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "DNDErrorDomain" && nsError.code == 1007
    }
}
