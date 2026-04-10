//
//  RuntimeObservabilityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import XCTest
@testable import Thaw

final class RuntimeObservabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RuntimeMetrics.shared.reset()
    }

    override func tearDown() {
        RuntimeMetrics.shared.reset()
        super.tearDown()
    }

    func testDiagnosticCategoriesMatchPlanExactly() {
        XCTAssertEqual(
            DiagLogCategory.allCases.map(\.rawValue),
            [
                "startup",
                "permission",
                "discovery",
                "identity",
                "activation",
                "layout",
                "profiles",
                "focus",
                "panel",
            ]
        )
    }

    func testRuntimeMetricsAccumulateTypedCountsAndDurations() {
        let metrics = RuntimeMetrics()

        metrics.recordDiscoveryDuration(0.25)
        metrics.recordDiscoveryDuration(0.75)
        metrics.recordActivationDuration(1.5)
        metrics.incrementIdentityChurn(by: 2)
        metrics.incrementInvalidationCount(cause: .workspace)
        metrics.incrementInvalidationCount(cause: .workspace)
        metrics.incrementLayoutMutationCount()
        metrics.incrementConfidencePromotionCount(by: 3)
        metrics.incrementConfidenceDemotionCount()
        metrics.incrementAmbiguousCandidateCount(by: 4)

        let snapshot = metrics.snapshot()

        XCTAssertEqual(snapshot.discoveryDurations.sampleCount, 2)
        XCTAssertEqual(snapshot.discoveryDurations.totalSeconds, 1.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.discoveryDurations.minimumSeconds, 0.25)
        XCTAssertEqual(snapshot.discoveryDurations.maximumSeconds, 0.75)
        XCTAssertEqual(try XCTUnwrap(snapshot.discoveryDurations.averageSeconds), 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.activationDurations.sampleCount, 1)
        XCTAssertEqual(snapshot.activationDurations.totalSeconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.identityChurnCount, 2)
        XCTAssertEqual(snapshot.invalidationCountsByCause[.workspace], 2)
        XCTAssertEqual(snapshot.layoutMutationCount, 1)
        XCTAssertEqual(snapshot.confidencePromotionCount, 3)
        XCTAssertEqual(snapshot.confidenceDemotionCount, 1)
        XCTAssertEqual(snapshot.ambiguousCandidateCount, 4)
    }

    func testResetClearsSnapshot() {
        let metrics = RuntimeMetrics()

        metrics.incrementIdentityChurn()
        metrics.incrementInvalidationCount(cause: .layout)
        metrics.reset()

        XCTAssertEqual(metrics.snapshot(), .empty)
    }

    func testDiscoveryInvalidationsMapToTypedMetricCauses() {
        XCTAssertEqual(DiscoveryInvalidation.startup.runtimeMetricCause, .startup)
        XCTAssertEqual(DiscoveryInvalidation.permissionChanged.runtimeMetricCause, .permission)
        XCTAssertEqual(
            DiscoveryInvalidation.displayConfigurationChanged.runtimeMetricCause,
            .display
        )
        XCTAssertEqual(
            DiscoveryInvalidation.observationRecoveryRequired.runtimeMetricCause,
            .discovery
        )
        XCTAssertEqual(
            DiscoveryInvalidation.panelPresented(displayUUID: "display-1").runtimeMetricCause,
            .panel
        )
        XCTAssertEqual(DiscoveryInvalidation.profileApplied.runtimeMetricCause, .profiles)
        XCTAssertEqual(
            DiscoveryInvalidation.activationFollowUp(
                canonicalID: MenuExtraCanonicalID(rawValue: "opaque-id"),
                surface: .panel,
                intent: .primary
            ).runtimeMetricCause,
            .activation
        )
    }

    func testActivationServiceRecordsActivationDuration() async {
        let baseline = RuntimeMetrics.shared.snapshot()
        let descriptor = await MainActor.run {
            makeDescriptor(id: "com.example.runtime.activation::stable::AXMenuBarItem")
        }
        let executor = await MainActor.run {
            RuntimeObservabilityActivationExecutor(outcome: .openedUI)
        }
        let displayService = await MainActor.run {
            DisplayService(workspaceEventSource: WorkspaceEventSource())
        }
        let service = ActivationService(
            executor: executor,
            contextProvider: RuntimeObservabilityActivationContext(descriptor: descriptor),
            displayService: displayService
        )

        _ = await service.activate(
            ActivationCommand(
                canonicalID: descriptor.canonicalID,
                surface: .quickAccess,
                intent: .primary
            )
        )

        let snapshot = RuntimeMetrics.shared.snapshot()
        XCTAssertGreaterThanOrEqual(
            snapshot.activationDurations.sampleCount,
            baseline.activationDurations.sampleCount + 1
        )
        XCTAssertGreaterThan(
            snapshot.activationDurations.totalSeconds,
            baseline.activationDurations.totalSeconds
        )
    }

    func testLayoutServiceRecordsLayoutMutationMetrics() throws {
        let baseline = RuntimeMetrics.shared.snapshot()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeObservabilityLayout.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let service = LayoutService(paths: ThawPersistencePaths(rootDirectory: tempDirectory))
        service.apply(
            ProfileLayoutV3(
                defaultLayout: LayoutStateV3(
                    groupsByCanonicalID: ["alpha": .archive],
                    orderedCanonicalIDsByGroup: [.archive: ["alpha"]],
                    aliasesByCanonicalID: ["alpha": "Alpha Alias"]
                )
            )
        )

        let snapshot = RuntimeMetrics.shared.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.layoutMutationCount, baseline.layoutMutationCount + 1)
    }

    func testIdentityRegistryRecordsAmbiguityPromotionAndDemotionMetrics() async throws {
        let baseline = RuntimeMetrics.shared.snapshot()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeObservabilityIdentity.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let registry = IdentityRegistry(paths: ThawPersistencePaths(rootDirectory: tempDirectory))
        _ = await registry.resolve([
            makeCandidate(
                bundleID: "com.example.ambiguous",
                title: "Ambiguous",
                axIdentifier: nil,
                slotIndex: 0,
                displayUUID: "display-1"
            ),
            makeCandidate(
                bundleID: "com.example.ambiguous",
                title: "Ambiguous",
                axIdentifier: nil,
                slotIndex: 1,
                displayUUID: "display-1"
            ),
        ])

        let stableCandidate = makeCandidate(
            bundleID: "com.example.promote",
            title: "Promote",
            axIdentifier: nil,
            slotIndex: 0,
            displayUUID: "display-1"
        )
        _ = await registry.resolve([stableCandidate])
        _ = await registry.resolve([stableCandidate])
        _ = await registry.resolve([stableCandidate])
        _ = await registry.resolve([
            makeCandidate(
                bundleID: "com.example.promote",
                title: "Promote",
                axIdentifier: nil,
                slotIndex: 1,
                displayUUID: "display-2"
            ),
        ])

        let snapshot = RuntimeMetrics.shared.snapshot()
        XCTAssertGreaterThanOrEqual(
            snapshot.ambiguousCandidateCount,
            baseline.ambiguousCandidateCount + 2
        )
        XCTAssertGreaterThanOrEqual(
            snapshot.confidencePromotionCount,
            baseline.confidencePromotionCount + 1
        )
        XCTAssertGreaterThanOrEqual(
            snapshot.confidenceDemotionCount,
            baseline.confidenceDemotionCount + 1
        )
    }

    @MainActor
    private func makeDescriptor(id: String) -> MenuExtraDescriptor {
        let components = id.components(separatedBy: "::")
        let identity = MenuExtraIdentity(
            bundleID: components[0],
            stableKey: components[1],
            normalizedTitle: "runtime",
            role: components[2]
        )

        return MenuExtraDescriptor(
            canonicalID: MenuExtraCanonicalID(rawValue: "runtime-\(components[0])"),
            identity: identity,
            ownerPID: 42,
            bundleIdentifier: identity.bundleID,
            bundleURL: nil,
            applicationName: identity.bundleID,
            title: "Runtime",
            rawRole: identity.role,
            frame: nil,
            displayID: nil,
            displayUUID: nil,
            capability: .axPress,
            group: .pinned,
            customName: nil
        )
    }

    private func makeCandidate(
        bundleID: String,
        title: String,
        axIdentifier: String?,
        slotIndex: Int,
        displayUUID: String
    ) -> DiscoveredMenuExtraCandidate {
        DiscoveredMenuExtraCandidate(
            ownerPID: 42,
            bundleIdentifier: bundleID,
            bundleURL: nil,
            applicationName: bundleID,
            title: title,
            normalizedTitle: MenuExtraIdentity.normalizedTitle(title),
            rawRole: "AXMenuBarItem",
            axIdentifier: axIdentifier,
            slotIndex: slotIndex,
            slotSignature: "\(displayUUID):\(slotIndex)",
            frame: CGRect(x: CGFloat(slotIndex * 24), y: 0, width: 18, height: 18),
            displayID: nil,
            displayUUID: displayUUID,
            capability: .axPress
        )
    }
}

private actor RuntimeObservabilityActivationContext: ActivationContextProviding {
    private let descriptorValue: MenuExtraDescriptor

    init(descriptor: MenuExtraDescriptor) {
        descriptorValue = descriptor
    }

    func descriptor(for canonicalID: MenuExtraCanonicalID) async -> MenuExtraDescriptor? {
        descriptorValue.canonicalID == canonicalID ? descriptorValue : nil
    }

    func recordThawInitiatedActivation() async {}

    func refresh(invalidation _: DiscoveryInvalidation) async {}
}

@MainActor
private final class RuntimeObservabilityActivationExecutor: ActivationExecuting {
    private let outcome: ActivationOutcome

    init(outcome: ActivationOutcome) {
        self.outcome = outcome
    }

    func execute(
        command _: ActivationCommand,
        descriptor _: MenuExtraDescriptor,
        displayService _: DisplayService
    ) async -> ActivationOutcome {
        try? await Task.sleep(for: .milliseconds(10))
        return outcome
    }
}
