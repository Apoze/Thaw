//
//  DiscoveryServiceTests.swift
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
final class DiscoveryServiceTests: XCTestCase {
    func testPerformSetupPublishesReadyStateAndInitialSnapshot() async throws {
        let descriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "Initial Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-initial"
        )
        let observationService = StreamingScopedDiscoveryObserver(allBatches: [[descriptor]])
        let harness = try makeHarness(observationService: observationService)

        let initialState = await harness.service.currentState()
        XCTAssertEqual(initialState, .empty)

        await harness.service.performSetup()

        let state = await harness.service.currentState()
        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.snapshot.descriptors, [descriptor])
        XCTAssertEqual(state.layoutSnapshot.groupsByCanonicalID[descriptor.canonicalID.rawValue], .hidden)
        let callCount = await observationService.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testPublishedSnapshotsRemainImmutableAfterLayoutMutation() async throws {
        let descriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "Mutable Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-layout"
        )
        let observationService = StreamingScopedDiscoveryObserver(allBatches: [[descriptor]])
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        let initialState = await harness.service.currentState()

        await harness.service.assign(.archive, to: descriptor.canonicalID)
        let updatedState = await harness.service.currentState()

        XCTAssertEqual(initialState.snapshot.descriptors.first?.group, .hidden)
        XCTAssertEqual(updatedState.snapshot.descriptors.first?.group, .archive)
        XCTAssertEqual(initialState.layoutSnapshot.groupsByCanonicalID[descriptor.canonicalID.rawValue], .hidden)
        XCTAssertEqual(updatedState.layoutSnapshot.groupsByCanonicalID[descriptor.canonicalID.rawValue], .archive)
    }

    func testStateUpdatesStreamPublishesSuccessiveServiceSnapshots() async throws {
        let firstDescriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-stream-first"
        )
        let secondDescriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-stream-second"
        )
        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [
                [firstDescriptor],
                [firstDescriptor, secondDescriptor],
            ]
        )
        let harness = try makeHarness(observationService: observationService)

        let collectedStates = Task { () -> [DiscoveryServiceState] in
            var states = [DiscoveryServiceState]()
            for await state in harness.service.stateUpdates {
                guard !state.snapshot.descriptors.isEmpty else {
                    continue
                }

                states.append(state)
                if states.count == 2 {
                    break
                }
            }
            return states
        }

        await harness.service.performSetup()
        await harness.service.refresh(.profileApplied)

        let states = await collectedStates.value

        XCTAssertEqual(states.map { $0.snapshot.descriptors.count }, [1, 2])
        XCTAssertTrue(states.allSatisfy(\.isReady))
    }

    func testAXInvalidationRefreshesOnlyAffectedProcessDescriptors() async throws {
        let firstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.first",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-partial-first"
        )
        let updatedFirstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.first",
            title: "First Item Updated",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-partial-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.second",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-partial-second"
        )

        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [[firstDescriptor, secondDescriptor]],
            scopedBatches: [
                [101]: [[updatedFirstDescriptor]],
            ]
        )
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        await observationService.emit(
            .axStructureChanged(bundleID: firstDescriptor.bundleIdentifier, processIdentifier: 101)
        )

        await waitUntil {
            let state = await harness.service.currentState()
            return state.snapshot.descriptors.contains(where: {
                $0.ownerPID == 101 && $0.title == "First Item Updated"
            })
        }

        let state = await harness.service.currentState()
        XCTAssertEqual(state.snapshot.descriptors.count, 2)
        XCTAssertEqual(
            state.snapshot.descriptors.first(where: { $0.ownerPID == 101 })?.title,
            "First Item Updated"
        )
        XCTAssertEqual(
            state.snapshot.descriptors.first(where: { $0.ownerPID == 202 })?.title,
            "Second Item"
        )
        let requestedScopes = await observationService.requestedScopes()
        XCTAssertEqual(requestedScopes, [.all, .processIdentifiers([101])])
    }

    func testPermissionInvalidationFallsBackToGlobalRefresh() async throws {
        let firstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.discovery",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-permission-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.discovery",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-permission-second"
        )
        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [
                [firstDescriptor],
                [firstDescriptor, secondDescriptor],
            ]
        )
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        await observationService.emit(.permissionChanged)

        await waitUntil {
            let state = await harness.service.currentState()
            return state.snapshot.descriptors.count == 2
        }

        let requestedScopes = await observationService.requestedScopes()
        XCTAssertEqual(requestedScopes, [.all, .all])
    }

    func testObservationRecoveryRequiredForcesGlobalRefresh() async throws {
        let firstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.discovery",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-recovery-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.discovery",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-recovery-second"
        )
        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [
                [firstDescriptor],
                [firstDescriptor, secondDescriptor],
            ]
        )
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        await observationService.emit(.observationRecoveryRequired)

        await waitUntil {
            let state = await harness.service.currentState()
            return state.snapshot.descriptors.count == 2
        }

        let requestedScopes = await observationService.requestedScopes()
        XCTAssertEqual(requestedScopes, [.all, .all])
    }

    func testObservationRecoveryRequiredIsDeduplicatedWhileRefreshIsInFlight() async throws {
        let firstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.discovery",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-recovery-bounded-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.discovery",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-recovery-bounded-second"
        )
        let thirdDescriptor = makeDescriptor(
            ownerPID: 303,
            bundleID: "com.example.discovery",
            title: "Third Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-recovery-bounded-third"
        )
        let observationService = BlockingScopedDiscoveryObserver(
            allBatches: [
                [firstDescriptor],
                [firstDescriptor, secondDescriptor],
                [firstDescriptor, secondDescriptor, thirdDescriptor],
            ],
            blockGlobalRefreshesStartingAtCall: 2
        )
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        await observationService.emit(.observationRecoveryRequired)

        await waitUntil {
            await observationService.fullCallCount() == 2
        }

        await observationService.emit(.observationRecoveryRequired)
        await observationService.releaseGlobalRefreshes()

        await waitUntil {
            await observationService.fullCallCount() == 3
        }

        try? await Task.sleep(for: .milliseconds(80))
        let fullCallCount = await observationService.fullCallCount()
        XCTAssertEqual(fullCallCount, 3)

        let requestedScopes = await observationService.requestedScopes()
        XCTAssertEqual(requestedScopes, [.all, .all, .all])
    }

    func testPartialRefreshPreservesUnaffectedLayoutAssignments() async throws {
        let firstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.first",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-layout-preserve-first"
        )
        let updatedFirstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.first",
            title: "First Item Updated",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-layout-preserve-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.second",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-layout-preserve-second"
        )
        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [[firstDescriptor, secondDescriptor]],
            scopedBatches: [
                [101]: [[updatedFirstDescriptor]],
            ]
        )
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        await harness.service.assign(.archive, to: secondDescriptor.canonicalID)
        await harness.service.rename(canonicalID: secondDescriptor.canonicalID, to: "Pinned Second")
        await observationService.emit(
            .axStructureChanged(bundleID: firstDescriptor.bundleIdentifier, processIdentifier: 101)
        )

        await waitUntil {
            let state = await harness.service.currentState()
            return state.snapshot.descriptors.contains(where: {
                $0.ownerPID == 101 && $0.title == "First Item Updated"
            })
        }

        let state = await harness.service.currentState()
        let unaffectedDescriptor = try XCTUnwrap(
            state.snapshot.descriptors.first(where: { $0.ownerPID == 202 })
        )
        XCTAssertEqual(unaffectedDescriptor.group, .archive)
        XCTAssertEqual(unaffectedDescriptor.customName, "Pinned Second")
        XCTAssertEqual(
            state.layoutSnapshot.groupsByCanonicalID[secondDescriptor.canonicalID.rawValue],
            .archive
        )
        XCTAssertEqual(
            state.layoutSnapshot.customNamesByCanonicalID[secondDescriptor.canonicalID.rawValue],
            "Pinned Second"
        )
    }

    func testTerminatedAppInvalidationRemovesOnlyAffectedProcessDescriptors() async throws {
        let firstDescriptor = makeDescriptor(
            ownerPID: 101,
            bundleID: "com.example.first",
            title: "First Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-terminated-first"
        )
        let secondDescriptor = makeDescriptor(
            ownerPID: 202,
            bundleID: "com.example.second",
            title: "Second Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-terminated-second"
        )
        let observationService = StreamingScopedDiscoveryObserver(
            allBatches: [[firstDescriptor, secondDescriptor]],
            scopedBatches: [
                [101]: [[]],
            ]
        )
        let harness = try makeHarness(observationService: observationService)

        await harness.service.performSetup()
        await harness.service.refresh(
            .appTerminated(bundleID: firstDescriptor.bundleIdentifier, processIdentifier: 101)
        )

        let state = await harness.service.currentState()
        XCTAssertEqual(state.snapshot.descriptors, [secondDescriptor])
        let requestedScopes = await observationService.requestedScopes()
        XCTAssertEqual(requestedScopes, [.all, .processIdentifiers([101])])
    }

    private func makeHarness(
        observationService: some DiscoveryObserving
    ) throws -> DiscoveryServiceHarness {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoveryServiceTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let paths = ThawPersistencePaths(rootDirectory: tempDirectory)
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
        let identityRegistry = IdentityRegistry(paths: paths)
        let layoutService = LayoutService(paths: paths)
        let service = DiscoveryService(
            displayService: displayService,
            identityRegistry: identityRegistry,
            workspaceEventSource: workspaceEventSource,
            observationService: observationService,
            layoutService: layoutService
        )

        return DiscoveryServiceHarness(
            rootDirectory: tempDirectory,
            service: service
        )
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

    private func waitUntil(
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

        XCTFail("Timed out waiting for discovery service condition")
    }
}

