//
//  AppGraphBootstrapTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import XCTest
import UserNotifications
@testable import Thaw

@MainActor
final class AppGraphBootstrapTests: XCTestCase {
    private var savedFirstLaunchValue: Any?

    override func setUp() {
        super.setUp()
        savedFirstLaunchValue = Defaults.object(forKey: .hasCompletedFirstLaunch)
    }

    override func tearDown() {
        if let savedFirstLaunchValue {
            Defaults.set(savedFirstLaunchValue, forKey: .hasCompletedFirstLaunch)
        } else {
            Defaults.removeObject(forKey: .hasCompletedFirstLaunch)
        }
        savedFirstLaunchValue = nil
        super.tearDown()
    }

    func testLaunchWithMissingPermissionsOpensPermissionsWindowAndPausesRuntime() async {
        let permission = TestPermission(isRequired: true, initialGrant: false)
        let appGraph = makeAppGraph(
            permissionService: PermissionService(accessibility: permission),
            isFirstLaunchProvider: { false },
            isPreviewEnvironment: { false },
            conflictWarningHandler: {},
            mainMenuHider: {},
            runtimeSetupOverride: {
                XCTFail("Runtime setup should not start while required permissions are missing")
            }
        )
        let appState = AppState(appGraph: appGraph)

        appGraph.applicationDidFinishLaunching()
        await waitForWindow(.permissions, in: appState)

        XCTAssertFalse(appGraph.hasStartedRuntime)
        XCTAssertTrue(appState.sessionModel.openWindows.contains(.permissions))
        XCTAssertFalse(appState.sessionModel.openWindows.contains(.settings))
    }

    func testLaunchWithGrantedPermissionsStartsRuntimeWithoutPermissionsWindow() async {
        let permission = TestPermission(isRequired: true, initialGrant: true)
        let runtimeStarted = expectation(description: "Runtime setup started")
        let appGraph = makeAppGraph(
            permissionService: PermissionService(accessibility: permission),
            isFirstLaunchProvider: { false },
            isPreviewEnvironment: { false },
            conflictWarningHandler: {},
            mainMenuHider: {},
            runtimeSetupOverride: {
                runtimeStarted.fulfill()
            }
        )
        let appState = AppState(appGraph: appGraph)

        appGraph.applicationDidFinishLaunching()
        await fulfillment(of: [runtimeStarted], timeout: 1)
        await settleMainQueue()

        XCTAssertTrue(appGraph.hasStartedRuntime)
        XCTAssertFalse(appState.sessionModel.openWindows.contains(.permissions))
    }

    func testCompletingPermissionsFlowDismissesPermissionsAndOpensSettings() async {
        let permission = TestPermission(isRequired: true, initialGrant: false)
        let runtimeStarted = expectation(description: "Runtime setup started after permissions flow")
        let appGraph = makeAppGraph(
            permissionService: PermissionService(accessibility: permission),
            isFirstLaunchProvider: { false },
            isPreviewEnvironment: { false },
            conflictWarningHandler: {},
            mainMenuHider: {},
            runtimeSetupOverride: {
                runtimeStarted.fulfill()
            }
        )
        let appState = AppState(appGraph: appGraph)

        appGraph.applicationDidFinishLaunching()
        await waitForWindow(.permissions, in: appState)
        XCTAssertTrue(appState.sessionModel.openWindows.contains(.permissions))

        permission.setGranted(true)
        appGraph.completePermissionsFlow()

        await fulfillment(of: [runtimeStarted], timeout: 1)
        await waitForWindow(.settings, in: appState)

        XCTAssertTrue(appGraph.hasStartedRuntime)
        XCTAssertFalse(appState.sessionModel.openWindows.contains(.permissions))
        XCTAssertTrue(appState.sessionModel.openWindows.contains(.settings))
        XCTAssertTrue(Defaults.bool(forKey: .hasCompletedFirstLaunch))
    }

    func testApplicationShouldHandleReopenOpensSettingsWindow() async {
        let permission = TestPermission(isRequired: true, initialGrant: true)
        let appGraph = makeAppGraph(
            permissionService: PermissionService(accessibility: permission),
            isFirstLaunchProvider: { false },
            isPreviewEnvironment: { false },
            conflictWarningHandler: {},
            mainMenuHider: {}
        )
        let appState = AppState(appGraph: appGraph)

        XCTAssertTrue(appGraph.applicationShouldHandleReopen())
        await waitForWindow(.settings, in: appState)

        XCTAssertTrue(appState.sessionModel.openWindows.contains(.settings))
    }

