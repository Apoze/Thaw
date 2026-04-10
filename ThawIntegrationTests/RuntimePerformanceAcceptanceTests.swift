//
//  RuntimePerformanceAcceptanceTests.swift
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
final class RuntimePerformanceAcceptanceTests: XCTestCase {
    private enum Threshold {
        static let warmPanelOpenP95Milliseconds = 120.0
        static let incrementalDiscoveryP95Milliseconds = 100.0
        static let interactiveActivationP95Milliseconds = 300.0
    }

    func testServiceLevelP95BenchmarksStayUnderPlanThresholds() async throws {
        let report = try await makeReport()
        let reportData = try JSONEncoder.performanceAcceptance.encode(report)
        let reportString = String(decoding: reportData, as: UTF8.self)

        print(reportString)
        let attachment = XCTAttachment(string: reportString)
        attachment.name = "runtime-performance-acceptance-report"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertLessThanOrEqual(
            report.warmPanelOpen.millisecondsP95,
            Threshold.warmPanelOpenP95Milliseconds,
            "Warm panel open p95 exceeded plan threshold"
        )
        XCTAssertLessThanOrEqual(
            report.incrementalDiscovery.millisecondsP95,
            Threshold.incrementalDiscoveryP95Milliseconds,
            "Incremental discovery p95 exceeded plan threshold"
        )
        XCTAssertLessThanOrEqual(
            report.interactiveActivation.millisecondsP95,
            Threshold.interactiveActivationP95Milliseconds,
            "Interactive activation p95 exceeded plan threshold"
        )
    }

    private func makeReport() async throws -> RuntimePerformanceAcceptanceReport {
        let warmPanelOpen = try await benchmarkWarmPanelOpen()
        let incrementalDiscovery = try await benchmarkIncrementalDiscovery()
        let interactiveActivation = try await benchmarkInteractiveActivation()

        return RuntimePerformanceAcceptanceReport(
            version: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            methodology: "Synthetic service-level benchmark run from ThawIntegrationTests on the local macOS host. This report measures runtime overhead for the active V3 paths; it is not a substitute for the live manual matrix.",
            warmPanelOpen: warmPanelOpen,
            incrementalDiscovery: incrementalDiscovery,
            interactiveActivation: interactiveActivation
        )
    }

    private func benchmarkWarmPanelOpen() async throws -> RuntimePerformanceMetric {
        guard let screen = NSScreen.main else {
            throw BenchmarkError.missingMainScreen
        }

        let chrome = BenchmarkPanelChromeController()
        let discovery = BenchmarkPanelDiscoverySession()
        let display = BenchmarkPanelDisplayService(preferredScreen: screen)
        let settings = BenchmarkPanelDisplaySettings()
        let service = PanelService()
        service.performSetup(with: .init(
            menuChromeController: chrome,
            discoverySession: discovery,
            displayService: display,
            displaySettings: settings
        ))

        let samples = try await benchmarkSamples {
            let baseline = await chrome.shownIceBarCallCount
            let start = ContinuousClock.now
            await service.show(group: .hidden, triggeredByHotkey: false)
            try await self.waitUntil {
                await chrome.shownIceBarCallCount > baseline
            }
            return self.milliseconds(since: start)
        }

        return RuntimePerformanceMetric(
            name: "warmPanelOpen",
            iterations: samples.count,
            millisecondsP50: percentile(0.50, from: samples),
            millisecondsP95: percentile(0.95, from: samples),
            maximumMilliseconds: samples.max() ?? 0
        )
    }

