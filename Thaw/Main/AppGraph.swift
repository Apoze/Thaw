//
//  AppGraph.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation

@MainActor
final class AppGraph {
    private weak var appState: AppState?
    private let diagLog = DiagLog(category: .startup)
    private let fileManager: FileManager
    private let persistencePaths: ThawPersistencePaths
    private let isFirstLaunchProvider: () -> Bool
    private let isPreviewEnvironment: () -> Bool
    private let conflictWarningHandler: @MainActor () -> Void
    private let mainMenuHider: @MainActor () -> Void
    private let systemPresentationOptionsPublisherFactory: @MainActor () -> AnyPublisher<NSApplication.PresentationOptions, Never>
    private let runtimeSetupOverride: (@MainActor () async -> Void)?
    private let startupMigrationRunner: StartupMigrationRunner
    private(set) var hasStartedRuntime = false

    let permissionService: PermissionService
    let workspaceEventSource: WorkspaceEventSource
    let displayService: DisplayService
    lazy var identityRegistry = IdentityRegistry(
        fileManager: fileManager,
        paths: persistencePaths
    )
    lazy var axObservationService = AXObservationService(identityRegistry: identityRegistry)
    lazy var layoutService = LayoutService(
        fileManager: fileManager,
        paths: persistencePaths
    )
    lazy var discoveryService = DiscoveryService(
        displayService: displayService,
        identityRegistry: identityRegistry,
        workspaceEventSource: workspaceEventSource,
        observationService: axObservationService,
        layoutService: layoutService
    )
    lazy var activationService = ActivationService(
        executor: AXActivationExecutor(identityRegistry: identityRegistry),
        contextProvider: discoveryService,
        displayService: displayService
    )
    lazy var discoverySession = DiscoverySession(
        service: discoveryService,
        workspaceEventSource: workspaceEventSource
    )
    let focusFilterService = FocusFilterService()
    let menuBarPresentationService = MenuBarPresentationService()
    let menuChromeController = MenuChromeController()
    let commandRouter = CommandRouter()
    let panelService = PanelService()
    let profilesService = ProfilesService()
    lazy var profileManager = ProfileManager(service: profilesService)

    init(
        permissionService: PermissionService? = nil,
        fileManager: FileManager = .default,
        persistencePaths: ThawPersistencePaths? = nil,
        isFirstLaunchProvider: (() -> Bool)? = nil,
        isPreviewEnvironment: (() -> Bool)? = nil,
        conflictWarningHandler: (@MainActor () -> Void)? = nil,
        mainMenuHider: (@MainActor () -> Void)? = nil,
        systemPresentationOptionsPublisherFactory: (@MainActor () -> AnyPublisher<NSApplication.PresentationOptions, Never>)? = nil,
        runtimeSetupOverride: (@MainActor () async -> Void)? = nil,
        migrationCoordinator: MigrationCoordinator? = nil
    ) {
        self.permissionService = permissionService ?? PermissionService()
        self.fileManager = fileManager
        let resolvedPersistencePaths = persistencePaths ?? .default(fileManager: fileManager)
        self.persistencePaths = resolvedPersistencePaths
        let resolvedMigrationCoordinator = migrationCoordinator ?? MigrationCoordinator(
            fileManager: fileManager,
            paths: resolvedPersistencePaths
        )
        self.startupMigrationRunner = StartupMigrationRunner(
            migrationCoordinator: resolvedMigrationCoordinator,
            fileManager: fileManager,
            paths: resolvedPersistencePaths
        )
        self.isFirstLaunchProvider = isFirstLaunchProvider ?? {
            !Defaults.bool(forKey: .hasCompletedFirstLaunch)
        }
        self.isPreviewEnvironment = isPreviewEnvironment ?? {
            #if DEBUG
                ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            #else
                false
            #endif
        }
        self.conflictWarningHandler = conflictWarningHandler ?? {
            ConflictingAppDetector.showWarningIfNeeded()
        }
        self.mainMenuHider = mainMenuHider ?? {
            for item in NSApp.mainMenu?.items ?? [] {
                item.isHidden = true
            }
        }
        self.systemPresentationOptionsPublisherFactory = systemPresentationOptionsPublisherFactory ?? {
            NSApp.publisher(for: \.currentSystemPresentationOptions).eraseToAnyPublisher()
        }
        self.runtimeSetupOverride = runtimeSetupOverride
        let workspaceEventSource = WorkspaceEventSource()
        self.workspaceEventSource = workspaceEventSource
        displayService = DisplayService(workspaceEventSource: workspaceEventSource)
    }