    func testIncomingSettingsURLRoutesThroughAppGraphToOpenSettingsWindow() async throws {
        let permission = TestPermission(isRequired: true, initialGrant: true)
        let appGraph = makeAppGraph(
            permissionService: PermissionService(accessibility: permission),
            isFirstLaunchProvider: { false },
            isPreviewEnvironment: { false },
            conflictWarningHandler: {},
            mainMenuHider: {}
        )
        let appState = AppState(appGraph: appGraph)

        let url = try XCTUnwrap(URL(string: "thaw://settings"))
        appGraph.handleIncomingURL(url)
        await waitForWindow(.settings, in: appState)

        XCTAssertTrue(appState.sessionModel.openWindows.contains(.settings))
    }

    func testSecondStartupBootstrapDoesNotRepeatLayoutCompatibilityMigration() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppGraphBootstrapTests.\(UUID().uuidString)", isDirectory: true)
        let paths = ThawPersistencePaths(rootDirectory: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let legacyLayout = ProfileLayoutV2(
            groupsByIdentityID: ["11111111-1111-1111-1111-111111111111": .archive],
            orderedIdentityIDsByGroup: [.archive: ["11111111-1111-1111-1111-111111111111"]],
            customNamesByIdentityID: ["11111111-1111-1111-1111-111111111111": "Legacy Alpha"]
        )
        let legacyEnvelope = PersistentEnvelope(
            schemaVersion: 3,
            payload: legacyLayout,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacyEnvelope).write(to: paths.layoutV3URL, options: .atomic)

        let firstAppGraph = makeAppGraph(
            fileManager: .default,
            persistencePaths: paths
        )
        await firstAppGraph.performStartupBootstrap()

        let migratedEnvelope = try JSONDecoder().decode(
            PersistentEnvelope<ProfileLayoutV3>.self,
            from: Data(contentsOf: paths.layoutV3URL)
        )
        XCTAssertEqual(migratedEnvelope.payload, ProfileLayoutMigration.migrate(legacyLayout))

        let migratedLayoutData = try Data(contentsOf: paths.layoutV3URL)
        let bookkeepingURL = paths.runtimeDirectory.appendingPathComponent("migration-metadata-v1.json")
        let bookkeepingData = try Data(contentsOf: bookkeepingURL)
        let bookkeepingDecoder = JSONDecoder()
        bookkeepingDecoder.dateDecodingStrategy = .iso8601
        let firstBookkeeping = try bookkeepingDecoder.decode(
            PersistentEnvelope<MigrationCoordinator.MigrationBookkeepingSnapshot>.self,
            from: bookkeepingData
        )
        XCTAssertTrue(
            firstBookkeeping.payload.completedMigrationIdentifiers.contains("runtime.layout.compatibility-upgrade")
        )

        let secondAppGraph = makeAppGraph(
            fileManager: .default,
            persistencePaths: paths
        )
        await secondAppGraph.performStartupBootstrap()

        XCTAssertEqual(migratedLayoutData, try Data(contentsOf: paths.layoutV3URL))
        XCTAssertEqual(bookkeepingData, try Data(contentsOf: bookkeepingURL))

        let secondBookkeeping = try bookkeepingDecoder.decode(
            PersistentEnvelope<MigrationCoordinator.MigrationBookkeepingSnapshot>.self,
            from: Data(contentsOf: bookkeepingURL)
        )
        XCTAssertEqual(
            secondBookkeeping.payload.completedMigrationIdentifiers,
            firstBookkeeping.payload.completedMigrationIdentifiers
        )
        XCTAssertEqual(
            secondBookkeeping.payload.completedSchemaVersions,
            firstBookkeeping.payload.completedSchemaVersions
        )
    }

    func testAppGraphDoesNotWireAXRuntimeDirectly() throws {
        let source = try ThawTestResourceSupport.sourceText(named: "AppGraph")

        XCTAssertFalse(source.contains("lazy var axRuntime"))
        XCTAssertFalse(source.contains("AXRuntime("))
        XCTAssertTrue(source.contains("AXActivationExecutor(identityRegistry: identityRegistry)"))
    }

