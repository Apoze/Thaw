//
//  WorkspaceEventSource.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

struct WorkspaceApplicationInfo: Equatable, Sendable {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let isCurrentApplication: Bool

    var activationSignature: String {
        let bundleID = bundleIdentifier ?? "unknown-bundle"
        return "\(bundleID)#\(processIdentifier)"
    }
}

@MainActor
final class WorkspaceEventSource: ObservableObject {
    enum Event: Equatable, Sendable {
        case applicationLaunched(WorkspaceApplicationInfo)
        case applicationTerminated(WorkspaceApplicationInfo)
        case applicationActivated(WorkspaceApplicationInfo)
        case activeSpaceChanged
        case displayConfigurationChanged
        case menuBarContextChanged
    }

    struct Environment {
        let workspaceNotificationCenter: NotificationCenter
        let applicationNotificationCenter: NotificationCenter
        let initialFrontmostApplication: () -> WorkspaceApplicationInfo?
        let frontmostApplicationPublisher: AnyPublisher<WorkspaceApplicationInfo?, Never>
        let menuBarOwningApplicationPublisher: AnyPublisher<WorkspaceApplicationInfo?, Never>

        static func live(workspace: NSWorkspace = .shared) -> Environment {
            Environment(
                workspaceNotificationCenter: workspace.notificationCenter,
                applicationNotificationCenter: .default,
                initialFrontmostApplication: {
                    WorkspaceApplicationInfo.make(from: workspace.frontmostApplication)
                },
                frontmostApplicationPublisher: workspace.publisher(for: \.frontmostApplication)
                    .map(WorkspaceApplicationInfo.make(from:))
                    .eraseToAnyPublisher(),
                menuBarOwningApplicationPublisher: workspace.publisher(for: \.menuBarOwningApplication)
                    .map(WorkspaceApplicationInfo.make(from:))
                    .eraseToAnyPublisher()
            )
        }
    }

    @Published private(set) var frontmostApplication: WorkspaceApplicationInfo?
    @Published private(set) var isThawFrontmost = false
    @Published private(set) var activeSpace: SpaceInfo

    private let environment: Environment
    private let eventSubject = PassthroughSubject<Event, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var hasPerformedSetup = false

    init(environment: Environment = .live()) {
        self.environment = environment
        let initialFrontmostApplication = environment.initialFrontmostApplication()
        frontmostApplication = initialFrontmostApplication
        isThawFrontmost = initialFrontmostApplication?.isCurrentApplication == true
        activeSpace = Self.currentActiveSpace()
    }

    var eventPublisher: AnyPublisher<Event, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    var invalidationPublisher: AnyPublisher<DiscoveryInvalidation, Never> {
        eventPublisher
            .compactMap { event in
                switch event {
                case .applicationLaunched(let info):
                    return .appLaunched(
                        bundleID: info.bundleIdentifier,
                        processIdentifier: info.processIdentifier
                    )
                case .applicationTerminated(let info):
                    return .appTerminated(
                        bundleID: info.bundleIdentifier,
                        processIdentifier: info.processIdentifier
                    )
                case .applicationActivated(let info):
                    return .appActivated(
                        bundleID: info.bundleIdentifier,
                        processIdentifier: info.processIdentifier
                    )
                case .displayConfigurationChanged:
                    return .displayConfigurationChanged
                case .activeSpaceChanged, .menuBarContextChanged:
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }

    var activeSpaceDidChangePublisher: AnyPublisher<Void, Never> {
        eventPublisher
            .compactMap { event in
                guard case .activeSpaceChanged = event else {
                    return nil
                }
                return ()
            }
            .eraseToAnyPublisher()
    }

    var displayConfigurationDidChangePublisher: AnyPublisher<Void, Never> {
        eventPublisher
            .compactMap { event in
                guard case .displayConfigurationChanged = event else {
                    return nil
                }
                return ()
            }
            .eraseToAnyPublisher()
    }

    var menuBarContextDidChangePublisher: AnyPublisher<Void, Never> {
        eventPublisher
            .compactMap { event in
                guard case .menuBarContextChanged = event else {
                    return nil
                }
                return ()
            }
            .eraseToAnyPublisher()
    }

    func performSetup() {
        guard !hasPerformedSetup else {
            frontmostApplication = environment.initialFrontmostApplication()
            isThawFrontmost = frontmostApplication?.isCurrentApplication == true
            activeSpace = Self.currentActiveSpace()
            return
        }

        hasPerformedSetup = true

        environment.workspaceNotificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap(Self.applicationInfo(from:))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.eventSubject.send(.applicationLaunched(info))
            }
            .store(in: &cancellables)

        environment.workspaceNotificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap(Self.applicationInfo(from:))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.eventSubject.send(.applicationTerminated(info))
            }
            .store(in: &cancellables)

        environment.workspaceNotificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap(Self.applicationInfo(from:))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else {
                    return
                }
                frontmostApplication = info
                isThawFrontmost = info.isCurrentApplication
                eventSubject.send(.applicationActivated(info))
            }
            .store(in: &cancellables)

        environment.workspaceNotificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                activeSpace = Self.currentActiveSpace()
                eventSubject.send(.activeSpaceChanged)
            }
            .store(in: &cancellables)

        environment.applicationNotificationCenter
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.eventSubject.send(.displayConfigurationChanged)
            }
            .store(in: &cancellables)

        environment.frontmostApplicationPublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else {
                    return
                }
                frontmostApplication = info
                isThawFrontmost = info?.isCurrentApplication == true
                eventSubject.send(.menuBarContextChanged)
            }
            .store(in: &cancellables)

        environment.menuBarOwningApplicationPublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.eventSubject.send(.menuBarContextChanged)
            }
            .store(in: &cancellables)
    }

    private static func applicationInfo(from notification: Notification) -> WorkspaceApplicationInfo? {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return WorkspaceApplicationInfo.make(from: app)
    }

    private static func currentActiveSpace() -> SpaceInfo {
        guard NSApp != nil else {
            return SpaceInfo(isFullscreen: false)
        }
        return SpaceInfo.activeSpace()
    }
}

private extension WorkspaceApplicationInfo {
    static func make(from app: NSRunningApplication?) -> WorkspaceApplicationInfo? {
        guard let app else {
            return nil
        }

        return WorkspaceApplicationInfo(
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            isCurrentApplication: app.processIdentifier == NSRunningApplication.current.processIdentifier
        )
    }
}
