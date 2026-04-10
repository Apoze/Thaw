//
//  MenuBarPresentationService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import CoreGraphics

/// Public V3 service for menu bar appearance context needed by Thaw's own UI.
///
/// This intentionally excludes retired section/control-item management and only
/// exposes the visual state still required by overlay, search, and settings UI.
@MainActor
final class MenuBarPresentationService: ObservableObject {
    struct Dependencies {
        let systemPresentationOptionsPublisher: AnyPublisher<NSApplication.PresentationOptions, Never>
        let activeSpaceDidChangePublisher: AnyPublisher<Void, Never>
        let displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
        let settingsWindowVisibilityPublisher: AnyPublisher<Bool, Never>
    }

    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?
    @Published private(set) var isMenuBarHiddenBySystem = false
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults = false

    private var cancellables = Set<AnyCancellable>()
    private var averageColorRefreshCancellable: AnyCancellable?

    func performSetup(with dependencies: Dependencies) {
        configureCancellables(with: dependencies)
    }

    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard
            let window = WindowInfo.menuBarWindow(from: windows, for: display),
            let element = AXHelpers.element(at: window.bounds.origin)
        else {
            return false
        }
        return AXHelpers.role(for: element) == .menuBar
    }

    private func configureCancellables(with dependencies: Dependencies) {
        averageColorRefreshCancellable?.cancel()
        averageColorRefreshCancellable = nil
        var c = Set<AnyCancellable>()

        refreshMenuBarHiddenUserDefaultsState()

        dependencies.systemPresentationOptionsPublisher
            .sink { [weak self] options in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    isMenuBarHiddenBySystem = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                }
            }
            .store(in: &c)

        Publishers.Merge(
            dependencies.activeSpaceDidChangePublisher,
            dependencies.displayConfigurationDidChangePublisher
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMenuBarHiddenUserDefaultsState()
            }
        }
        .store(in: &c)

        dependencies.settingsWindowVisibilityPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible {
                    updateAverageColorInfo()
                    averageColorRefreshCancellable = Timer.publish(
                        every: 60,
                        tolerance: 10,
                        on: .main,
                        in: .default
                    )
                    .autoconnect()
                    .sink { [weak self] _ in
                        self?.updateAverageColorInfo()
                    }
                } else {
                    averageColorRefreshCancellable?.cancel()
                    averageColorRefreshCancellable = nil
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func refreshMenuBarHiddenUserDefaultsState() {
        isMenuBarHiddenBySystemUserDefaults = Defaults.globalDomain["_HIHideMenuBar"] as? Bool ?? false
    }

    /// The implementation remains intentionally isolated from retired runtime
    /// code so the active graph depends only on V3 services.
    func updateAverageColorInfo() {}
}