    private func benchmarkIncrementalDiscovery() async throws -> RuntimePerformanceMetric {
        let descriptor = makeDescriptor(
            ownerPID: 404,
            bundleID: "com.example.discovery-benchmark",
            title: "Discovery Benchmark",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-benchmark"
        )
        let observationService = BenchmarkScopedDiscoveryObserver(
            initialBatch: [descriptor],
            scopedBatch: [descriptor]
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimePerformanceAcceptance.Discovery.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

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
        let identityRegistry = IdentityRegistry(paths: ThawPersistencePaths(rootDirectory: tempDirectory))
        let layoutService = LayoutService(paths: ThawPersistencePaths(rootDirectory: tempDirectory))
        let service = DiscoveryService(
            displayService: displayService,
            identityRegistry: identityRegistry,
            workspaceEventSource: workspaceEventSource,
            observationService: observationService,
            layoutService: layoutService
        )
        await service.performSetup()

        let samples = try await benchmarkSamples {
            let start = ContinuousClock.now
            await service.refresh(
                invalidation: .axStructureChanged(
                    bundleID: descriptor.bundleIdentifier,
                    processIdentifier: descriptor.ownerPID
                )
            )
            return self.milliseconds(since: start)
        }

        let requestedScopes = await observationService.requestedScopes()
        XCTAssertTrue(
            requestedScopes.contains(.processIdentifiers([descriptor.ownerPID])),
            "Benchmark must exercise the incremental per-process discovery path"
        )

        return RuntimePerformanceMetric(
            name: "incrementalDiscovery",
            iterations: samples.count,
            millisecondsP50: percentile(0.50, from: samples),
            millisecondsP95: percentile(0.95, from: samples),
            maximumMilliseconds: samples.max() ?? 0
        )
    }

    private func benchmarkInteractiveActivation() async throws -> RuntimePerformanceMetric {
        let descriptor = makeDescriptor(
            ownerPID: 505,
            bundleID: "com.example.activation-benchmark",
            title: "Activation Benchmark",
            role: "AXMenuBarItem",
            stableKeyBasis: "activation-benchmark"
        )
        let executor = BenchmarkActivationExecutor(outcome: .openedUI)
        let displayService = DisplayService(workspaceEventSource: WorkspaceEventSource())
        let service = ActivationService(
            executor: executor,
            contextProvider: BenchmarkActivationContextProvider(descriptor: descriptor),
            displayService: displayService
        )
        let command = ActivationCommand(
            canonicalID: descriptor.canonicalID,
            surface: .panel,
            intent: .primary
        )

        let samples = try await benchmarkSamples {
            let start = ContinuousClock.now
            _ = await service.activate(command)
            return self.milliseconds(since: start)
        }

        return RuntimePerformanceMetric(
            name: "interactiveActivation",
            iterations: samples.count,
            millisecondsP50: percentile(0.50, from: samples),
            millisecondsP95: percentile(0.95, from: samples),
            maximumMilliseconds: samples.max() ?? 0
        )
    }

    private func benchmarkSamples(
        warmupIterations: Int = 5,
        measuredIterations: Int = 40,
        operation: @escaping @MainActor @Sendable () async throws -> Double
    ) async throws -> [Double] {
        for _ in 0 ..< warmupIterations {
            _ = try await operation()
        }

        var samples = [Double]()
        samples.reserveCapacity(measuredIterations)
        for _ in 0 ..< measuredIterations {
            samples.append(try await operation())
        }
        return samples
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(5),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw BenchmarkError.timeout
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        start.duration(to: .now).timeInterval * 1000
    }

    private func percentile(_ fraction: Double, from samples: [Double]) -> Double {
        guard !samples.isEmpty else {
            return 0
        }

        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded(.up))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    private func makeDescriptor(
        ownerPID: pid_t,
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
            displayUUID: "display-benchmark",
            capability: .axPress,
            group: .hidden,
            customName: nil
        )
    }
}

private enum BenchmarkError: Error {
    case missingMainScreen
    case timeout
}

private struct RuntimePerformanceAcceptanceReport: Encodable {
    let version: Int
    let generatedAt: String
    let methodology: String
    let warmPanelOpen: RuntimePerformanceMetric
    let incrementalDiscovery: RuntimePerformanceMetric
    let interactiveActivation: RuntimePerformanceMetric
}