    lazy var iceBarAdapter = IceBarAdapter(
        sessionModel: resolvedSessionModel,
        discoverySession: discoverySession,
        panelInteractionController: activationService,
        panelService: panelService,
        permissions: permissionService,
        generalSettings: resolvedAppState.settings.general,
        advancedSettings: resolvedAppState.settings.advanced,
        displaySettings: resolvedAppState.settings.displaySettings,
        menuChromeController: menuChromeController,
        appearanceManager: resolvedAppState.appearanceManager,
        menuBarPresentationService: menuBarPresentationService,
        activeSpaceDidChangePublisher: workspaceEventSource.activeSpaceDidChangePublisher,
        displayConfigurationDidChangePublisher: displayService.displayConfigurationDidChangePublisher
    )
    lazy var searchPanelAdapter = MenuBarSearchPanelAdapter(
        sessionModel: resolvedSessionModel,
        searchAdapter: MenuBarSearchAdapter(
            discoverySession: discoverySession,
            panelInteractionController: activationService
        ),
        commandRouter: commandRouter,
        panelService: panelService,
        activeSpaceDidChangePublisher: workspaceEventSource.activeSpaceDidChangePublisher,
        displayConfigurationDidChangePublisher: displayService.displayConfigurationDidChangePublisher
    )
    lazy var hotkeySessionAdapter = HotkeySessionAdapter(
        registry: resolvedAppState.settings.hotkeys.registry,
        profilesService: profilesService,
        commandRouter: commandRouter
    )
    lazy var settingsSessionAdapter = SettingsSessionAdapter(
        settings: resolvedAppState.settings,
        layoutEditorAdapter: layoutEditorAdapter,
        appearanceManager: resolvedAppState.appearanceManager,
        appearanceEditorAdapter: appearanceEditorAdapter,
        profileManager: profileManager,
        updatesManager: resolvedAppState.updatesManager,
        permissions: permissionService
    )
    lazy var settingsWindowAdapter = SettingsWindowAdapter(
        sessionModel: resolvedSessionModel,
        navigationState: resolvedSessionModel.navigationState,
        session: settingsSessionAdapter,
        updatesManager: resolvedAppState.updatesManager
    )
    lazy var permissionsFlowAdapter = PermissionsFlowAdapter(
        sessionModel: resolvedSessionModel,
        completePermissionsFlowHandler: { [weak self] in
            self?.completePermissionsFlow()
        }
    )
    lazy var permissionsWindowAdapter = PermissionsWindowAdapter(
        manager: permissionService,
        flowAdapter: permissionsFlowAdapter,
        sessionModel: resolvedSessionModel
    )
    lazy var menuBarSessionAdapter = MenuBarSessionAdapter(
        settings: resolvedAppState.settings,
        profilesService: profilesService,
        panelService: panelService,
        menuChromeController: menuChromeController,
        commandRouter: commandRouter
    )
    lazy var menuBarOverlayAdapter = MenuBarOverlayAdapter(
        sessionModel: resolvedSessionModel,
        appearanceManager: resolvedAppState.appearanceManager,
        menuBarPresentationService: menuBarPresentationService,
        menuChromeController: menuChromeController,
        activeSpaceDidChangePublisher: workspaceEventSource.activeSpaceDidChangePublisher,
        displayConfigurationDidChangePublisher: displayService.displayConfigurationDidChangePublisher,
        menuBarContextDidChangePublisher: workspaceEventSource.menuBarContextDidChangePublisher
    )
    lazy var layoutEditorAdapter = MenuBarLayoutEditorAdapter(
        discoverySession: discoverySession
    )
    lazy var appearanceEditorAdapter = MenuBarAppearanceEditorAdapter(
        appearanceManager: resolvedAppState.appearanceManager,
        menuBarPresentationService: menuBarPresentationService,
        advancedSettings: resolvedAppState.settings.advanced
    )

