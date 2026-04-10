//
//  ViewAdapterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import XCTest
@testable import Thaw

@MainActor
final class ViewAdapterTests: XCTestCase {
    func testSearchAdapterPublishesSnapshotsOnMainActor() async {
        let initialDescriptor = makeDescriptor(
            bundleID: "com.example.search",
            title: "Search Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "search-initial"
        )
        let updatedDescriptor = makeDescriptor(
            bundleID: "com.example.search",
            title: "Updated Search Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "search-updated"
        )

        let session = StubDiscoverySession(
            snapshot: DiscoverySnapshot(descriptors: [initialDescriptor], generatedAt: .init(timeIntervalSince1970: 1))
        )
        let adapter = MenuBarSearchAdapter(
            discoverySession: session,
            panelInteractionController: StubPanelInteractionController()
        )

        XCTAssertEqual(adapter.descriptors, [initialDescriptor])

        let publication = PublicationProbe()
        var cancellables = Set<AnyCancellable>()
        adapter.$snapshot
            .dropFirst()
            .sink { snapshot in
                publication.record(threadIsMain: Thread.isMainThread, snapshot: snapshot)
                _ = publication.markFulfilled()
            }
            .store(in: &cancellables)

        session.snapshot = DiscoverySnapshot(
            descriptors: [updatedDescriptor],
            generatedAt: .init(timeIntervalSince1970: 2)
        )

        await waitUntil {
            await MainActor.run {
                publication.snapshot()?.descriptors == [updatedDescriptor]
            }
        }
        XCTAssertTrue(publication.receivedOnMainThread())
        XCTAssertEqual(publication.snapshot()?.descriptors, [updatedDescriptor])
        XCTAssertEqual(adapter.snapshot.descriptors, [updatedDescriptor])
    }

