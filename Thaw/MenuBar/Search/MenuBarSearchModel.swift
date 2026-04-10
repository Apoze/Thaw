//
//  MenuBarSearchModel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Ifrit

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(VirtualGroup)
        case item(String)
    }

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?
    @Published var editingItemID: String?
    @Published var editingName: String = ""

    private var cancellables = Set<AnyCancellable>()

    let fuse = Fuse(threshold: 0.5)

    func performSetup(
        with panel: MenuBarSearchPanel,
        displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
    ) {
        configureCancellables(
            with: panel,
            displayConfigurationDidChangePublisher: displayConfigurationDidChangePublisher
        )
    }

    private func configureCancellables(
        with panel: MenuBarSearchPanel,
        displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
    ) {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            panel.publisher(for: \.screen),
            panel.publisher(for: \.isVisible)
        )
        .compactMap { screen, isVisible in
            isVisible ? screen : nil
        }
        .debounce(for: 0.1, scheduler: DispatchQueue.main) // Debounce to avoid rapid updates
        .sink { [weak self] screen in
            self?.updateAverageColorInfo(for: screen)
        }
        .store(in: &c)

        // Clear average color when search panel closes to free memory
        panel.publisher(for: \.isVisible)
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.averageColorInfo = nil
            }
            .store(in: &c)

        // Clear on display changes to prevent stale color info
        displayConfigurationDidChangePublisher
            .sink { [weak self] _ in
                self?.averageColorInfo = nil
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateAverageColorInfo(for screen: NSScreen) {}
}