    func attach(appState: AppState) {
        self.appState = appState
        commandRouter.performSetup(with: .init(
            toggleGroup: { [weak self] group, triggeredByHotkey in
                self?.panelService.toggle(group: group, triggeredByHotkey: triggeredByHotkey)
            },
            togglePrimarySurface: { [weak self] triggeredByHotkey in
                self?.panelService.togglePrimarySurface(triggeredByHotkey: triggeredByHotkey)
            },
            openSearch: { [weak self] in
                self?.panelService.toggleSearch()
            },
            openSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            checkForUpdates: { [weak self] in
                self?.resolvedAppState.updatesManager.checkForUpdates()
            },
            applyProfile: { [weak self] profileID in
                Task { @MainActor [weak self] in
                    try? await self?.profilesService.applyProfile(id: profileID)
                }
            }
        ))
    }

    func applicationDidFinishLaunching() {
        guard let appState else {
            return
        }

        guard !isPreviewEnvironment() else {
            return
        }

        mainMenuHider()
        conflictWarningHandler()

        let isFirstLaunch = isFirstLaunchProvider()
        let permissionsState = permissionService.refreshPermissions()
        if isFirstLaunch || permissionsState == .missing {
            appState.openWindow(.permissions)
        }

        guard permissionsState != .missing else {
            diagLog.debug("Startup paused until required permissions are granted")
            return
        }

        startRuntimeIfNeeded()
    }

    func completePermissionsFlow() {
        guard let appState else {
            return
        }

        let permissionsState = permissionService.refreshPermissions()
        guard permissionsState != .missing else {
            diagLog.debug("Permissions flow completed without the required permission state")
            return
        }

        Defaults.set(true, forKey: .hasCompletedFirstLaunch)
        appState.dismissWindow(.permissions)
        startRuntimeIfNeeded()

        Task { @MainActor [weak self] in
            guard let appState = self?.appState else {
                return
            }
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }

    private var resolvedAppState: AppState {
        guard let appState else {
            preconditionFailure("AppGraph accessed before being attached to AppState")
        }
        return appState
    }

    private var resolvedSessionModel: AppSessionModel {
        resolvedAppState.sessionModel
    }

    private func startRuntimeIfNeeded() {
        guard !hasStartedRuntime else {
            return
        }

        hasStartedRuntime = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if let runtimeSetupOverride {
                await runtimeSetupOverride()
            } else {
                await performRuntimeSetup()
            }
        }
    }

