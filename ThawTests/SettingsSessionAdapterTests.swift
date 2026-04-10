//
//  SettingsSessionAdapterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class SettingsSessionAdapterTests: XCTestCase {
    func testResetAllSettingsToDefaultsResetsAppearanceAtSessionBoundary() {
        let settings = AppSettings()
        let appearanceManager = MenuBarAppearanceManager()
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.staticConfiguration.tintKind = .solid
        appearanceManager.configuration = configuration

        let adapter = SettingsSessionAdapter(
            settings: settings,
            layoutEditorAdapter: MenuBarLayoutEditorAdapter(discoverySession: StubDiscoverySession(
                snapshot: DiscoverySnapshot(descriptors: [], generatedAt: .init(timeIntervalSince1970: 0))
            )),
            appearanceManager: appearanceManager,
            appearanceEditorAdapter: MenuBarAppearanceEditorAdapter(
                appearanceManager: appearanceManager,
                menuBarPresentationService: MenuBarPresentationService(),
                advancedSettings: settings.advanced
            ),
            profileManager: ProfileManager(service: ProfilesService()),
            updatesManager: UpdatesManager(),
            permissions: PermissionService()
        )

        adapter.resetAllSettingsToDefaults()

        XCTAssertEqual(
            appearanceManager.configuration,
            Defaults.DefaultValue.menuBarAppearanceConfigurationV2
        )
    }
}
