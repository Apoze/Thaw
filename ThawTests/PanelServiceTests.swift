//
//  PanelServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import XCTest
@testable import Thaw

@MainActor
final class PanelServiceTests: XCTestCase {
    func testShowRefreshesPreparationAndPresentsIceBarOnPreferredScreen() async {
        guard let screen = NSScreen.main else {
            XCTFail("Expected a main display during test execution")
            return
        }

        let chrome = StubPanelChromeController()
        let discovery = StubPanelDiscoverySession()
        let display = StubPanelDisplayService(preferredScreen: screen)
        let settings = StubPanelDisplaySettings()
        let service = makeService(
            chrome: chrome,
            discovery: discovery,
            display: display,
            settings: settings
        )

        service.show(group: .hidden, triggeredByHotkey: true)
        await settleRuntimeTasks()

        XCTAssertEqual(discovery.invalidations, [.panelPreparation])
        XCTAssertEqual(
            chrome.shownIceBarCalls,
            [.init(group: .hidden, displayID: screen.displayID, triggeredByHotkey: true)]
        )
    }

    func testToggleClosesVisibleIceBarWithoutRefreshing() async {
        let chrome = StubPanelChromeController()
        chrome.visibleIceBarGroups = [.archive]
        let discovery = StubPanelDiscoverySession()
        let display = StubPanelDisplayService()
        let settings = StubPanelDisplaySettings()
        let service = makeService(
            chrome: chrome,
            discovery: discovery,
            display: display,
            settings: settings
        )

        service.toggle(group: .archive)
        await settleRuntimeTasks()

        XCTAssertEqual(chrome.closeIceBarCallCount, 1)
        XCTAssertTrue(discovery.invalidations.isEmpty)
        XCTAssertTrue(chrome.shownIceBarCalls.isEmpty)
    }

    func testTogglePrimarySurfaceUsesPinnedGroupWhenMenuBarDisplayUsesIceBar() async {
        guard let screen = NSScreen.main else {
            XCTFail("Expected a main display during test execution")
            return
        }

        let chrome = StubPanelChromeController()
        let discovery = StubPanelDiscoverySession()
        let displayID = screen.displayID
        let display = StubPanelDisplayService(
            activeMenuBarDisplayID: displayID,
            preferredScreen: screen
        )
        let settings = StubPanelDisplaySettings(iceBarDisplays: [displayID: true])
        let service = makeService(
            chrome: chrome,
            discovery: discovery,
            display: display,
            settings: settings
        )

        service.togglePrimarySurface()
        await settleRuntimeTasks()

        XCTAssertEqual(discovery.invalidations, [.panelPreparation])
        XCTAssertEqual(chrome.shownIceBarCalls.map(\.group), [.pinned])
    }

    func testToggleSearchClosesVisibleSearchPanelWithoutRefreshing() async {
        let chrome = StubPanelChromeController()
        chrome.isSearchPanelVisible = true
        let discovery = StubPanelDiscoverySession()
        let display = StubPanelDisplayService()
        let settings = StubPanelDisplaySettings()
        let service = makeService(
            chrome: chrome,
            discovery: discovery,
            display: display,
            settings: settings
        )

        service.toggleSearch()
        await settleRuntimeTasks()

        XCTAssertEqual(chrome.closeSearchPanelCallCount, 1)
        XCTAssertTrue(discovery.invalidations.isEmpty)
        XCTAssertEqual(chrome.showSearchPanelCallCount, 0)
    }

    func testToggleSearchRefreshesPreparationBeforePresentingSearchPanel() async {
        let chrome = StubPanelChromeController()
        let discovery = StubPanelDiscoverySession()
        let display = StubPanelDisplayService()
        let settings = StubPanelDisplaySettings()
        let service = makeService(
            chrome: chrome,
            discovery: discovery,
            display: display,
            settings: settings
        )

        service.toggleSearch()
        await settleRuntimeTasks()

        XCTAssertEqual(discovery.invalidations, [.panelPreparation])
        XCTAssertEqual(chrome.showSearchPanelCallCount, 1)
    }

    func testHandleIceBarInteractionDismissesMatchingPresentationOnly() async {
        let chrome = StubPanelChromeController()
        let service = makeService(
            chrome: chrome,
            discovery: StubPanelDiscoverySession(),
            display: StubPanelDisplayService(),
            settings: StubPanelDisplaySettings()
        )
        let expectedPresentationID = UUID()

        service.handleIceBarInteraction(
            PanelInteractionResult(outcome: .openedUI, disposition: .dismiss),
            expectedPresentationID: expectedPresentationID
        )
        service.handleIceBarInteraction(
            PanelInteractionResult(outcome: .failedRecoverable, disposition: .keepPresented),
            expectedPresentationID: UUID()
        )

        XCTAssertEqual(chrome.closeIceBarPresentationIDs, [expectedPresentationID])
    }

