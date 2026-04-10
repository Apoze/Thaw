//
//  MenuBarLayoutEditorAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

@MainActor
final class MenuBarLayoutEditorAdapter: ObservableObject {
    @Published private(set) var snapshot: DiscoverySnapshot

    private let discoverySession: any MenuBarDiscoverySessionControlling
    private var cancellables = Set<AnyCancellable>()

    init(discoverySession: some MenuBarDiscoverySessionControlling) {
        self.discoverySession = discoverySession
        snapshot = discoverySession.snapshot

        discoverySession.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
            .store(in: &cancellables)
    }

    func refresh() async {
        await discoverySession.refresh(.layoutEditorPresented)
    }

    func descriptors(in group: VirtualGroup) -> [MenuExtraDescriptor] {
        snapshot.descriptors.filter { $0.group == group }
    }

    func descriptor(withID id: String) -> MenuExtraDescriptor? {
        snapshot.descriptors.first(where: { $0.id == id })
    }

    func moveDescriptor(
        id: String,
        to group: VirtualGroup,
        before targetID: String? = nil
    ) {
        guard let descriptor = descriptor(withID: id) else {
            return
        }

        var reordered = descriptors(in: group).filter { $0.id != id }
        var movedDescriptor = descriptor
        movedDescriptor.group = group

        if let targetID,
           let index = reordered.firstIndex(where: { $0.id == targetID })
        {
            reordered.insert(movedDescriptor, at: index)
        } else {
            reordered.append(movedDescriptor)
        }

        Task {
            await discoverySession.assign(group, to: descriptor.canonicalID)
            await discoverySession.reorder(group: group, descriptors: reordered)
        }
    }

    func resetSuggestedLayout() async {
        await discoverySession.resetSuggestedLayout()
        await discoverySession.refresh(.layoutReset)
    }
}
