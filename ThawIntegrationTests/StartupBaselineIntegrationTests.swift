//
//  StartupBaselineIntegrationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import XCTest
@testable import Thaw

@MainActor
final class StartupBaselineIntegrationTests: XCTestCase {
    func testAppGraphComposesCoreServicesWithoutFocusBootstrap() {
        let appGraph = makeAppGraph()

        XCTAssertEqual(appGraph.focusFilterService.state, .notConfigured)
        XCTAssertNotNil(appGraph.permissionService)
        XCTAssertNotNil(appGraph.displayService)
        XCTAssertNotNil(appGraph.commandRouter)
        XCTAssertNotNil(appGraph.panelService)
        XCTAssertNotNil(appGraph.menuChromeController)
    }

    func testAppGraphCommandRouterResolvesCoreExternalCommands() {
        let appGraph = makeAppGraph()

        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://panel")!),
            .toggleGroup(.hidden)
        )
        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://archive")!),
            .toggleGroup(.archive)
        )
        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://settings")!),
            .openSettings
        )
        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://surface")!),
            .toggleThawBar
        )
        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://search")!),
            .openSearch
        )
    }

    func testAppGraphCommandRouterResolvesLegacyExternalCommandsDuringCompatibilityWindow() {
        let appGraph = makeAppGraph()

        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://toggle-hidden")!),
            .toggleGroup(.hidden)
        )
        XCTAssertEqual(
            appGraph.commandRouter.command(for: URL(string: "thaw://toggle-always-hidden")!),
            .toggleGroup(.archive)
        )
    }

    func testAppGraphCommandRouterMapsCurrentHotkeyContracts() {
        let appGraph = makeAppGraph()

        XCTAssertEqual(appGraph.commandRouter.command(for: .togglePanel), .toggleGroup(.hidden))
        XCTAssertEqual(appGraph.commandRouter.command(for: .toggleArchive), .toggleGroup(.archive))
        XCTAssertEqual(appGraph.commandRouter.command(for: .searchLauncher), .openSearch)
        XCTAssertEqual(appGraph.commandRouter.command(for: .togglePrimarySurface), .toggleThawBar)
        XCTAssertNil(appGraph.commandRouter.command(for: .profileApply))
    }

    func testAppGraphReopenUsesGraphOwnedSettingsFlow() async {
        let appGraph = makeAppGraph(
            isPreviewEnvironment: { false },
            conflictWarningHandler: {},
            mainMenuHider: {}
        )
        let appState = AppState(appGraph: appGraph)

        XCTAssertTrue(appGraph.applicationShouldHandleReopen())
        await waitForWindow(.settings, in: appState)

        XCTAssertTrue(appState.sessionModel.openWindows.contains(.settings))
    }

    func testAppGraphRoutesSettingsURLThroughGraphOwnedCommandRouter() async {
        let appGraph = makeAppGraph()
        let appState = AppState(appGraph: appGraph)

        appGraph.handleIncomingURL(URL(string: "thaw://settings")!)
        await waitForWindow(.settings, in: appState)

        XCTAssertTrue(appState.sessionModel.openWindows.contains(.settings))
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
