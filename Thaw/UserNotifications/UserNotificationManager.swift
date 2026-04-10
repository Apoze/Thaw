//
//  UserNotificationManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import UserNotifications

@MainActor
protocol UserNotificationCenterHandling: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func requestAuthorization(options: UNAuthorizationOptions) async throws
    func add(_ request: UNNotificationRequest) async throws
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemUserNotificationCenterAdapter: UserNotificationCenterHandling {
    private let centerProvider: @MainActor () -> UNUserNotificationCenter
    private lazy var center = centerProvider()

    init(centerProvider: @escaping @MainActor () -> UNUserNotificationCenter = { .current() }) {
        self.centerProvider = centerProvider
    }

    var delegate: UNUserNotificationCenterDelegate? {
        get { center.delegate }
        set { center.delegate = newValue }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws {
        _ = try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
protocol UpdateNotificationHandling: AnyObject {
    func requestAuthorization()
    func addRequest(with identifier: UserNotificationIdentifier, title: String, body: String)
    func removeDeliveredNotifications(with identifiers: [UserNotificationIdentifier])
}

/// Manager for user notifications.
@MainActor
final class UserNotificationManager: NSObject, UpdateNotificationHandling {
    private let diagLog = DiagLog(category: "UserNotificationManager")
    struct Dependencies {
        let checkForUpdates: @MainActor () -> Void
    }

    private var dependencies: Dependencies?
    private let notificationCenter: any UserNotificationCenterHandling
    private var hasConfiguredDelegate = false

    init(notificationCenter: (any UserNotificationCenterHandling)? = nil) {
        self.notificationCenter = notificationCenter ?? SystemUserNotificationCenterAdapter()
        super.init()
    }

    /// Performs the initial setup of the manager.
    func performSetup(with dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    private func ensureNotificationCenterDelegate() {
        guard !hasConfiguredDelegate else {
            return
        }
        notificationCenter.delegate = self
        hasConfiguredDelegate = true
    }

    /// Requests authorization to allow user notifications for the app.
    func requestAuthorization() {
        Task {
            do {
                ensureNotificationCenterDelegate()
                try await notificationCenter.requestAuthorization(options: [.badge, .alert, .sound])
            } catch {
                diagLog.error("Failed to request notification authorization: \(error)")
            }
        }
    }

    /// Schedules the delivery of a local notification.
    func addRequest(with identifier: UserNotificationIdentifier, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: identifier.rawValue,
            content: content,
            trigger: nil
        )

        Task {
            do {
                ensureNotificationCenterDelegate()
                try await notificationCenter.add(request)
            } catch {
                diagLog.error("Failed to add notification request: \(error)")
            }
        }
    }

    /// Removes the notifications from Notification Center that match the given identifiers.
    func removeDeliveredNotifications(with identifiers: [UserNotificationIdentifier]) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers.map { $0.rawValue })
    }

    @discardableResult
    func handleNotificationResponse(identifier: String, actionIdentifier: String) -> Bool {
        guard let dependencies else {
            return false
        }

        switch UserNotificationIdentifier(rawValue: identifier) {
        case .updateCheck:
            guard actionIdentifier == UNNotificationDefaultActionIdentifier else {
                return false
            }
            dependencies.checkForUpdates()
            return true
        case nil:
            return false
        }
    }
}

// MARK: UserNotificationManager: UNUserNotificationCenterDelegate

extension UserNotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }

        handleNotificationResponse(
            identifier: response.notification.request.identifier,
            actionIdentifier: response.actionIdentifier
        )
    }
}