private final class DiscoveryServiceHarness {
    let rootDirectory: URL
    let service: DiscoveryService

    init(
        rootDirectory: URL,
        service: DiscoveryService
    ) {
        self.rootDirectory = rootDirectory
        self.service = service
    }

    deinit {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private actor StreamingScopedDiscoveryObserver: DiscoveryObserving {
    enum Scope: Equatable {
        case all
        case processIdentifiers(Set<pid_t>)
    }

    private var remainingBatches: [[MenuExtraDescriptor]]
    private var lastBatch = [MenuExtraDescriptor]()
    private var observedSnapshots = [DisplayObservationSnapshot]()
    private var remainingScopedBatches: [Set<pid_t>: [[MenuExtraDescriptor]]]
    private var lastScopedBatches = [Set<pid_t>: [MenuExtraDescriptor]]()
    private var requestedScopeHistory = [Scope]()
    nonisolated let invalidationUpdates: AsyncStream<DiscoveryInvalidation>
    private let invalidationContinuation: AsyncStream<DiscoveryInvalidation>.Continuation

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

    func discoverDescriptors(displaySnapshot: DisplayObservationSnapshot) async -> [MenuExtraDescriptor] {
        observedSnapshots.append(displaySnapshot)
        requestedScopeHistory.append(.all)

        if !remainingBatches.isEmpty {
            lastBatch = remainingBatches.removeFirst()
        }

        return lastBatch
    }

    func discoverDescriptors(
        displaySnapshot: DisplayObservationSnapshot,
        processIdentifiers: Set<pid_t>
    ) async -> [MenuExtraDescriptor] {
        observedSnapshots.append(displaySnapshot)
        requestedScopeHistory.append(.processIdentifiers(processIdentifiers))

        if var batches = remainingScopedBatches[processIdentifiers], !batches.isEmpty {
            let nextBatch = batches.removeFirst()
            remainingScopedBatches[processIdentifiers] = batches
            lastScopedBatches[processIdentifiers] = nextBatch
            return nextBatch
        }

        return lastScopedBatches[processIdentifiers] ?? []
    }

    func callCount() -> Int {
        observedSnapshots.count
    }

    func requestedScopes() -> [Scope] {
        requestedScopeHistory
    }

    func emit(_ invalidation: DiscoveryInvalidation) {
        invalidationContinuation.yield(invalidation)
    }
}

private actor BlockingScopedDiscoveryObserver: DiscoveryObserving {
    enum Scope: Equatable {
        case all
        case processIdentifiers(Set<pid_t>)
    }

    private var remainingBatches: [[MenuExtraDescriptor]]
    private var lastBatch = [MenuExtraDescriptor]()
    private var requestedScopeHistory = [Scope]()
    private let blockGlobalRefreshesStartingAtCall: Int?
    private var globalRefreshGateOpen = false
    private var globalRefreshWaitContinuation: CheckedContinuation<Void, Never>?
    nonisolated let invalidationUpdates: AsyncStream<DiscoveryInvalidation>
    private let invalidationContinuation: AsyncStream<DiscoveryInvalidation>.Continuation
    private var fullCallCountValue = 0

    init(
        allBatches: [[MenuExtraDescriptor]],
        blockGlobalRefreshesStartingAtCall: Int?
    ) {
        var capturedContinuation: AsyncStream<DiscoveryInvalidation>.Continuation?
        invalidationUpdates = AsyncStream(bufferingPolicy: .bufferingNewest(16)) {
            capturedContinuation = $0
        }
        guard let capturedContinuation else {
            preconditionFailure("BlockingScopedDiscoveryObserver invalidation stream was not initialized")
        }
        invalidationContinuation = capturedContinuation
        remainingBatches = allBatches
        self.blockGlobalRefreshesStartingAtCall = blockGlobalRefreshesStartingAtCall
    }

    func discoverDescriptors(displaySnapshot _: DisplayObservationSnapshot) async -> [MenuExtraDescriptor] {
        await performFullDiscover()
    }

    func discoverDescriptors(
        displaySnapshot _: DisplayObservationSnapshot,
        processIdentifiers _: Set<pid_t>
    ) async -> [MenuExtraDescriptor] {
        await performFullDiscover()
    }

    func fullCallCount() -> Int {
        fullCallCountValue
    }

    func requestedScopes() -> [Scope] {
        requestedScopeHistory
    }

    func emit(_ invalidation: DiscoveryInvalidation) {
        invalidationContinuation.yield(invalidation)
    }

    func releaseGlobalRefreshes() {
        globalRefreshGateOpen = true
        globalRefreshWaitContinuation?.resume()
        globalRefreshWaitContinuation = nil
    }

    private func performFullDiscover() async -> [MenuExtraDescriptor] {
        requestedScopeHistory.append(.all)
        fullCallCountValue += 1

        if
            let blockGlobalRefreshesStartingAtCall,
            fullCallCountValue >= blockGlobalRefreshesStartingAtCall,
            !globalRefreshGateOpen
        {
            await waitForGlobalRefreshRelease()
        }

        if !remainingBatches.isEmpty {
            lastBatch = remainingBatches.removeFirst()
        }

        return lastBatch
    }

    private func waitForGlobalRefreshRelease() async {
        await withCheckedContinuation { continuation in
            globalRefreshWaitContinuation = continuation
        }
    }
}
