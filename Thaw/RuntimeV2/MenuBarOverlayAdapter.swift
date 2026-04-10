//
//  MenuBarOverlayAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

@MainActor
final class MenuBarOverlayAdapter: ObservableObject {
    @Published private(set) var activeSpace: SpaceInfo
    @Published private(set) var statusItemFrameSnapshot: CGRect?

    let appearanceManager: MenuBarAppearanceManager
    let menuBarPresentationService: MenuBarPresentationService
    let activeSpaceDidChangePublisher: AnyPublisher<Void, Never>
    let displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
    let menuBarContextDidChangePublisher: AnyPublisher<Void, Never>

    private var cancellables = Set<AnyCancellable>()

    init(
        sessionModel: AppSessionModel,
        appearanceManager: MenuBarAppearanceManager,
        menuBarPresentationService: MenuBarPresentationService,
        menuChromeController: MenuChromeController,
        activeSpaceDidChangePublisher: AnyPublisher<Void, Never>,
        displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>,
        menuBarContextDidChangePublisher: AnyPublisher<Void, Never>
    ) {
        self.appearanceManager = appearanceManager
        self.menuBarPresentationService = menuBarPresentationService
        self.activeSpaceDidChangePublisher = activeSpaceDidChangePublisher
        self.displayConfigurationDidChangePublisher = displayConfigurationDidChangePublisher
        self.menuBarContextDidChangePublisher = menuBarContextDidChangePublisher
        activeSpace = sessionModel.activeSpace
        statusItemFrameSnapshot = menuChromeController.statusItemFrameSnapshot

        sessionModel.$activeSpace
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeSpace in
                self?.activeSpace = activeSpace
            }
            .store(in: &cancellables)

        menuChromeController.$statusItemFrameSnapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.statusItemFrameSnapshot = frame
            }
            .store(in: &cancellables)
    }

    func owns(_ panel: MenuBarOverlayPanel) -> Bool {
        appearanceManager.overlayPanels.contains(panel)
    }
}
