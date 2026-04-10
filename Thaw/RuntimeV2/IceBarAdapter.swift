//
//  IceBarAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

@MainActor
protocol IceBarDiscoverySessionControlling: AnyObject {
    var snapshot: DiscoverySnapshot { get }
    var isReady: Bool { get }
    var discoverySnapshotPublisher: AnyPublisher<DiscoverySnapshot, Never> { get }
    var isReadyPublisher: AnyPublisher<Bool, Never> { get }
}

@MainActor
final class IceBarAdapter: ObservableObject {
    @Published private(set) var snapshot: DiscoverySnapshot
    @Published private(set) var isReady: Bool
    @Published private(set) var activeSpace: SpaceInfo

    let appearanceManager: MenuBarAppearanceManager
    let menuBarPresentationService: MenuBarPresentationService
    let activeSpaceDidChangePublisher: AnyPublisher<Void, Never>
    let displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>

    private let discoverySession: any IceBarDiscoverySessionControlling
    private let panelInteractionController: any PanelInteractionHandling
    private let panelService: PanelService
    private let permissions: PermissionService
    private let generalSettings: GeneralSettings
    private let advancedSettings: AdvancedSettings
    private let displaySettings: DisplaySettingsManager
    private let navigationState: AppNavigationState
    private let menuChromeController: MenuChromeController
    private let sessionModel: AppSessionModel
    private var cancellables = Set<AnyCancellable>()

    init(
        sessionModel: AppSessionModel,
        discoverySession: some IceBarDiscoverySessionControlling,
        panelInteractionController: any PanelInteractionHandling,
        panelService: PanelService,
        permissions: PermissionService,
        generalSettings: GeneralSettings,
        advancedSettings: AdvancedSettings,
        displaySettings: DisplaySettingsManager,
        menuChromeController: MenuChromeController,
        appearanceManager: MenuBarAppearanceManager,
        menuBarPresentationService: MenuBarPresentationService,
        activeSpaceDidChangePublisher: AnyPublisher<Void, Never>,
        displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
    ) {
        self.sessionModel = sessionModel
        self.discoverySession = discoverySession
        self.panelInteractionController = panelInteractionController
        self.panelService = panelService
        self.permissions = permissions
        self.generalSettings = generalSettings
        self.advancedSettings = advancedSettings
        self.displaySettings = displaySettings
        navigationState = sessionModel.navigationState
        self.menuChromeController = menuChromeController
        self.appearanceManager = appearanceManager
        self.menuBarPresentationService = menuBarPresentationService
        self.activeSpaceDidChangePublisher = activeSpaceDidChangePublisher
        self.displayConfigurationDidChangePublisher = displayConfigurationDidChangePublisher
        snapshot = discoverySession.snapshot
        isReady = discoverySession.isReady
        activeSpace = sessionModel.activeSpace

        discoverySession.discoverySnapshotPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$snapshot)

        discoverySession.isReadyPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$isReady)

        sessionModel.$activeSpace
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeSpace)
    }

    var tooltipDelay: TimeInterval {
        advancedSettings.tooltipDelay
    }

    var hotkeyUsesPointerLocation: Bool {
        generalSettings.iceBarLocationOnHotkey
    }

    var menuBarInsetAmount: CGFloat {
        appearanceManager.menuBarInsetAmount
    }

    var isAccessibilityGranted: Bool {
        AXHelpers.isProcessTrusted()
    }

    var statusItemFrame: CGRect? {
        menuChromeController.statusItemFrame
    }

    func descriptors(in group: VirtualGroup, on displayID: CGDirectDisplayID) -> [MenuExtraDescriptor] {
        snapshot.descriptors.filter { descriptor in
            guard descriptor.group == group else { return false }
            return descriptor.displayID == nil || descriptor.displayID == displayID
        }
    }

    func iceBarLocation(for displayID: CGDirectDisplayID) -> IceBarLocation {
        displaySettings.iceBarLocation(for: displayID)
    }

    func setIceBarPresented(_ isPresented: Bool) {
        navigationState.isIceBarPresented = isPresented
    }

    func requestAccessibilityPermission() {
        permissions.accessibility.performRequest()
    }

    func activate(
        descriptor: MenuExtraDescriptor,
        intent: ActivationIntent
    ) async -> PanelInteractionResult {
        await panelInteractionController.interactWithPanel(using: ActivationCommand(
            canonicalID: descriptor.canonicalID,
            surface: descriptor.group.activationSurface,
            intent: intent
        ))
    }

    func handleActivation(
        _ result: PanelInteractionResult,
        expectedPresentationID: UUID?
    ) {
        panelService.handleIceBarInteraction(
            result,
            expectedPresentationID: expectedPresentationID
        )
    }
}