    func testSearchAdapterForwardsCommandsToRuntime() async {
        let descriptor = makeDescriptor(
            bundleID: "com.example.search",
            title: "Search Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "search-commands"
        )
        let session = StubDiscoverySession(
            snapshot: DiscoverySnapshot(descriptors: [descriptor], generatedAt: .init(timeIntervalSince1970: 1))
        )
        let panelInteractionController = StubPanelInteractionController()
        let adapter = MenuBarSearchAdapter(
            discoverySession: session,
            panelInteractionController: panelInteractionController
        )

        await adapter.refresh()
        await adapter.rename(descriptorID: descriptor.id, to: "Renamed")
        let outcome = await adapter.activate(
            canonicalID: descriptor.canonicalID,
            surface: .search,
            intent: .automatic
        )

        XCTAssertEqual(session.refreshInvalidations, [.panelPreparation])
        XCTAssertEqual(session.renamedCanonicalIDs.count, 1)
        XCTAssertEqual(session.renamedCanonicalIDs.first?.0, descriptor.canonicalID)
        XCTAssertEqual(session.renamedCanonicalIDs.first?.1, "Renamed")
        XCTAssertEqual(session.activateCallCount, 0)
        XCTAssertEqual(panelInteractionController.activatedCommands, [
            ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .search,
                intent: .automatic,
            ),
        ])
        XCTAssertEqual(outcome.outcome, .openedUI)
        XCTAssertEqual(outcome.disposition, .dismiss)
    }

    func testLayoutEditorAdapterPublishesSnapshotsOnMainActor() async {
        let sourceDescriptor = makeDescriptor(
            bundleID: "com.example.layout",
            title: "Source Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "layout-source"
        )
        let movedDescriptor = makeDescriptor(
            bundleID: "com.example.layout",
            title: "Moved Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "layout-moved"
        )

        let session = StubDiscoverySession(
            snapshot: DiscoverySnapshot(
                descriptors: [sourceDescriptor, movedDescriptor],
                generatedAt: .init(timeIntervalSince1970: 1)
            )
        )
        let adapter = MenuBarLayoutEditorAdapter(discoverySession: session)

        let publication = PublicationProbe()
        var cancellables = Set<AnyCancellable>()
        adapter.$snapshot
            .dropFirst()
            .sink { snapshot in
                publication.record(threadIsMain: Thread.isMainThread, snapshot: snapshot)
                _ = publication.markFulfilled()
            }
            .store(in: &cancellables)

        adapter.moveDescriptor(
            id: sourceDescriptor.id,
            to: .archive
        )

        await waitUntil {
            await MainActor.run {
                publication.snapshot()?.descriptors.first?.group == .archive &&
                    adapter.snapshot.descriptors.first?.group == .archive &&
                    session.reorderedDescriptors.map(\.id) == [sourceDescriptor.id]
            }
        }
        XCTAssertTrue(publication.receivedOnMainThread())
        XCTAssertEqual(publication.snapshot()?.descriptors.first?.group, .archive)
        XCTAssertEqual(adapter.snapshot.descriptors.first?.group, .archive)
        XCTAssertEqual(adapter.snapshot.descriptors.count, 1)
        XCTAssertEqual(session.assignedGroups.count, 1)
        XCTAssertEqual(session.assignedGroups.first?.0, .archive)
        XCTAssertEqual(session.assignedGroups.first?.1, sourceDescriptor.canonicalID)
        XCTAssertEqual(session.reorderedDescriptors.map(\.id), [sourceDescriptor.id])
    }

    func testLayoutEditorAdapterForwardsCommandsToRuntime() async {
        let descriptor = makeDescriptor(
            bundleID: "com.example.layout",
            title: "Layout Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "layout-commands"
        )
        let session = StubDiscoverySession(
            snapshot: DiscoverySnapshot(descriptors: [descriptor], generatedAt: .init(timeIntervalSince1970: 1))
        )
        let adapter = MenuBarLayoutEditorAdapter(discoverySession: session)

        await adapter.refresh()
        await adapter.resetSuggestedLayout()

        XCTAssertEqual(
            session.refreshInvalidations,
            [
                .layoutEditorPresented,
                .layoutReset,
            ]
        )
        XCTAssertEqual(session.resetSuggestedLayoutCount, 1)
    }

    func testViewFilesDoNotReachIntoRuntimeLayersDirectly() throws {
        try assertSource(
            named: SourceResource.menuBarSearchPanel,
            doesNotContain: [
                "AppState",
                "DiscoveryRuntime",
                "AXRuntime",
                "AXActivationResolver",
                "DiscoveryService",
                "AXObservationService",
                "DisplayRuntime",
                "PanelService",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarSearchModel,
            doesNotContain: [
                "AppState",
                "DiscoveryRuntime",
                "AXRuntime",
                "AXActivationResolver",
                "DiscoveryService",
                "AXObservationService",
                "DisplayRuntime",
                "PanelService",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarLayoutSettingsPane,
            doesNotContain: [
                "AppState",
                "DiscoveryRuntime",
                "AXRuntime",
                "AXActivationResolver",
                "DiscoveryService",
                "AXObservationService",
                "DisplayRuntime",
                "PanelService",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarAppearanceEditorPanel,
            doesNotContain: [
                "AppState",
                "DiscoveryRuntime",
                "AXRuntime",
                "AXActivationResolver",
                "DiscoveryService",
                "AXObservationService",
                "DisplayRuntime",
                "PanelService",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarPresentationService,
            doesContain: [
                "struct Dependencies",
                "func performSetup(with dependencies: Dependencies)",
            ],
            doesNotContain: [
                "AppState",
                "private weak var appState",
                "performSetup(with appState:",
            ]
        )

        try assertSource(
            named: SourceResource.iceBarAdapter,
            doesContain: [
                "protocol IceBarDiscoverySessionControlling",
            ],
            doesNotContain: [
                "private let discoverySession: DiscoverySession",
            ]
        )
    }

    func testSnapshotAdaptersDoNotReachIntoDiscoveryInternals() throws {
        try assertSource(
            named: SourceResource.menuBarSearchAdapter,
            doesNotContain: [
                "DiscoveryService",
                "AXObservationService",
                "AXRuntime",
                "AXActivationResolver",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarLayoutEditorAdapter,
            doesNotContain: [
                "DiscoveryService",
                "AXObservationService",
                "AXRuntime",
                "AXActivationResolver",
            ]
        )

        try assertSource(
            named: SourceResource.iceBarAdapter,
            doesNotContain: [
                "DiscoveryService",
                "AXObservationService",
                "AXRuntime",
                "AXActivationResolver",
            ]
        )

        try assertSource(
            named: SourceResource.panelRuntime,
            doesNotContain: [
                "DiscoveryService",
                "AXObservationService",
                "AXRuntime",
                "AXActivationResolver",
            ]
        )
    }

    func testMenuChromeBoundaryFilesUseDependenciesInsteadOfAppState() throws {
        try assertSource(
            named: SourceResource.menuChromeController,
            doesContain: [
                "struct Dependencies",
                "func performSetup(with dependencies: Dependencies)",
                "StatusItemIconRenderer.image(",
                "generalSettings.$iceIcon",
            ],
            doesNotContain: [
                "private weak var appState",
                "performSetup(with appState:",
                "DiscoveryRuntime",
                "AXRuntime",
                "AXActivationResolver",
                "DisplayRuntime",
                "PanelService",
                "systemSymbolName: \"snowflake\"",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarSessionAdapter,
            doesContain: [
                "struct ProfileMenuEntry",
                "var profileMenuEntries: [ProfileMenuEntry]",
                "func canApplyProfileFromMenu(id: UUID) -> Bool",
            ],
            doesNotContain: []
        )

        try assertSource(
            named: SourceResource.panelRuntime,
            doesContain: [
                "struct Dependencies",
                "func performSetup(with dependencies: Dependencies)",
                "protocol PanelChromeControlling",
            ],
            doesNotContain: [
                "private weak var appState",
                "performSetup(with appState:",
            ]
        )

        try assertSource(
            named: SourceResource.iceBar,
            doesContain: [
                "func show(",
                "group: VirtualGroup",
            ],
            doesNotContain: [
                "AppState",
                "performSetup(with appState:",
                "DiscoveryRuntime",
                "AXRuntime",
                "DisplayRuntime",
                "PanelService",
                "MenuBarSection",
                "currentSection",
                "show(section:",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarAppearanceManager,
            doesContain: [
                "struct Dependencies",
                "func performSetup(with dependencies: Dependencies)",
            ],
            doesNotContain: [
                "private weak var appState",
                "performSetup(with appState:",
            ]
        )

        try assertSource(
            named: SourceResource.settingsResetter,
            doesNotContain: [
                "AppState",
                "appState?",
                "resetAppearance()",
                "appearanceManager?.configuration",
            ]
        )

        try assertSource(
            named: SourceResource.settingsSessionAdapter,
            doesContain: [
                "settings.resetAllSettingsToDefaults()",
                "appearanceManager.configuration = Defaults.DefaultValue.menuBarAppearanceConfigurationV2",
            ],
            doesNotContain: [
                "AppState",
            ]
        )
    }

    func testIceBarAdapterConsumesPublishedDiscoverySnapshotsInsteadOfLegacyRuntime() throws {
        try assertSource(
            named: SourceResource.iceBarAdapter,
            doesContain: [
                "@Published private(set) var snapshot: DiscoverySnapshot",
                "protocol IceBarDiscoverySessionControlling",
                "discoverySession.discoverySnapshotPublisher",
                "discoverySession.isReadyPublisher",
            ],
            doesNotContain: [
                "DiscoveryRuntime",
                "AXRuntime",
                "AXActivationResolver",
                "DisplayRuntime",
            ]
        )
    }

    private func assertSource(
        named resourceName: String,
        doesContain requiredTokens: [String] = [],
        doesNotContain forbiddenTokens: [String]
    ) throws {
        let source = try ThawTestResourceSupport.sourceText(named: resourceName)

        for token in requiredTokens {
            XCTAssertTrue(source.contains(token), "Missing \(token) in \(resourceName).swift")
        }

        for token in forbiddenTokens {
            XCTAssertFalse(source.contains(token), "Unexpected \(token) in \(resourceName).swift")
        }
    }

    private func makeDescriptor(
        bundleID: String,
        title: String,
        role: String,
        stableKeyBasis: String,
        canonicalID: MenuExtraCanonicalID? = nil
    ) -> MenuExtraDescriptor {
        let identity = MenuExtraIdentity.make(
            bundleID: bundleID,
            title: title,
            role: role,
            stableKeyBasis: stableKeyBasis
        )

        return MenuExtraDescriptor(
            canonicalID: canonicalID ?? .generated(),
            identity: identity,
            ownerPID: 42,
            bundleIdentifier: bundleID,
            bundleURL: nil,
            applicationName: bundleID,
            title: title,
            rawRole: role,
            frame: .zero,
            displayID: nil,
            displayUUID: nil,
            capability: .axPress,
            group: .hidden,
            customName: nil
        )
    }
}

private extension ViewAdapterTests {
    func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        condition: @Sendable @escaping () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }

            try? await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for adapter publication")
    }
}

private enum SourceResource {
    static let menuBarSearchPanel = "MenuBarSearchPanel"
    static let menuBarSearchModel = "MenuBarSearchModel"
    static let menuBarLayoutSettingsPane = "MenuBarLayoutSettingsPane"
    static let menuBarAppearanceEditorPanel = "MenuBarAppearanceEditorPanel"
    static let menuBarPresentationService = "MenuBarPresentationService"
    static let menuBarSearchAdapter = "MenuBarSearchAdapter"
    static let menuBarLayoutEditorAdapter = "MenuBarLayoutEditorAdapter"
    static let iceBarAdapter = "IceBarAdapter"
    static let panelRuntime = "PanelRuntime"
    static let menuChromeController = "MenuChromeController"
    static let menuBarSessionAdapter = "MenuBarSessionAdapter"
    static let iceBar = "IceBar"
    static let menuBarAppearanceManager = "MenuBarAppearanceManager"
    static let settingsResetter = "SettingsResetter"
    static let settingsSessionAdapter = "SettingsSessionAdapter"
}

private final class PublicationProbe {
    private let lock = NSLock()
    private var isMainThread = false
    private var lastSnapshot: DiscoverySnapshot?
    private var didFulfill = false

    func record(threadIsMain: Bool, snapshot: DiscoverySnapshot) {
        lock.lock()
        isMainThread = isMainThread || threadIsMain
        lastSnapshot = snapshot
        lock.unlock()
    }

    func receivedOnMainThread() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isMainThread
    }

    func snapshot() -> DiscoverySnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return lastSnapshot
    }

    func markFulfilled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didFulfill else {
            return false
        }
        didFulfill = true
        return true
    }
}

@MainActor
final class StubDiscoverySession: MenuBarDiscoverySessionControlling {
    @Published var snapshot: DiscoverySnapshot

    var snapshotPublisher: AnyPublisher<DiscoverySnapshot, Never> {
        $snapshot.eraseToAnyPublisher()
    }

    private(set) var refreshInvalidations = [DiscoveryInvalidation]()
    private(set) var renamedCanonicalIDs = [(MenuExtraCanonicalID, String?)]()
    private(set) var assignedGroups = [(VirtualGroup, MenuExtraCanonicalID)]()
    private(set) var reorderedDescriptors = [MenuExtraDescriptor]()
    private(set) var resetSuggestedLayoutCount = 0
    private(set) var activateCallCount = 0

    init(snapshot: DiscoverySnapshot) {
        self.snapshot = snapshot
    }

    func refresh(_ invalidation: DiscoveryInvalidation) async {
        refreshInvalidations.append(invalidation)
    }

    func rename(canonicalID: MenuExtraCanonicalID, to customName: String?) async {
        renamedCanonicalIDs.append((canonicalID, customName))
    }

    func assign(_ group: VirtualGroup, to canonicalID: MenuExtraCanonicalID) async {
        assignedGroups.append((group, canonicalID))
    }

    func reorder(group: VirtualGroup, descriptors: [MenuExtraDescriptor]) async {
        reorderedDescriptors = descriptors
        snapshot = DiscoverySnapshot(
            descriptors: descriptors.map { descriptor in
                var copy = descriptor
                copy.group = group
                return copy
            },
            generatedAt: Date()
        )
    }

    func resetSuggestedLayout() async {
        resetSuggestedLayoutCount += 1
    }
}

@MainActor
private final class StubPanelInteractionController: PanelInteractionHandling {
    private(set) var activatedCommands = [ActivationCommand]()
    private(set) var interactionCallCount = 0

    func interactWithPanel(using command: ActivationCommand) async -> PanelInteractionResult {
        interactionCallCount += 1
        activatedCommands.append(command)
        return PanelInteractionResult(outcome: .openedUI, disposition: .dismiss)
    }
}