    func testAppGraphRoutesStartupMigrationsThroughStartupMigrationRunner() throws {
        let source = try ThawTestResourceSupport.sourceText(named: "AppGraph")

        XCTAssertTrue(source.contains("private let startupMigrationRunner: StartupMigrationRunner"))
        XCTAssertTrue(source.contains("let reports = try await startupMigrationRunner.perform()"))
        XCTAssertTrue(source.contains("menuBarPresentationService.performSetup(with: .init("))
        XCTAssertFalse(source.contains("MigrationCoordinator.MigrationStep("))
        XCTAssertFalse(source.contains("func startupMigrationSteps()"))
        XCTAssertFalse(source.contains("menuBarPresentationService.performSetup(with appState:"))
    }

    func testAppGraphWiresProfilesServiceThroughRuntimeContextOnly() throws {
        let source = try ThawTestResourceSupport.sourceText(named: "AppGraph")

        XCTAssertTrue(source.contains("makeProfileRuntimeContext()"))
        XCTAssertTrue(source.contains("profilesService.performSetup("))
        XCTAssertFalse(source.contains("profilesService.performSetup(\n            with: appState,"))
        XCTAssertFalse(source.contains("ProfileRuntimeContext(appState:"))
    }

    func testAppGraphWiresUpdatesAndNotificationsThroughExplicitDependencies() throws {
        let source = try ThawTestResourceSupport.sourceText(named: "AppGraph")

        XCTAssertTrue(source.contains("userNotificationManager.performSetup(with: .init("))
        XCTAssertTrue(source.contains("updatesManager.performSetup(with: .init("))
        XCTAssertTrue(source.contains("notificationManager: appState.userNotificationManager"))
        XCTAssertTrue(source.contains("checkForUpdates: { [weak appState] in"))
        XCTAssertFalse(source.contains("performSetup(with appState:"))
    }

    func testUpdatesAndNotificationsBoundaryFilesUseDependenciesInsteadOfAppState() throws {
        let updatesSource = try ThawTestResourceSupport.sourceText(named: "Updates")
        let userNotificationSource = try ThawTestResourceSupport.sourceText(named: "UserNotificationManager")

        XCTAssertTrue(updatesSource.contains("struct Dependencies"))
        XCTAssertTrue(updatesSource.contains("activateApp"))
        XCTAssertTrue(updatesSource.contains("openSettings"))
        XCTAssertTrue(updatesSource.contains("notificationManager: any UpdateNotificationHandling"))
        XCTAssertFalse(updatesSource.contains("AppState"))
        XCTAssertFalse(updatesSource.contains("performSetup(with appState:"))

        XCTAssertTrue(userNotificationSource.contains("struct Dependencies"))
        XCTAssertTrue(userNotificationSource.contains("checkForUpdates"))
        XCTAssertTrue(userNotificationSource.contains("handleNotificationResponse(identifier:"))
        XCTAssertFalse(userNotificationSource.contains("AppState"))
        XCTAssertFalse(userNotificationSource.contains("performSetup(with appState:"))
    }

    func testWindowSessionBoundaryUsesExplicitWindowCommandsInsteadOfEnvironmentAccess() throws {
        let sessionSource = try ThawTestResourceSupport.sourceText(named: "AppSessionModel")
        let iceWindowSource = try ThawTestResourceSupport.sourceText(named: "IceWindow")
        let settingsWindowSource = try ThawTestResourceSupport.sourceText(named: "SettingsWindow")
        let permissionsWindowSource = try ThawTestResourceSupport.sourceText(named: "PermissionsWindow")

        XCTAssertTrue(sessionSource.contains("struct WindowCommands"))
        XCTAssertTrue(sessionSource.contains("func performSetup(windowCommands: WindowCommands)"))
        XCTAssertTrue(sessionSource.contains("func bindWindow(_ id: IceWindowIdentifier, to window: NSWindow?)"))
        XCTAssertFalse(sessionSource.contains("EnvironmentValues()"))
        XCTAssertFalse(sessionSource.contains("publisher(for: \\.windows)"))

        XCTAssertTrue(iceWindowSource.contains("installWindowCommands"))
        XCTAssertTrue(iceWindowSource.contains("openWindow(id: windowID)"))
        XCTAssertTrue(iceWindowSource.contains("dismissWindow(id: windowID)"))

        XCTAssertTrue(settingsWindowSource.contains("adapter.performSetup(windowCommands: .init("))
        XCTAssertTrue(settingsWindowSource.contains("adapter.bindWindow(window)"))
        XCTAssertTrue(permissionsWindowSource.contains("adapter.performSetup(windowCommands: .init("))
        XCTAssertTrue(permissionsWindowSource.contains("adapter.bindWindow(window)"))
    }