    func testHandleSearchInteractionDismissesMatchingPresentationOnly() async {
        let chrome = StubPanelChromeController()
        let service = makeService(
            chrome: chrome,
            discovery: StubPanelDiscoverySession(),
            display: StubPanelDisplayService(),
            settings: StubPanelDisplaySettings()
        )
        let expectedPresentationID = UUID()

        service.handleSearchInteraction(
            PanelInteractionResult(outcome: .openedApp, disposition: .dismiss),
            expectedPresentationID: expectedPresentationID
        )
        service.handleSearchInteraction(
            PanelInteractionResult(outcome: .timeout, disposition: .keepPresented),
            expectedPresentationID: UUID()
        )

        XCTAssertEqual(chrome.closeSearchPresentationIDs, [expectedPresentationID])
    }

    private func makeService(
        chrome: StubPanelChromeController,
        discovery: StubPanelDiscoverySession,
        display: StubPanelDisplayService,
        settings: StubPanelDisplaySettings
    ) -> PanelService {
        let service = PanelService()
        service.performSetup(with: .init(
            menuChromeController: chrome,
            discoverySession: discovery,
            displayService: display,
            displaySettings: settings
        ))
        return service
    }

    private func settleRuntimeTasks() async {
        try? await Task.sleep(for: .milliseconds(150))
    }
}

@MainActor
private final class StubPanelChromeController: PanelChromeControlling {
    struct ShowIceBarCall: Equatable {
        let group: VirtualGroup
        let displayID: CGDirectDisplayID?
        let triggeredByHotkey: Bool
    }

    var visibleIceBarGroups = Set<VirtualGroup>()
    var isSearchPanelVisible = false
    private(set) var shownIceBarCalls = [ShowIceBarCall]()
    private(set) var closeIceBarCallCount = 0
    private(set) var closeSearchPanelCallCount = 0
    private(set) var showSearchPanelCallCount = 0
    private(set) var closeIceBarPresentationIDs = [UUID?]()
    private(set) var closeSearchPresentationIDs = [UUID?]()

    func isIceBarVisible(for group: VirtualGroup) -> Bool {
        visibleIceBarGroups.contains(group)
    }

    func closeIceBar() {
        closeIceBarCallCount += 1
    }

    func showIceBar(group: VirtualGroup, on screen: NSScreen, triggeredByHotkey: Bool) {
        shownIceBarCalls.append(
            .init(
                group: group,
                displayID: screen.displayID,
                triggeredByHotkey: triggeredByHotkey
            )
        )
    }

    func closeSearchPanel() {
        closeSearchPanelCallCount += 1
    }

    func showSearchPanel(on _: NSScreen?) {
        showSearchPanelCallCount += 1
    }

    func closeIceBarIfPresentationMatches(_ presentationID: UUID?) {
        closeIceBarPresentationIDs.append(presentationID)
    }

    func closeSearchPanelIfPresentationMatches(_ presentationID: UUID?) {
        closeSearchPresentationIDs.append(presentationID)
    }
}

@MainActor
private final class StubPanelDiscoverySession: PanelDiscoveryPreparing {
    private(set) var invalidations = [DiscoveryInvalidation]()

    func refresh(_ invalidation: DiscoveryInvalidation) async {
        invalidations.append(invalidation)
    }
}

@MainActor
private final class StubPanelDisplayService: PanelDisplayProviding {
    var activeMenuBarDisplayID: CGDirectDisplayID?
    private let preferredScreen: NSScreen?

    init(
        activeMenuBarDisplayID: CGDirectDisplayID? = nil,
        preferredScreen: NSScreen? = nil
    ) {
        self.activeMenuBarDisplayID = activeMenuBarDisplayID
        self.preferredScreen = preferredScreen
    }

    func preferredPresentationScreen() -> NSScreen? {
        preferredScreen
    }
}

@MainActor
private final class StubPanelDisplaySettings: PanelDisplaySettingsReading {
    private let iceBarDisplays: [CGDirectDisplayID: Bool]

    init(iceBarDisplays: [CGDirectDisplayID: Bool] = [:]) {
        self.iceBarDisplays = iceBarDisplays
    }

    func useIceBar(for displayID: CGDirectDisplayID) -> Bool {
        iceBarDisplays[displayID] ?? false
    }
}
