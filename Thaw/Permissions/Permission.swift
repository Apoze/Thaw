//
//  Permission.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
class Permission: ObservableObject, Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    @Published private(set) var hasPermission = false

    /// The title of the permission.
    let title: String

    /// Descriptive details for the permission.
    let details: [String]

    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?

    /// The function that checks permissions.
    private let check: () -> Bool

    /// The function that requests permissions.
    private let request: () -> Void

    /// Observer that runs on a timer to check permissions.
    private var timerCancellable: AnyCancellable?

    /// Continuations waiting for this permission to be granted.
    private var permissionWaiters = [UUID: CheckedContinuation<Void, Never>]()

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.request = request
        self.hasPermission = check()
        configureCancellables()
    }

    /// Sets up the internal observers for the permission.
    private func configureCancellables() {
        timerCancellable?.cancel()

        let timerPublisher = Timer.publish(every: 3, tolerance: 0.5, on: .main, in: .default)
            .autoconnect()
            .map { _ in }
        let activationPublisher = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .map { _ in }

        timerCancellable = Publishers.Merge3(timerPublisher, Just(()), activationPublisher)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                let granted = refreshStatus()
                if granted {
                    timerCancellable?.cancel()
                    timerCancellable = nil
                }
            }
    }

    /// Performs an immediate permission check and publishes the latest state.
    @discardableResult
    func refreshStatus() -> Bool {
        let granted = check()
        hasPermission = granted
        if granted {
            resumeAllPermissionWaiters()
        }
        return granted
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        request()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// Asynchronously waits for the app to be granted this permission.
    func waitForPermission() async {
        configureCancellables()
        guard !refreshStatus() else {
            return
        }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                permissionWaiters[waiterID] = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.resumePermissionWaiter(withID: waiterID)
            }
        }
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
        resumeAllPermissionWaiters()
    }

    private func resumePermissionWaiter(withID waiterID: UUID) {
        guard let continuation = permissionWaiters.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume()
    }

    private func resumeAllPermissionWaiters() {
        guard !permissionWaiters.isEmpty else {
            return
        }

        let waiters = permissionWaiters.values
        permissionWaiters.removeAll()
        for continuation in waiters {
            continuation.resume()
        }
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Accessibility"),
            details: [
                String(localized: "Observe menu extras and menu bar state in real time."),
                String(localized: "Open and organize menu extras inside Thaw."),
            ],
            isRequired: true,
            settingsURL: nil,
            check: {
                AXHelpers.isProcessTrusted()
            },
            request: {
                AXHelpers.isProcessTrusted(prompt: true)
            }
        )
    }
}
