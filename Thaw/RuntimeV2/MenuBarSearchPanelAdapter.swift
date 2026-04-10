//
//  MenuBarSearchPanelAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

@MainActor
final class MenuBarSearchPanelAdapter {
    let searchAdapter: MenuBarSearchAdapter
    let activeSpaceDidChangePublisher: AnyPublisher<Void, Never>
    let displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>

    private let navigationState: AppNavigationState
    private let commandRouter: CommandRouter
    private let panelService: PanelService

    init(
        sessionModel: AppSessionModel,
        searchAdapter: MenuBarSearchAdapter,
        commandRouter: CommandRouter,
        panelService: PanelService,
        activeSpaceDidChangePublisher: AnyPublisher<Void, Never>,
        displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
    ) {
        self.searchAdapter = searchAdapter
        navigationState = sessionModel.navigationState
        self.commandRouter = commandRouter
        self.panelService = panelService
        self.activeSpaceDidChangePublisher = activeSpaceDidChangePublisher
        self.displayConfigurationDidChangePublisher = displayConfigurationDidChangePublisher
    }

    func setSearchPresented(_ isPresented: Bool) {
        navigationState.isSearchPresented = isPresented
    }

    func openSettings() {
        commandRouter.route(.openSettings, source: "search-panel")
    }

    func openAdvancedSettings() {
        navigationState.settingsNavigationIdentifier = .advanced
        openSettings()
    }

    func handleActivation(
        _ result: PanelInteractionResult,
        expectedPresentationID: UUID?
    ) {
        panelService.handleSearchInteraction(
            result,
            expectedPresentationID: expectedPresentationID
        )
    }
}
