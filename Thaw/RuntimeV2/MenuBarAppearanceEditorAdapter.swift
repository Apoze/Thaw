//
//  MenuBarAppearanceEditorAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

@MainActor
final class MenuBarAppearanceEditorAdapter: ObservableObject {
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults: Bool
    @Published private(set) var showsSecondaryContextMenuTip: Bool

    let appearanceManager: MenuBarAppearanceManager

    private let menuBarPresentationService: MenuBarPresentationService
    private let advancedSettings: AdvancedSettings
    private var cancellables = Set<AnyCancellable>()

    init(
        appearanceManager: MenuBarAppearanceManager,
        menuBarPresentationService: MenuBarPresentationService,
        advancedSettings: AdvancedSettings
    ) {
        self.appearanceManager = appearanceManager
        self.menuBarPresentationService = menuBarPresentationService
        self.advancedSettings = advancedSettings
        isMenuBarHiddenBySystemUserDefaults = menuBarPresentationService.isMenuBarHiddenBySystemUserDefaults
        showsSecondaryContextMenuTip = advancedSettings.enableSecondaryContextMenu

        menuBarPresentationService.$isMenuBarHiddenBySystemUserDefaults
            .receive(on: DispatchQueue.main)
            .assign(to: &$isMenuBarHiddenBySystemUserDefaults)

        advancedSettings.$enableSecondaryContextMenu
            .receive(on: DispatchQueue.main)
            .assign(to: &$showsSecondaryContextMenuTip)
    }
}
