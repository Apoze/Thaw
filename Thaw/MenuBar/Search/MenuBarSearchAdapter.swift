//
//  MenuBarSearchAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import CoreGraphics
import Foundation

@MainActor
protocol MenuBarDiscoverySessionControlling: AnyObject {
    var snapshot: DiscoverySnapshot { get }
    var snapshotPublisher: AnyPublisher<DiscoverySnapshot, Never> { get }

    func refresh(_ invalidation: DiscoveryInvalidation) async
    func rename(canonicalID: MenuExtraCanonicalID, to customName: String?) async
    func assign(_ group: VirtualGroup, to canonicalID: MenuExtraCanonicalID) async
    func reorder(group: VirtualGroup, descriptors: [MenuExtraDescriptor]) async
    func resetSuggestedLayout() async
}

extension DiscoverySession: MenuBarDiscoverySessionControlling {
    var snapshotPublisher: AnyPublisher<DiscoverySnapshot, Never> {
        $snapshot.eraseToAnyPublisher()
    }
}

@MainActor
final class MenuBarSearchAdapter: ObservableObject {
    @Published private(set) var snapshot: DiscoverySnapshot

    private let discoverySession: any MenuBarDiscoverySessionControlling
    private let panelInteractionController: any PanelInteractionHandling
    private var cancellables = Set<AnyCancellable>()

    init(
        discoverySession: some MenuBarDiscoverySessionControlling,
        panelInteractionController: some PanelInteractionHandling
    ) {
        self.discoverySession = discoverySession
        self.panelInteractionController = panelInteractionController
        snapshot = discoverySession.snapshot

        discoverySession.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
            .store(in: &cancellables)
    }

    var descriptors: [MenuExtraDescriptor] {
        snapshot.descriptors
    }

    func refresh() async {
        await discoverySession.refresh(.panelPreparation)
    }

    func descriptors(in group: VirtualGroup, on displayID: CGDirectDisplayID? = nil) -> [MenuExtraDescriptor] {
        snapshot.descriptors.filter { descriptor in
            guard descriptor.group == group else { return false }
            guard let displayID else { return true }
            return descriptor.displayID == nil || descriptor.displayID == displayID
        }
    }

    func descriptor(withID id: String) -> MenuExtraDescriptor? {
        snapshot.descriptors.first(where: { $0.id == id })
    }

    func rename(descriptorID: String, to customName: String?) async {
        guard let descriptor = descriptor(withID: descriptorID) else {
            return
        }

        await discoverySession.rename(canonicalID: descriptor.canonicalID, to: customName)
    }

    func activate(
        canonicalID: MenuExtraCanonicalID,
        surface: ActivationSurface = .search,
        intent: ActivationIntent = .automatic
    ) async -> PanelInteractionResult {
        await panelInteractionController.interactWithPanel(using:
            ActivationCommand(
                canonicalID: canonicalID,
                surface: surface,
                intent: intent
            ))
    }
}
