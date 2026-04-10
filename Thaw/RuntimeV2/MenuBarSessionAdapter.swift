//
//  MenuBarSessionAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class MenuBarSessionAdapter {
    struct ProfileMenuEntry: Identifiable, Hashable {
        let id: UUID
        let name: String
        let isActive: Bool
    }

    let generalSettings: GeneralSettings
    let advancedSettings: AdvancedSettings
    let hotkeysSettings: HotkeysSettings

    private let profilesService: ProfilesService

    private let panelService: PanelService
    private let menuChromeController: MenuChromeController
    private let commandRouter: CommandRouter

    init(
        settings: AppSettings,
        profilesService: ProfilesService,
        panelService: PanelService,
        menuChromeController: MenuChromeController,
        commandRouter: CommandRouter
    ) {
        generalSettings = settings.general
        advancedSettings = settings.advanced
        hotkeysSettings = settings.hotkeys
        self.profilesService = profilesService
        self.panelService = panelService
        self.menuChromeController = menuChromeController
        self.commandRouter = commandRouter
    }

    var currentVirtualGroup: VirtualGroup? {
        menuChromeController.currentIceBarGroup
    }

    func hotkey(for action: HotkeyAction) -> Hotkey? {
        hotkeysSettings.hotkey(withAction: action)
    }

    func show(group: VirtualGroup, triggeredByHotkey: Bool = false) {
        panelService.show(group: group, triggeredByHotkey: triggeredByHotkey)
    }

    func toggle(group: VirtualGroup) {
        commandRouter.route(.toggleGroup(group), source: "control-item-menu")
    }

    func closeIfPresented(group: VirtualGroup) {
        menuChromeController.closeIceBarIfPresented(group: group)
    }

    func openSearch() {
        commandRouter.route(.openSearch, source: "control-item-menu")
    }

    func openSettings() {
        commandRouter.route(.openSettings, source: "control-item-menu")
    }

    var profileMenuEntries: [ProfileMenuEntry] {
        profilesService.profiles.map { profile in
            ProfileMenuEntry(
                id: profile.id,
                name: profile.name,
                isActive: profile.id == profilesService.activeProfileID
            )
        }
    }

    func canApplyProfileFromMenu(id: UUID) -> Bool {
        profilesService.layoutTask == nil && profilesService.activeProfileID != id
    }

    func applyProfile(id: UUID) {
        commandRouter.route(.applyProfile(id), source: "control-item-menu")
    }

    func checkForUpdates() {
        commandRouter.route(.checkForUpdates, source: "control-item-menu")
    }
}
