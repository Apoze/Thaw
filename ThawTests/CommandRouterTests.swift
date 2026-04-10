//
//  CommandRouterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

final class CommandRouterTests: XCTestCase {
    @MainActor
    func testRouterUsesExplicitDependenciesInsteadOfAppState() {
        let recorder = RouteRecorder()
        let router = CommandRouter()
        router.performSetup(with: .init(
            toggleGroup: recorder.toggleGroup(_:triggeredByHotkey:),
            togglePrimarySurface: recorder.togglePrimarySurface(triggeredByHotkey:),
            openSearch: recorder.openSearch,
            openSettings: recorder.openSettings,
            checkForUpdates: recorder.checkForUpdates,
            applyProfile: recorder.applyProfile(_:)
        ))

        router.route(url: URL(string: "thaw://panel")!)
        router.route(hotkeyAction: .togglePrimarySurface)
        router.route(.openSearch, source: "control-item-menu")
        router.route(.openSettings, source: "status-item-menu")
        router.route(.checkForUpdates, source: "control-item-menu")
        router.route(.applyProfile(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!), source: "control-item-menu")

        XCTAssertEqual(recorder.toggledGroupIDs, [.hidden])
        XCTAssertEqual(recorder.toggledGroupHotkeyFlags, [false])
        XCTAssertEqual(recorder.togglePrimarySurfaceHotkeyFlags, [true])
        XCTAssertEqual(recorder.openSearchCount, 1)
        XCTAssertEqual(recorder.openSettingsCount, 1)
        XCTAssertEqual(recorder.checkForUpdatesCount, 1)
        XCTAssertEqual(recorder.appliedProfileIDs, [UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!])
    }

    @MainActor
    func testURLHostsMapToCommands() {
        let router = CommandRouter()

        XCTAssertEqual(router.command(for: URL(string: "thaw://panel")!), .toggleGroup(.hidden))
        XCTAssertEqual(router.command(for: URL(string: "thaw://toggle-hidden")!), .toggleGroup(.hidden))
        XCTAssertEqual(router.command(for: URL(string: "thaw://archive")!), .toggleGroup(.archive))
        XCTAssertEqual(router.command(for: URL(string: "thaw://toggle-always-hidden")!), .toggleGroup(.archive))
        XCTAssertEqual(router.command(for: URL(string: "thaw://surface")!), .toggleThawBar)
        XCTAssertEqual(router.command(for: URL(string: "thaw://search")!), .openSearch)
        XCTAssertEqual(router.command(for: URL(string: "thaw://settings")!), .openSettings)
    }

    @MainActor
    func testURLHostParsingIsCaseInsensitiveAndRejectsUnknownHosts() {
        let router = CommandRouter()

        XCTAssertEqual(router.command(for: URL(string: "thaw://PANEL")!), .toggleGroup(.hidden))
        XCTAssertNil(router.command(for: URL(string: "thaw://unknown")!))
        XCTAssertNil(router.command(for: URL(string: "https://panel")!))
    }

    @MainActor
    func testCurrentExternalURLContractRemainsStable() {
        let router = CommandRouter()
        let expectedCommandsByHost: [String: AppCommand] = [
            "panel": .toggleGroup(.hidden),
            "toggle-hidden": .toggleGroup(.hidden),
            "archive": .toggleGroup(.archive),
            "toggle-always-hidden": .toggleGroup(.archive),
            "surface": .toggleThawBar,
            "search": .openSearch,
            "settings": .openSettings,
        ]

        let resolvedCommandsByHost: [String: AppCommand] = Dictionary(uniqueKeysWithValues: expectedCommandsByHost.keys.compactMap { host in
            guard let command = router.command(for: URL(string: "thaw://\(host)")!) else {
                return nil
            }
            return (host, command)
        })

        XCTAssertEqual(resolvedCommandsByHost, expectedCommandsByHost)
    }

    @MainActor
    func testHotkeyActionsMapToCommands() {
        let router = CommandRouter()

        XCTAssertEqual(router.command(for: .togglePanel), .toggleGroup(.hidden))
        XCTAssertEqual(router.command(for: .toggleArchive), .toggleGroup(.archive))
        XCTAssertEqual(router.command(for: .searchLauncher), .openSearch)
        XCTAssertEqual(router.command(for: .togglePrimarySurface), .toggleThawBar)
        XCTAssertNil(router.command(for: .profileApply))
    }

    func testSettingsActionsExposeOnlyCurrentActions() {
        XCTAssertEqual(Set(HotkeyAction.settingsActions), [
            .togglePanel,
            .toggleArchive,
            .searchLauncher,
            .togglePrimarySurface,
        ])
        XCTAssertFalse(HotkeyAction.settingsActions.contains(.profileApply))
    }

    @MainActor
    func testSettingsHotkeysRemainRoutableThroughCurrentExternalContract() {
        let router = CommandRouter()

        let commands = HotkeyAction.settingsActions.compactMap(router.command(for:))

        XCTAssertEqual(
            commands,
            [
                .toggleGroup(.hidden),
                .toggleGroup(.archive),
                .openSearch,
                .toggleThawBar,
            ]
        )
    }
}

@MainActor
private final class RouteRecorder {
    var toggledGroupIDs: [VirtualGroup] = []
    var toggledGroupHotkeyFlags: [Bool] = []
    var togglePrimarySurfaceHotkeyFlags: [Bool] = []
    var openSearchCount = 0
    var openSettingsCount = 0
    var checkForUpdatesCount = 0
    var appliedProfileIDs: [UUID] = []

    func toggleGroup(_ group: VirtualGroup, triggeredByHotkey: Bool) {
        toggledGroupIDs.append(group)
        toggledGroupHotkeyFlags.append(triggeredByHotkey)
    }

    func togglePrimarySurface(triggeredByHotkey: Bool) {
        togglePrimarySurfaceHotkeyFlags.append(triggeredByHotkey)
    }

    func openSearch() {
        openSearchCount += 1
    }

    func openSettings() {
        openSettingsCount += 1
    }

    func checkForUpdates() {
        checkForUpdatesCount += 1
    }

    func applyProfile(_ profileID: UUID) {
        appliedProfileIDs.append(profileID)
    }
}
