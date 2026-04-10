//
//  DiscoveryIntegrationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import XCTest
@testable import Thaw

@MainActor
final class DiscoveryIntegrationTests: XCTestCase {
    func testDiscoverySessionRefreshesFromWorkspaceLaunchInvalidation() async throws {
        let launchedProcessIdentifier = NSRunningApplication.current.processIdentifier
        let firstDescriptor = makeDescriptor(
            ownerPID: launchedProcessIdentifier,
            bundleID: "com.example.discovery",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-session-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: launchedProcessIdentifier,
            bundleID: "com.example.discovery",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-session-second"
        )

        let workspaceCenter = NotificationCenter()
        let screenCenter = NotificationCenter()
        let frontmostApplication = CurrentValueSubject<WorkspaceApplicationInfo?, Never>(nil)
        let menuBarOwner = CurrentValueSubject<WorkspaceApplicationInfo?, Never>(nil)
        let workspaceEventSource = WorkspaceEventSource(
            environment: .init(
                workspaceNotificationCenter: workspaceCenter,
                applicationNotificationCenter: screenCenter,
                initialFrontmostApplication: { nil },
                frontmostApplicationPublisher: frontmostApplication.eraseToAnyPublisher(),
                menuBarOwningApplicationPublisher: menuBarOwner.eraseToAnyPublisher()
            )
        )
        let displayService = DisplayService(workspaceEventSource: workspaceEventSource)
        let harness = try makeHarness(
            workspaceEventSource: workspaceEventSource,
            displayService: displayService,
            observationService: StreamingScopedDiscoveryObserver(
                allBatches: [[firstDescriptor]],
                scopedBatches: [
                    [launchedProcessIdentifier]: [[firstDescriptor, secondDescriptor]],
                ]
            )
        )

        workspaceEventSource.performSetup()
        displayService.performSetup()
        harness.session.performSetup()

        await waitUntil {
            harness.session.isReady && harness.session.snapshot.descriptors.count == 1
        }

        workspaceCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        await waitUntil {
            harness.session.snapshot.descriptors.count == 2
        }

        XCTAssertEqual(
            harness.session.snapshot.descriptors.map(\.canonicalID),
            [firstDescriptor.canonicalID, secondDescriptor.canonicalID]
        )
    }

    func testDiscoverySessionPublishesServiceBackedLayoutMutations() async throws {
        let descriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "Layout Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-session-layout"
        )
        let workspaceEventSource = WorkspaceEventSource(
            environment: .init(
                workspaceNotificationCenter: NotificationCenter(),
                applicationNotificationCenter: NotificationCenter(),
                initialFrontmostApplication: { nil },
                frontmostApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher(),
                menuBarOwningApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher()
            )
        )
        let displayService = DisplayService(workspaceEventSource: workspaceEventSource)
        let harness = try makeHarness(
            workspaceEventSource: workspaceEventSource,
            displayService: displayService,
            observationService: StreamingScopedDiscoveryObserver(allBatches: [[descriptor]])
        )

        workspaceEventSource.performSetup()
        displayService.performSetup()
        harness.session.performSetup()

        await waitUntil {
            harness.session.snapshot.descriptors.first?.group == .hidden
        }

        let initialSnapshot = harness.session.snapshot
        await harness.session.assign(.archive, to: descriptor.canonicalID)

        await waitUntil {
            harness.session.snapshot.descriptors.first?.group == .archive
        }