private struct RuntimePerformanceMetric: Encodable {
    let name: String
    let iterations: Int
    let millisecondsP50: Double
    let millisecondsP95: Double
    let maximumMilliseconds: Double
}

private extension JSONEncoder {
    static var performanceAcceptance: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

@MainActor
private final class BenchmarkPanelChromeController: PanelChromeControlling {
    private(set) var shownIceBarCallCount = 0

    func isIceBarVisible(for _: VirtualGroup) -> Bool {
        false
    }

    func closeIceBar() {}

    func showIceBar(group _: VirtualGroup, on _: NSScreen, triggeredByHotkey _: Bool) {
        shownIceBarCallCount += 1
    }

    var isSearchPanelVisible: Bool {
        false
    }

    func closeSearchPanel() {}

    func showSearchPanel(on _: NSScreen?) {}

    func closeIceBarIfPresentationMatches(_: UUID?) {}

    func closeSearchPanelIfPresentationMatches(_: UUID?) {}
}

@MainActor
private final class BenchmarkPanelDiscoverySession: PanelDiscoveryPreparing {
    func refresh(_: DiscoveryInvalidation) async {}
}

@MainActor
private final class BenchmarkPanelDisplayService: PanelDisplayProviding {
    let activeMenuBarDisplayID: CGDirectDisplayID? = nil
    private let preferredScreen: NSScreen

    init(preferredScreen: NSScreen) {
        self.preferredScreen = preferredScreen
    }

    func preferredPresentationScreen() -> NSScreen? {
        preferredScreen
    }
}

@MainActor
private final class BenchmarkPanelDisplaySettings: PanelDisplaySettingsReading {
    func useIceBar(for _: CGDirectDisplayID) -> Bool {
        false
    }
}

private actor BenchmarkScopedDiscoveryObserver: DiscoveryObserving {
    enum Scope: Equatable {
        case all
        case processIdentifiers(Set<pid_t>)
    }

    private let initialBatch: [MenuExtraDescriptor]
    private let scopedBatch: [MenuExtraDescriptor]
    private var scopeHistory = [Scope]()

    init(
        initialBatch: [MenuExtraDescriptor],
        scopedBatch: [MenuExtraDescriptor]
    ) {
        self.initialBatch = initialBatch
        self.scopedBatch = scopedBatch
    }

    func discoverDescriptors(displaySnapshot _: DisplayObservationSnapshot) async -> [MenuExtraDescriptor] {
        scopeHistory.append(.all)
        return initialBatch
    }

    func discoverDescriptors(
        displaySnapshot _: DisplayObservationSnapshot,
        processIdentifiers: Set<pid_t>
    ) async -> [MenuExtraDescriptor] {
        scopeHistory.append(.processIdentifiers(processIdentifiers))
        return scopedBatch
    }

    func requestedScopes() -> [Scope] {
        scopeHistory
    }
}

@MainActor
private final class BenchmarkActivationExecutor: ActivationExecuting {
    private let outcome: ActivationOutcome

    init(outcome: ActivationOutcome) {
        self.outcome = outcome
    }

    func execute(
        command _: ActivationCommand,
        descriptor _: MenuExtraDescriptor,
        displayService _: DisplayService
    ) async -> ActivationOutcome {
        outcome
    }
}

private actor BenchmarkActivationContextProvider: ActivationContextProviding {
    private let descriptor: MenuExtraDescriptor

    init(descriptor: MenuExtraDescriptor) {
        self.descriptor = descriptor
    }

    func descriptor(for canonicalID: MenuExtraCanonicalID) async -> MenuExtraDescriptor? {
        descriptor.canonicalID == canonicalID ? descriptor : nil
    }

    func recordThawInitiatedActivation() async {}

    func refresh(invalidation _: DiscoveryInvalidation) async {}
}