    private func performRuntimeSetup() async {
        let appState = resolvedAppState

        if Defaults.bool(forKey: .enableDiagnosticLogging) {
            DiagnosticLogger.shared.isEnabled = true
        }

        diagLog.debug("Starting runtime setup sequence")
        permissionService.stopAllChecks()
        await performStartupBootstrap()
        appState.settings.performSetup(with: .init(
            hotkeySessionAdapter: hotkeySessionAdapter,
            displayService: displayService
        ))
        appState.appearanceManager.performSetup(with: .init(
            displayService: displayService,
            menuBarOverlayAdapter: menuBarOverlayAdapter
        ))
        appState.userNotificationManager.performSetup(with: .init(
            checkForUpdates: { [weak self] in
                guard let appState = self?.appState else {
                    return
                }
                appState.updatesManager.checkForUpdates()
            }
        ))
        appState.updatesManager.performSetup(with: .init(
            activateApp: { [weak self] in
                guard let appState = self?.appState else {
                    return
                }
                appState.activate(withPolicy: .regular)
            },
            openSettings: { [weak self] in
                guard let appState = self?.appState else {
                    return
                }
                appState.openWindow(.settings)
            },
            notificationManager: appState.userNotificationManager
        ))

        workspaceEventSource.performSetup()
        displayService.performSetup()
        menuBarPresentationService.performSetup(with: .init(
            systemPresentationOptionsPublisher: systemPresentationOptionsPublisherFactory(),
            activeSpaceDidChangePublisher: workspaceEventSource.activeSpaceDidChangePublisher.eraseToAnyPublisher(),
            displayConfigurationDidChangePublisher: displayService.displayConfigurationDidChangePublisher.eraseToAnyPublisher(),
            settingsWindowVisibilityPublisher: resolvedAppState.publisherForWindowVisibility(.settings)
        ))
        menuChromeController.performSetup(with: .init(
            generalSettings: appState.settings.general,
            commandRouter: commandRouter,
            displayService: displayService,
            iceBarAdapter: iceBarAdapter,
            searchPanelAdapter: searchPanelAdapter,
            appearanceManager: appState.appearanceManager,
            appearanceEditorAdapter: appearanceEditorAdapter
        ))
        panelService.performSetup(with: .init(
            menuChromeController: menuChromeController,
            discoverySession: discoverySession,
            displayService: displayService,
            displaySettings: appState.settings.displaySettings
        ))
        discoverySession.performSetup()
        profilesService.performSetup(
            runtimeContext: makeProfileRuntimeContext(),
            focusFilterService: focusFilterService
        )
        focusFilterService.performSetup { [weak profilesService] profileID in
            profilesService?.hasProfile(id: profileID) ?? false
        }

        appState.completeRuntimeSetupIfNeeded()
        warmActivationPolicy()
        diagLog.debug("Runtime setup sequence complete")
    }

    func performStartupBootstrap() async {
        do {
            let reports = try await startupMigrationRunner.perform()
            if !reports.isEmpty {
                diagLog.info("Completed \(reports.count) startup migration step(s)")
            }
        } catch {
            diagLog.error("Startup migrations failed: \(error)")
        }
    }

    private func makeProfileRuntimeContext() -> ProfileRuntimeContext {
        let appState = resolvedAppState
        return ProfileRuntimeContext(
            generalSettings: appState.settings.general,
            advancedSettings: appState.settings.advanced,
            hotkeysSettings: appState.settings.hotkeys,
            displaySettings: appState.settings.displaySettings,
            appearanceManager: appState.appearanceManager,
            discoverySession: discoverySession,
            displayConfigurationDidChangePublisher: displayService.displayConfigurationDidChangePublisher,
            currentDisplayUUIDProvider: { [weak self] in
                self?.displayService.activeDisplayUUID
            },
            hotkeySetupHandler: { [weak self] hotkey in
                guard let self else {
                    return
                }
                hotkey.performSetup(with: self.hotkeySessionAdapter)
            }
        )
    }

    private func warmActivationPolicy() {
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen() -> Bool {
        diagLog.debug("Handling reopen from app icon click")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let appState = resolvedAppState
        if sender.isActive, sender.activationPolicy() != .accessory, appState.navigationState.isAppFrontmost {
            diagLog.debug("All windows closed - deactivating with accessory activation policy")
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationWillTerminate() {
        diagLog.info("Application will terminate")
    }

    func handleIncomingURL(_ url: URL) {
        commandRouter.route(url: url)
    }

    func openSettingsWindow() {
        diagLog.debug("Opening settings window from app icon/dock/menu click")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let appState = self?.appState else {
                return
            }
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
