//
//  SettingsSessionAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class SettingsSessionAdapter {
    let generalSettings: GeneralSettings
    let displaySettings: DisplaySettingsManager
    let layoutEditorAdapter: MenuBarLayoutEditorAdapter
    let appearanceManager: MenuBarAppearanceManager
    let appearanceEditorAdapter: MenuBarAppearanceEditorAdapter
    let hotkeysSettings: HotkeysSettings
    let profileManager: ProfileManager
    let advancedSettings: AdvancedSettings
    let updatesManager: UpdatesManager
    let permissions: PermissionService

    private let settings: AppSettings

    init(
        settings: AppSettings,
        layoutEditorAdapter: MenuBarLayoutEditorAdapter,
        appearanceManager: MenuBarAppearanceManager,
        appearanceEditorAdapter: MenuBarAppearanceEditorAdapter,
        profileManager: ProfileManager,
        updatesManager: UpdatesManager,
        permissions: PermissionService
    ) {
        self.settings = settings
        generalSettings = settings.general
        displaySettings = settings.displaySettings
        self.layoutEditorAdapter = layoutEditorAdapter
        self.appearanceManager = appearanceManager
        self.appearanceEditorAdapter = appearanceEditorAdapter
        hotkeysSettings = settings.hotkeys
        self.profileManager = profileManager
        advancedSettings = settings.advanced
        self.updatesManager = updatesManager
        self.permissions = permissions
    }

    func resetAllSettingsToDefaults() {
        settings.resetAllSettingsToDefaults()
        appearanceManager.configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2
    }
}