        XCTAssertEqual(initialSnapshot.descriptors.first?.group, .hidden)
        XCTAssertEqual(harness.session.snapshot.descriptors.first?.group, .archive)
    }

    func testDiscoverySessionRefreshesFromAXScopedInvalidation() async throws {
        let firstDescriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-session-ax-first"
        )
        let updatedFirstDescriptor = MenuExtraDescriptor(
            canonicalID: firstDescriptor.canonicalID,
            identity: firstDescriptor.identity,
            ownerPID: firstDescriptor.ownerPID,
            bundleIdentifier: firstDescriptor.bundleIdentifier,
            bundleURL: firstDescriptor.bundleURL,
            applicationName: firstDescriptor.applicationName,
            title: "First Item Updated",
            rawRole: firstDescriptor.rawRole,
            frame: firstDescriptor.frame,
            displayID: firstDescriptor.displayID,
            displayUUID: firstDescriptor.displayUUID,
            capability: firstDescriptor.capability,
            group: .hidden,
            customName: nil
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.discovery.other",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-session-ax-second"
        )

        let workspaceEventSource = WorkspaceEventSource(
            environment: .init(
                workspaceNotificationCenter: NotificationCenter(),
                applicationNotificationCenter: NotificationCenter(),
                initialFrontmostApplication: { nil },
                frontmostApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher(),
                menuBarOwningApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher()
            )
        )
        let displayService = DisplayService(workspaceEventSource: workspaceEventSource)
        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [[firstDescriptor, secondDescriptor]],
            scopedBatches: [
                [firstDescriptor.ownerPID]: [[updatedFirstDescriptor]],
            ]
        )
        let harness = try makeHarness(
            workspaceEventSource: workspaceEventSource,
            displayService: displayService,
            observationService: observationService
        )

        workspaceEventSource.performSetup()
        displayService.performSetup()
        harness.session.performSetup()

        await waitUntil {
            harness.session.snapshot.descriptors.count == 2
        }

        await observationService.emit(
            .axStructureChanged(
                bundleID: firstDescriptor.bundleIdentifier,
                processIdentifier: firstDescriptor.ownerPID
            )
        )

        await waitUntil {
            harness.session.snapshot.descriptors.contains(where: {
                $0.ownerPID == firstDescriptor.ownerPID && $0.title == "First Item Updated"
            })
        }

        XCTAssertEqual(
            harness.session.snapshot.descriptors.first(where: { $0.ownerPID == secondDescriptor.ownerPID })?.title,
            "Second Item"
        )
    }

    private func makeHarness(
        workspaceEventSource: WorkspaceEventSource,
        displayService: DisplayService,
        observationService: some DiscoveryObserving
    ) throws -> DiscoverySessionHarness {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoveryIntegrationTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let paths = ThawPersistencePaths(rootDirectory: tempDirectory)
        let identityRegistry = IdentityRegistry(paths: paths)
        let layoutService = LayoutService(paths: paths)
        let service = DiscoveryService(
            displayService: displayService,
            identityRegistry: identityRegistry,
            workspaceEventSource: workspaceEventSource,
            observationService: observationService,
            layoutService: layoutService
        )

        return DiscoverySessionHarness(
            rootDirectory: tempDirectory,
            session: DiscoverySession(
                service: service,
                workspaceEventSource: workspaceEventSource
            )
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(4),
        pollInterval: Duration = .milliseconds(20),
        condition: @MainActor @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for integration condition")
    }

    private func makeDescriptor(
        ownerPID: pid_t = 42,
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
            ownerPID: ownerPID,
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

private final class DiscoverySessionHarness {
    let rootDirectory: URL
    let session: DiscoverySession

    init(
        rootDirectory: URL,
        session: DiscoverySession
    ) {
        self.rootDirectory = rootDirectory
        self.session = session
    }

    deinit {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private actor StreamingScopedDiscoveryObserver: DiscoveryObserving {
    nonisolated let invalidationUpdates: AsyncStream<DiscoveryInvalidation>
    private let invalidationContinuation: AsyncStream<DiscoveryInvalidation>.Continuation
    private var remainingBatches: [[MenuExtraDescriptor]]
    private var lastBatch = [MenuExtraDescriptor]()
    private var remainingScopedBatches: [Set<pid_t>: [[MenuExtraDescriptor]]]
    private var lastScopedBatches = [Set<pid_t>: [MenuExtraDescriptor]]()

    init(
        allBatches: [[MenuExtraDescriptor]],
        scopedBatches: [Set<pid_t>: [[MenuExtraDescriptor]]] = [:]
    ) {
        var capturedContinuation: AsyncStream<DiscoveryInvalidation>.Continuation?
        invalidationUpdates = AsyncStream(bufferingPolicy: .bufferingNewest(16)) {
            capturedContinuation = $0
        }
        guard let capturedContinuation else {
            preconditionFailure("StreamingScopedDiscoveryObserver invalidation stream was not initialized")
        }
        invalidationContinuation = capturedContinuation
        remainingBatches = allBatches
        remainingScopedBatches = scopedBatches
    }

    func discoverDescriptors(displaySnapshot _: DisplayObservationSnapshot) async -> [MenuExtraDescriptor] {
        if !remainingBatches.isEmpty {
            lastBatch = remainingBatches.removeFirst()
        }

        return lastBatch
    }

    func discoverDescriptors(
        displaySnapshot _: DisplayObservationSnapshot,
        processIdentifiers: Set<pid_t>
    ) async -> [MenuExtraDescriptor] {
        if var batches = remainingScopedBatches[processIdentifiers], !batches.isEmpty {
            let nextBatch = batches.removeFirst()
            remainingScopedBatches[processIdentifiers] = batches
            lastScopedBatches[processIdentifiers] = nextBatch
            return nextBatch
        }

        return lastScopedBatches[processIdentifiers] ?? []
    }

    func emit(_ invalidation: DiscoveryInvalidation) {
        invalidationContinuation.yield(invalidation)
    }
}
