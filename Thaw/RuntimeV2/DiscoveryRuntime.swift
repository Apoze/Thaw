//
//  DiscoveryRuntime.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation

@MainActor
final class DiscoverySession: ObservableObject {
    @Published private(set) var snapshot = DiscoverySnapshot.empty
    @Published private(set) var isReady = false
    @Published private(set) var lastRefreshAt: Date?

    private let service: DiscoveryService
    private let workspaceEventSource: WorkspaceEventSource
    private var layoutSnapshot = ProfileLayoutV3.empty
    private var cancellables = Set<AnyCancellable>()
    private var stateTask: Task<Void, Never>?
    private var hasPerformedSetup = false

    init(
        service: DiscoveryService,
        workspaceEventSource: WorkspaceEventSource
    ) {
        self.service = service
        self.workspaceEventSource = workspaceEventSource
    }

    func performSetup() {
        guard !hasPerformedSetup else {
            return
        }

        hasPerformedSetup = true

        stateTask = Task { [weak self] in
            guard let self else {
                return
            }

            let initialState = await self.service.currentState()
            self.apply(state: initialState)

            for await state in self.service.stateUpdates {
                self.apply(state: state)
            }
        }

        workspaceEventSource.invalidationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invalidation in
                guard let self else {
                    return
                }

                Task {
                    await self.service.refresh(invalidation: invalidation)
                }
            }
            .store(in: &cancellables)

        Task {
            await self.service.performSetup()
        }
    }

    deinit {
        stateTask?.cancel()
    }

    var descriptors: [MenuExtraDescriptor] {
        snapshot.descriptors
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

    func descriptor(withCanonicalID canonicalID: MenuExtraCanonicalID) -> MenuExtraDescriptor? {
        snapshot.descriptors.first(where: { $0.canonicalID == canonicalID })
    }

    func currentLayoutSnapshot() -> ProfileLayoutV3 {
        layoutSnapshot
    }

    func refresh(_ invalidation: DiscoveryInvalidation) async {
        await service.refresh(invalidation: invalidation)
    }

    func applyLayoutSnapshot(_ profileLayout: ProfileLayoutV3) async {
        await service.applyLayoutSnapshot(profileLayout)
    }

    func resetSuggestedLayout() async {
        await service.resetSuggestedLayout()
    }

    func assign(_ group: VirtualGroup, to canonicalID: MenuExtraCanonicalID) async {
        await service.assign(group, to: canonicalID)
    }

    func rename(canonicalID: MenuExtraCanonicalID, to customName: String?) async {
        await service.rename(canonicalID: canonicalID, to: customName)
    }

    func reorder(group: VirtualGroup, descriptors: [MenuExtraDescriptor]) async {
        await service.reorder(group: group, descriptors: descriptors)
    }

    private func apply(state: DiscoveryServiceState) {
        snapshot = state.snapshot
        layoutSnapshot = state.layoutSnapshot
        isReady = state.isReady
        lastRefreshAt = state.lastRefreshAt
    }
}

@MainActor
extension DiscoverySession: IceBarDiscoverySessionControlling {
    var discoverySnapshotPublisher: AnyPublisher<DiscoverySnapshot, Never> {
        $snapshot.eraseToAnyPublisher()
    }

    var isReadyPublisher: AnyPublisher<Bool, Never> {
        $isReady.eraseToAnyPublisher()
    }
}
