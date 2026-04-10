//
//  AXActivationExecutorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
import XCTest
@testable import Thaw

@MainActor
final class AXActivationExecutorTests: XCTestCase {
    func testRetryableAXFailureReResolvesOnceAndSucceeds() async {
        let descriptor = makeDescriptor(id: "com.example.retry-success::stable::AXMenuBarItem")
        let element = UIElement(AXUIElementCreateSystemWide())
        let resolver = StubAXActivationResolver(candidates: [
            ResolvedCandidate(element: element, descriptor: descriptor),
            ResolvedCandidate(element: element, descriptor: descriptor),
        ])
        var performAttemptCount = 0
        let environment = AXActivationEnvironment(
            isProcessTrusted: { true },
            supportedActions: { _ in [.press] },
            performAction: { _, _, _ in
                performAttemptCount += 1
                if performAttemptCount == 1 {
                    throw AXError.invalidUIElement
                }
            },
            shownMenu: { _ in
                performAttemptCount >= 2 ? element : nil
            },
            onScreenWindows: { [] },
            activateOwningApplication: { _ in false }
        )
        let executor = AXActivationExecutor(
            axActivationResolver: resolver,
            environment: environment,
            confirmationWindow: ActivationConfirmationWindow(pollInterval: .zero, maxPollCount: 1)
        )

        let outcome = await executor.execute(
            command: ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .quickAccess,
                intent: .primary
            ),
            descriptor: descriptor,
            displayService: DisplayService(workspaceEventSource: WorkspaceEventSource())
        )

        XCTAssertEqual(outcome, .openedUI)
        XCTAssertEqual(resolver.resolveCount, 2)
        XCTAssertEqual(performAttemptCount, 2)
    }

    func testRetryableAXFailureStopsAfterSingleReResolution() async {
        let descriptor = makeDescriptor(id: "com.example.retry-fail::stable::AXMenuBarItem")
        let element = UIElement(AXUIElementCreateSystemWide())
        let resolver = StubAXActivationResolver(candidates: [
            ResolvedCandidate(element: element, descriptor: descriptor),
            ResolvedCandidate(element: element, descriptor: descriptor),
        ])
        var performAttemptCount = 0
        let environment = AXActivationEnvironment(
            isProcessTrusted: { true },
            supportedActions: { _ in [.press] },
            performAction: { _, _, _ in
                performAttemptCount += 1
                throw AXError.cannotComplete
            },
            shownMenu: { _ in nil },
            onScreenWindows: { [] },
            activateOwningApplication: { _ in false }
        )
        let executor = AXActivationExecutor(
            axActivationResolver: resolver,
            environment: environment,
            confirmationWindow: ActivationConfirmationWindow(pollInterval: .zero, maxPollCount: 1)
        )

        let outcome = await executor.execute(
            command: ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .panel,
                intent: .primary
            ),
            descriptor: descriptor,
            displayService: DisplayService(workspaceEventSource: WorkspaceEventSource())
        )

        XCTAssertEqual(outcome, .failedRecoverable)
        XCTAssertEqual(resolver.resolveCount, 2)
        XCTAssertEqual(performAttemptCount, 2)
    }

    func testNonRetryableAXFailureReturnsTerminalWithoutRetry() async {
        let descriptor = makeDescriptor(id: "com.example.terminal::stable::AXMenuBarItem")
        let element = UIElement(AXUIElementCreateSystemWide())
        let resolver = StubAXActivationResolver(candidates: [
            ResolvedCandidate(element: element, descriptor: descriptor),
        ])
        var performAttemptCount = 0
        let environment = AXActivationEnvironment(
            isProcessTrusted: { true },
            supportedActions: { _ in [.press] },
            performAction: { _, _, _ in
                performAttemptCount += 1
                throw AXError.failure
            },
            shownMenu: { _ in nil },
            onScreenWindows: { [] },
            activateOwningApplication: { _ in false }
        )
        let executor = AXActivationExecutor(
            axActivationResolver: resolver,
            environment: environment,
            confirmationWindow: ActivationConfirmationWindow(pollInterval: .zero, maxPollCount: 1)
        )

        let outcome = await executor.execute(
            command: ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .search,
                intent: .automatic
            ),
            descriptor: descriptor,
            displayService: DisplayService(workspaceEventSource: WorkspaceEventSource())
        )

        XCTAssertEqual(outcome, .failedTerminal)
        XCTAssertEqual(resolver.resolveCount, 1)
        XCTAssertEqual(performAttemptCount, 1)
    }

    func testConfirmationWindowReturnsOpenedAppWhenNoInterfaceObserved() async {
        let descriptor = makeDescriptor(id: "com.example.confirm-app::stable::AXMenuBarItem")
        let element = UIElement(AXUIElementCreateSystemWide())
        let resolver = StubAXActivationResolver(candidates: [
            ResolvedCandidate(element: element, descriptor: descriptor),
        ])
        let environment = AXActivationEnvironment(
            isProcessTrusted: { true },
            supportedActions: { _ in [.press] },
            performAction: { _, _, _ in },
            shownMenu: { _ in nil },
            onScreenWindows: { [] },
            activateOwningApplication: { _ in false }
        )
        let executor = AXActivationExecutor(
            axActivationResolver: resolver,
            environment: environment,
            confirmationWindow: ActivationConfirmationWindow(pollInterval: .zero, maxPollCount: 2)
        )

        let outcome = await executor.execute(
            command: ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .quickAccess,
                intent: .secondary
            ),
            descriptor: descriptor,
            displayService: DisplayService(workspaceEventSource: WorkspaceEventSource())
        )

        XCTAssertEqual(outcome, .openedApp)
        XCTAssertEqual(resolver.resolveCount, 1)
    }

    func testConfirmationWindowReturnsOpenedUIWhenMenuAppears() async {
        let descriptor = makeDescriptor(id: "com.example.confirm-ui::stable::AXMenuBarItem")
        let element = UIElement(AXUIElementCreateSystemWide())
        let resolver = StubAXActivationResolver(candidates: [
            ResolvedCandidate(element: element, descriptor: descriptor),
        ])
        let environment = AXActivationEnvironment(
            isProcessTrusted: { true },
            supportedActions: { _ in [.press] },
            performAction: { _, _, _ in },
            shownMenu: { _ in element },
            onScreenWindows: { [] },
            activateOwningApplication: { _ in false }
        )
        let executor = AXActivationExecutor(
            axActivationResolver: resolver,
            environment: environment,
            confirmationWindow: ActivationConfirmationWindow(pollInterval: .zero, maxPollCount: 1)
        )

        let outcome = await executor.execute(
            command: ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .archive,
                intent: .primary
            ),
            descriptor: descriptor,
            displayService: DisplayService(workspaceEventSource: WorkspaceEventSource())
        )

        XCTAssertEqual(outcome, .openedUI)
        XCTAssertEqual(resolver.resolveCount, 1)
    }

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
}

@MainActor
private final class StubAXActivationResolver: AXActivationResolving {
    private var candidates: [ResolvedCandidate?]
    private(set) var resolveCount = 0

    init(candidates: [ResolvedCandidate?]) {
        self.candidates = candidates
    }

    func resolveCandidate(
        _ descriptor: MenuExtraDescriptor,
        displaySnapshot _: DisplayObservationSnapshot
    ) async -> ResolvedCandidate? {
        resolveCount += 1

        if candidates.isEmpty {
            return nil
        }

        let next = candidates.removeFirst()
        return next?.descriptor.canonicalID == descriptor.canonicalID ? next : nil
    }
}
