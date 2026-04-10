//
//  ActivationServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

final class ActivationServiceTests: XCTestCase {
    func testCoalescesRepeatedActivationsForSameCanonicalID() async {
        let descriptor = await MainActor.run {
            makeDescriptor(id: "com.example.alpha::stable::AXMenuBarItem")
        }
        let dependencies = await makeDependencies(descriptor: descriptor, outcome: .openedUI)
        let command = ActivationCommand(
            canonicalID: descriptor.canonicalID,
            surface: .quickAccess,
            intent: .primary
        )

        async let first = dependencies.service.activate(command)
        async let second = dependencies.service.activate(command)

        let outcomes = await [first, second]

        XCTAssertEqual(outcomes, [.openedUI, .openedUI])
        let callCount = await MainActor.run { dependencies.executor.callCount }
        XCTAssertEqual(callCount, 1)
        let refreshes = await dependencies.context.recordedRefreshes()
        XCTAssertEqual(refreshes, [command.followUpInvalidation])
    }

    func testSuccessfulActivationTriggersTypedFollowUpRefresh() async {
        let descriptor = await MainActor.run {
            makeDescriptor(id: "com.example.beta::stable::AXMenuBarItem")
        }
        let dependencies = await makeDependencies(descriptor: descriptor, outcome: .openedApp)
        let command = ActivationCommand(
            canonicalID: descriptor.canonicalID,
            surface: .search,
            intent: .automatic
        )

        let outcome = await dependencies.service.activate(command)

        XCTAssertEqual(outcome, .openedApp)
        let refreshes = await dependencies.context.recordedRefreshes()
        XCTAssertEqual(refreshes, [command.followUpInvalidation])
    }

    func testPanelInteractionDismissesOnSuccessfulActivation() async {
        let descriptor = await MainActor.run {
            makeDescriptor(id: "com.example.gamma::stable::AXMenuBarItem")
        }
        let dependencies = await makeDependencies(descriptor: descriptor, outcome: .openedUI)
        let command = ActivationCommand(
            canonicalID: descriptor.canonicalID,
            surface: .panel,
            intent: .primary
        )

        let result = await dependencies.service.interactWithPanel(using: command)

        XCTAssertEqual(result.outcome, .openedUI)
        XCTAssertEqual(result.disposition, .dismiss)
    }

    func testPanelInteractionKeepsPresentationOnRecoverableFailure() async {
        let descriptor = await MainActor.run {
            makeDescriptor(id: "com.example.delta::stable::AXMenuBarItem")
        }
        let dependencies = await makeDependencies(descriptor: descriptor, outcome: .failedRecoverable)
        let command = ActivationCommand(
            canonicalID: descriptor.canonicalID,
            surface: .panel,
            intent: .secondary
        )

        let result = await dependencies.service.interactWithPanel(using: command)

        XCTAssertEqual(result.outcome, .failedRecoverable)
        XCTAssertEqual(result.disposition, .keepPresented)
        let refreshes = await dependencies.context.recordedRefreshes()
        XCTAssertTrue(refreshes.isEmpty)
    }

    func testMissingDescriptorDoesNotInvokeExecutorOrRefresh() async {
        let descriptor = await MainActor.run {
            makeDescriptor(id: "com.example.missing::stable::AXMenuBarItem")
        }
        let dependencies = await makeDependencies(descriptor: descriptor, outcome: .openedUI)
        let missingCommand = ActivationCommand(
            canonicalID: MenuExtraCanonicalID(rawValue: "missing-canonical-id"),
            surface: .panel,
            intent: .primary
        )

        let outcome = await dependencies.service.activate(missingCommand)

        XCTAssertEqual(outcome, .failedRecoverable)
        let callCount = await MainActor.run { dependencies.executor.callCount }
        XCTAssertEqual(callCount, 0)
        let refreshes = await dependencies.context.recordedRefreshes()
        XCTAssertTrue(refreshes.isEmpty)
    }

    @MainActor
    private func makeDescriptor(id: String) -> MenuExtraDescriptor {
        let components = id.components(separatedBy: "::")
        let identity = MenuExtraIdentity(
            bundleID: components[0],
            stableKey: components[1],
            normalizedTitle: "alpha",
            role: components[2]
        )

        return MenuExtraDescriptor(
            canonicalID: MenuExtraCanonicalID(rawValue: "runtime-\(components[0])"),
            identity: identity,
            ownerPID: 42,
            bundleIdentifier: identity.bundleID,
            bundleURL: nil,
            applicationName: identity.bundleID,
            title: "Alpha",
            rawRole: identity.role,
            frame: nil,
            displayID: nil,
            displayUUID: nil,
            capability: .axPress,
            group: .pinned,
            customName: nil
        )
    }

    private func makeDependencies(
        descriptor: MenuExtraDescriptor,
        outcome: ActivationOutcome
    ) async -> (
        service: ActivationService,
        executor: MockActivationExecutor,
        context: MockActivationContextProvider
    ) {
        let executor = await MainActor.run { MockActivationExecutor(outcome: outcome) }
        let context = MockActivationContextProvider(descriptor: descriptor)
        let displayService = await MainActor.run {
            DisplayService(workspaceEventSource: WorkspaceEventSource())
        }
        let service = ActivationService(
            executor: executor,
            contextProvider: context,
            displayService: displayService
        )

        return (service, executor, context)
    }
}

private actor MockActivationContextProvider: ActivationContextProviding {
    private let descriptorValue: MenuExtraDescriptor
    private var refreshes = [DiscoveryInvalidation]()

    init(descriptor: MenuExtraDescriptor) {
        descriptorValue = descriptor
    }

    func descriptor(for canonicalID: MenuExtraCanonicalID) async -> MenuExtraDescriptor? {
        descriptorValue.canonicalID == canonicalID ? descriptorValue : nil
    }

    func recordThawInitiatedActivation() async {}

    func refresh(invalidation: DiscoveryInvalidation) async {
        refreshes.append(invalidation)
    }

    func recordedRefreshes() async -> [DiscoveryInvalidation] {
        refreshes
    }
}

@MainActor
private final class MockActivationExecutor: ActivationExecuting {
    private let outcome: ActivationOutcome
    var callCount = 0

    init(outcome: ActivationOutcome) {
        self.outcome = outcome
    }

    func execute(
        command _: ActivationCommand,
        descriptor _: MenuExtraDescriptor,
        displayService _: DisplayService
    ) async -> ActivationOutcome {
        callCount += 1
        try? await Task.sleep(for: .milliseconds(50))
        return outcome
    }
}
