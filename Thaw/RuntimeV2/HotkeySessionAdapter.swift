//
//  HotkeySessionAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class HotkeySessionAdapter {
    let registry: HotkeyRegistry
    let profilesService: ProfilesService

    private let commandRouter: CommandRouter

    init(
        registry: HotkeyRegistry,
        profilesService: ProfilesService,
        commandRouter: CommandRouter
    ) {
        self.registry = registry
        self.profilesService = profilesService
        self.commandRouter = commandRouter
    }

    func route(_ action: HotkeyAction) {
        guard action != .profileApply else {
            return
        }
        commandRouter.route(hotkeyAction: action)
    }

    func applyAssignedProfile(for hotkey: Hotkey) {
        guard profilesService.layoutTask == nil else {
            return
        }

        let key = ObjectIdentifier(hotkey)
        guard
            let profileID = profilesService.hotkeyProfileMap[key],
            profileID != profilesService.activeProfileID
        else {
            return
        }

        Task {
            try? await profilesService.applyProfile(id: profileID)
        }
    }
}
