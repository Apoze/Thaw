//
//  PanelRuntime.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

@MainActor
protocol PanelChromeControlling: AnyObject {
    func isIceBarVisible(for group: VirtualGroup) -> Bool
    func closeIceBar()
    func showIceBar(group: VirtualGroup, on screen: NSScreen, triggeredByHotkey: Bool)
    var isSearchPanelVisible: Bool { get }
    func closeSearchPanel()
    func showSearchPanel(on screen: NSScreen?)
    func closeIceBarIfPresentationMatches(_ presentationID: UUID?)
    func closeSearchPanelIfPresentationMatches(_ presentationID: UUID?)
}

extension MenuChromeController: PanelChromeControlling {}

@MainActor
protocol PanelDiscoveryPreparing: AnyObject {
    func refresh(_ invalidation: DiscoveryInvalidation) async
}

extension DiscoverySession: PanelDiscoveryPreparing {}

@MainActor
protocol PanelDisplayProviding: AnyObject {
    var activeMenuBarDisplayID: CGDirectDisplayID? { get }
    func preferredPresentationScreen() -> NSScreen?
}

extension DisplayService: PanelDisplayProviding {}

@MainActor
protocol PanelDisplaySettingsReading: AnyObject {
    func useIceBar(for displayID: CGDirectDisplayID) -> Bool
}

extension DisplaySettingsManager: PanelDisplaySettingsReading {}

@MainActor
final class PanelService: ObservableObject {
    struct Dependencies {
        let menuChromeController: any PanelChromeControlling
        let discoverySession: any PanelDiscoveryPreparing
        let displayService: any PanelDisplayProviding
        let displaySettings: any PanelDisplaySettingsReading
    }

    private var dependencies: Dependencies?
    private var iceBarShowTask: Task<Void, Never>?
    private var pendingIceBarShowID = UUID()
    private var searchShowTask: Task<Void, Never>?
    private var pendingSearchShowID = UUID()

    func performSetup(with dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func toggle(group: VirtualGroup, triggeredByHotkey: Bool = false) {
        guard let dependencies else { return }
        if dependencies.menuChromeController.isIceBarVisible(for: group) {
            cancelPendingIceBarShow()
            dependencies.menuChromeController.closeIceBar()
            return
        }
        show(group: group, triggeredByHotkey: triggeredByHotkey)
    }

    func togglePrimarySurface(triggeredByHotkey: Bool = false) {
        guard let dependencies else {
            return
        }

        let group: VirtualGroup =
            if dependencies.displayService.activeMenuBarDisplayID.map(dependencies.displaySettings.useIceBar(for:)) == true {
                .pinned
            } else {
                .hidden
            }

        toggle(group: group, triggeredByHotkey: triggeredByHotkey)
    }

    func show(group: VirtualGroup, triggeredByHotkey: Bool = false) {
        guard let dependencies else {
            return
        }

        cancelPendingIceBarShow()
        let showID = UUID()
        pendingIceBarShowID = showID

        iceBarShowTask = Task { [weak self] in
            defer {
                if self?.pendingIceBarShowID == showID {
                    self?.iceBarShowTask = nil
                }
            }

            guard let self else {
                return
            }

            await dependencies.discoverySession.refresh(.panelPreparation)

            guard !Task.isCancelled, self.pendingIceBarShowID == showID else {
                return
            }

            guard let screen = dependencies.displayService.preferredPresentationScreen() else {
                return
            }

            guard self.pendingIceBarShowID == showID else {
                return
            }

            dependencies.menuChromeController.showIceBar(
                group: group,
                on: screen,
                triggeredByHotkey: triggeredByHotkey
            )
        }
    }

    func toggleSearch() {
        guard let dependencies else {
            return
        }

        if dependencies.menuChromeController.isSearchPanelVisible {
            cancelPendingSearchShow()
            dependencies.menuChromeController.closeSearchPanel()
            return
        }

        showSearch()
    }

    func handleIceBarInteraction(
        _ result: PanelInteractionResult,
        expectedPresentationID: UUID?
    ) {
        guard result.disposition == .dismiss, let dependencies else {
            return
        }

        dependencies.menuChromeController.closeIceBarIfPresentationMatches(expectedPresentationID)
    }

    func handleSearchInteraction(
        _ result: PanelInteractionResult,
        expectedPresentationID: UUID?
    ) {
        guard result.disposition == .dismiss, let dependencies else {
            return
        }

        dependencies.menuChromeController.closeSearchPanelIfPresentationMatches(expectedPresentationID)
    }

    private func showSearch() {
        guard let dependencies else {
            return
        }

        cancelPendingSearchShow()
        let showID = UUID()
        pendingSearchShowID = showID

        searchShowTask = Task { [weak self] in
            defer {
                if self?.pendingSearchShowID == showID {
                    self?.searchShowTask = nil
                }
            }

            guard let self else {
                return
            }

            await dependencies.discoverySession.refresh(.panelPreparation)

            guard !Task.isCancelled, self.pendingSearchShowID == showID else {
                return
            }

            dependencies.menuChromeController.showSearchPanel(on: nil)
        }
    }

    private func cancelPendingIceBarShow() {
        iceBarShowTask?.cancel()
        iceBarShowTask = nil
        pendingIceBarShowID = UUID()
    }

    private func cancelPendingSearchShow() {
        searchShowTask?.cancel()
        searchShowTask = nil
        pendingSearchShowID = UUID()
    }
}

typealias PanelRuntime = PanelService