    func testUserNotificationManagerRoutesUpdateCheckNotificationResponsesToInjectedClosure() {
        var didRouteUpdateCheck = false
        let manager = UserNotificationManager(notificationCenter: StubUserNotificationCenter())
        manager.performSetup(with: .init(checkForUpdates: {
            didRouteUpdateCheck = true
        }))

        let handled = manager.handleNotificationResponse(
            identifier: UserNotificationIdentifier.updateCheck.rawValue,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didRouteUpdateCheck)
    }

    func testUpdatesManagerRequestsNotificationAuthorizationWhenSparkleSchedulesACheck() {
        let notificationManager = NotificationManagerSpy()
        let updatesManager = UpdatesManager()
        updatesManager.performSetup(with: .init(
            activateApp: {},
            openSettings: {},
            notificationManager: notificationManager
        ))

        updatesManager.updater(updatesManager.updater, willScheduleUpdateCheckAfterDelay: 1)

        XCTAssertEqual(notificationManager.requestAuthorizationCallCount, 1)
    }

    private func settleMainQueue() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    private func makeAppGraph(
        permissionService: PermissionService? = nil,
        fileManager: FileManager = .default,
        persistencePaths: ThawPersistencePaths? = nil,
        isFirstLaunchProvider: (() -> Bool)? = nil,
        isPreviewEnvironment: (() -> Bool)? = nil,
        conflictWarningHandler: (@MainActor () -> Void)? = nil,
        mainMenuHider: (@MainActor () -> Void)? = nil,
        runtimeSetupOverride: (@MainActor () async -> Void)? = nil,
        migrationCoordinator: MigrationCoordinator? = nil
    ) -> AppGraph {
        AppGraph(
            permissionService: permissionService,
            fileManager: fileManager,
            persistencePaths: persistencePaths,
            isFirstLaunchProvider: isFirstLaunchProvider,
            isPreviewEnvironment: isPreviewEnvironment,
            conflictWarningHandler: conflictWarningHandler,
            mainMenuHider: mainMenuHider,
            systemPresentationOptionsPublisherFactory: {
                Empty<NSApplication.PresentationOptions, Never>().eraseToAnyPublisher()
            },
            runtimeSetupOverride: runtimeSetupOverride,
            migrationCoordinator: migrationCoordinator
        )
    }

    private func waitForWindow(
        _ id: IceWindowIdentifier,
        in appState: AppState,
        timeout: Duration = .milliseconds(500)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if appState.sessionModel.openWindows.contains(id) {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}

@MainActor
private final class TestPermission: Permission {
    private let storage: PermissionStorage

    init(isRequired: Bool, initialGrant: Bool) {
        storage = PermissionStorage(isGranted: initialGrant)
        super.init(
            title: "Test Permission",
            details: [],
            isRequired: isRequired,
            settingsURL: nil,
            check: { [storage] in
                storage.isGranted
            },
            request: {}
        )
    }

    func setGranted(_ newValue: Bool) {
        storage.isGranted = newValue
    }
}

private final class PermissionStorage {
    var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }
}

@MainActor
private final class StubUserNotificationCenter: UserNotificationCenterHandling {
    weak var delegate: UNUserNotificationCenterDelegate?

    func requestAuthorization(options _: UNAuthorizationOptions) async throws {}

    func add(_: UNNotificationRequest) async throws {}

    func removeDeliveredNotifications(withIdentifiers _: [String]) {}
}

@MainActor
private final class NotificationManagerSpy: UpdateNotificationHandling {
    private(set) var requestAuthorizationCallCount = 0
    private(set) var addedRequests = [(UserNotificationIdentifier, String, String)]()
    private(set) var removedDeliveredNotifications = [[UserNotificationIdentifier]]()

    func requestAuthorization() {
        requestAuthorizationCallCount += 1
    }

    func addRequest(with identifier: UserNotificationIdentifier, title: String, body: String) {
        addedRequests.append((identifier, title, body))
    }

    func removeDeliveredNotifications(with identifiers: [UserNotificationIdentifier]) {
        removedDeliveredNotifications.append(identifiers)
    }
}
