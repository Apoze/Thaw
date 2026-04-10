//
//  PanelActivationIntegrationTests.swift
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
final class PanelActivationIntegrationTests: XCTestCase {
    func testSearchAdapterUsesActivationServiceTransactionallyForRepeatedActivation() async {
        let descriptor = makeDescriptor(
            bundleID: "com.example.search",
            title: "Search Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "search-panel"
        )
        let executor = RecordingActivationExecutor()
        let displayService = DisplayService(workspaceEventSource: WorkspaceEventSource())
        let contextProvider = MockActivationContextProvider(descriptors: [descriptor])
        let activationService = ActivationService(
            executor: executor,
            contextProvider: contextProvider,
            displayService: displayService
        )
        let session = StubDiscoverySession(
            snapshot: DiscoverySnapshot(descriptors: [descriptor], generatedAt: .init(timeIntervalSince1970: 1))
        )
        let adapter = MenuBarSearchAdapter(
            discoverySession: session,
            panelInteractionController: activationService
        )

        async let first = adapter.activate(
            canonicalID: descriptor.canonicalID,
            surface: .search,
            intent: .automatic
        )
        async let second = adapter.activate(
            canonicalID: descriptor.canonicalID,
            surface: .search,
            intent: .automatic
        )

        let outcomes: [PanelInteractionResult] = await [first, second]

        XCTAssertEqual(
            outcomes,
            [
                PanelInteractionResult(outcome: .openedUI, disposition: .dismiss),
                PanelInteractionResult(outcome: .openedUI, disposition: .dismiss),
            ]
        )
        XCTAssertEqual(executor.callCount, 1)
        XCTAssertEqual(executor.recordedCommands, [
            ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .search,
                intent: .automatic
            ),
        ])
        XCTAssertEqual(session.activateCallCount, 0)
        let refreshInvalidations = await contextProvider.refreshInvalidations()
        XCTAssertEqual(refreshInvalidations, [
            .activationFollowUp(
                canonicalID: descriptor.canonicalID,
                surface: .search,
                intent: .automatic
            ),
        ])
    }

    func testActivationServiceMapsSuccessfulPanelInteractionToDismissal() async {
        let descriptor = makeDescriptor(
            bundleID: "com.example.panel",
            title: "Panel Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "panel-interaction"
        )
        let executor = RecordingActivationExecutor()
        let displayService = DisplayService(workspaceEventSource: WorkspaceEventSource())
        let contextProvider = MockActivationContextProvider(descriptors: [descriptor])
        let activationService = ActivationService(
            executor: executor,
            contextProvider: contextProvider,
            displayService: displayService
        )

        let result = await activationService.interactWithPanel(
            using: ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .quickAccess,
                intent: .primary
            )
        )

        XCTAssertEqual(result.outcome, .openedUI)
        XCTAssertEqual(result.disposition, .dismiss)
        XCTAssertEqual(executor.callCount, 1)
        XCTAssertEqual(executor.recordedCommands, [
            ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .quickAccess,
                intent: .primary
            ),
        ])
        let refreshInvalidations = await contextProvider.refreshInvalidations()
        XCTAssertEqual(refreshInvalidations, [
            .activationFollowUp(
                canonicalID: descriptor.canonicalID,
                surface: .quickAccess,
                intent: .primary
            ),
        ])
    }

    func testSearchAdapterKeepsPresentationOnRecoverableFailureWithoutLegacyFallback() async {
        let descriptor = makeDescriptor(
            bundleID: "com.example.search",
            title: "Search Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "search-panel-failure"
        )
        let executor = RecordingActivationExecutor(outcome: .failedRecoverable)
        let displayService = DisplayService(workspaceEventSource: WorkspaceEventSource())
        let contextProvider = MockActivationContextProvider(descriptors: [descriptor])
        let activationService = ActivationService(
            executor: executor,
            contextProvider: contextProvider,
            displayService: displayService
        )
        let session = StubDiscoverySession(
            snapshot: DiscoverySnapshot(descriptors: [descriptor], generatedAt: .init(timeIntervalSince1970: 1))
        )
        let adapter = MenuBarSearchAdapter(
            discoverySession: session,
            panelInteractionController: activationService
        )

        let result = await adapter.activate(
            canonicalID: descriptor.canonicalID,
            surface: .search,
            intent: .automatic
        )

        XCTAssertEqual(
            result,
            PanelInteractionResult(outcome: .failedRecoverable, disposition: .keepPresented)
        )
        XCTAssertEqual(executor.callCount, 1)
        XCTAssertEqual(session.activateCallCount, 0)
        let refreshInvalidations = await contextProvider.refreshInvalidations()
        XCTAssertTrue(refreshInvalidations.isEmpty)
    }

    private func makeDescriptor(
        bundleID: String,
        title: String,
        role: String,
        stableKeyBasis: String
    ) -> MenuExtraDescriptor {
        let identity = MenuExtraIdentity.make(
            bundleID: bundleID,
            title: title,
            role: role,
            stableKeyBasis: stableKeyBasis
        )

        return MenuExtraDescriptor(
            canonicalID: .generated(),
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

private actor MockActivationContextProvider: ActivationContextProviding {
    private let descriptorsByCanonicalID: [MenuExtraCanonicalID: MenuExtraDescriptor]
    private var refreshInvalidations = [DiscoveryInvalidation]()
    private var thawInitiatedActivationCount = 0

    init(descriptors: [MenuExtraDescriptor]) {
        descriptorsByCanonicalID = Dictionary(
            uniqueKeysWithValues: descriptors.map { ($0.canonicalID, $0) }
        )
    }

    func descriptor(for canonicalID: MenuExtraCanonicalID) async -> MenuExtraDescriptor? {
        descriptorsByCanonicalID[canonicalID]
    }

    func recordThawInitiatedActivation() async {
        thawInitiatedActivationCount += 1
    }

    func refresh(invalidation: DiscoveryInvalidation) async {
        refreshInvalidations.append(invalidation)
    }

    func refreshInvalidations() async -> [DiscoveryInvalidation] {
        refreshInvalidations
    }
}

@MainActor
private final class RecordingActivationExecutor: ActivationExecuting {
    private let outcome: ActivationOutcome
    private(set) var callCount = 0
    private(set) var recordedCommands = [ActivationCommand]()

    init(outcome: ActivationOutcome = .openedUI) {
        self.outcome = outcome
    }

    func execute(
        command: ActivationCommand,
        descriptor _: MenuExtraDescriptor,
        displayService _: DisplayService
    ) async -> ActivationOutcome {
        callCount += 1
        recordedCommands.append(command)
        try? await Task.sleep(for: .milliseconds(25))
        return outcome
    }
}

@MainActor
private final class StubDiscoverySession: MenuBarDiscoverySessionControlling {
    @Published var snapshot: DiscoverySnapshot

    var snapshotPublisher: AnyPublisher<DiscoverySnapshot, Never> {
        $snapshot.eraseToAnyPublisher()
    }

    init(snapshot: DiscoverySnapshot) {
        self.snapshot = snapshot
    }

    func refresh(_ invalidation: DiscoveryInvalidation) async {
        _ = invalidation
    }

    private(set) var activateCallCount = 0

    func rename(canonicalID: MenuExtraCanonicalID, to customName: String?) async {
        _ = canonicalID
        _ = customName
    }

    func activate(_ command: ActivationCommand) async -> ActivationOutcome {
        activateCallCount += 1
        _ = command
        return .openedUI
    }

    func assign(_ group: VirtualGroup, to canonicalID: MenuExtraCanonicalID) async {
        _ = group
        _ = canonicalID
    }

    func reorder(group: VirtualGroup, descriptors: [MenuExtraDescriptor]) async {
        _ = group
        snapshot = DiscoverySnapshot(descriptors: descriptors, generatedAt: Date())
    }

    func resetSuggestedLayout() async {
    }
}
