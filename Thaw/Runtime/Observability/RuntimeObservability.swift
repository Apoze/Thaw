//
//  RuntimeObservability.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import OSLog

/// Typed diagnostic categories for the plan-defined runtime surfaces.
enum DiagLogCategory: String, CaseIterable, Sendable {
    case startup
    case permission
    case discovery
    case identity
    case activation
    case layout
    case profiles
    case focus
    case panel
}

/// Typed causes used when counting invalidations in runtime metrics.
enum RuntimeInvalidationCause: String, Codable, CaseIterable, Sendable {
    case startup
    case permission
    case workspace
    case display
    case discovery
    case activation
    case layout
    case profiles
    case focus
    case panel
    case unknown
}

/// A cumulative duration summary for runtime instrumentation.
struct RuntimeDurationSummary: Codable, Hashable, Sendable {
    var sampleCount: Int
    var totalSeconds: TimeInterval
    var minimumSeconds: TimeInterval?
    var maximumSeconds: TimeInterval?

    static let empty = RuntimeDurationSummary(
        sampleCount: 0,
        totalSeconds: 0,
        minimumSeconds: nil,
        maximumSeconds: nil
    )

    var averageSeconds: TimeInterval? {
        guard sampleCount > 0 else {
            return nil
        }
        return totalSeconds / Double(sampleCount)
    }

    mutating func record(seconds: TimeInterval) {
        let clampedSeconds = max(seconds, 0)
        sampleCount += 1
        totalSeconds += clampedSeconds
        minimumSeconds = min(minimumSeconds ?? clampedSeconds, clampedSeconds)
        maximumSeconds = max(maximumSeconds ?? clampedSeconds, clampedSeconds)
    }
}

/// The snapshot persisted in memory for runtime observability.
struct RuntimeObservabilitySnapshot: Codable, Hashable, Sendable {
    var discoveryDurations: RuntimeDurationSummary
    var activationDurations: RuntimeDurationSummary
    var identityChurnCount: Int
    var invalidationCountsByCause: [RuntimeInvalidationCause: Int]
    var layoutMutationCount: Int
    var confidencePromotionCount: Int
    var confidenceDemotionCount: Int
    var ambiguousCandidateCount: Int

    static let empty = RuntimeObservabilitySnapshot(
        discoveryDurations: .empty,
        activationDurations: .empty,
        identityChurnCount: 0,
        invalidationCountsByCause: [:],
        layoutMutationCount: 0,
        confidencePromotionCount: 0,
        confidenceDemotionCount: 0,
        ambiguousCandidateCount: 0
    )
}

/// A typed event that updates the runtime observability snapshot.
enum RuntimeMetricEvent: Sendable {
    case discoveryDuration(TimeInterval)
    case activationDuration(TimeInterval)
    case identityChurn(Int)
    case invalidation(cause: RuntimeInvalidationCause, count: Int)
    case layoutMutation(Int)
    case confidencePromotion(Int)
    case confidenceDemotion(Int)
    case ambiguousCandidate(Int)
}

/// A small, synchronous metrics store for runtime instrumentation.
final class RuntimeMetrics: @unchecked Sendable {
    static let shared = RuntimeMetrics()

    private let state = OSAllocatedUnfairLock(initialState: RuntimeObservabilitySnapshot.empty)

    init() {}

    func snapshot() -> RuntimeObservabilitySnapshot {
        state.withLock { $0 }
    }

    func reset() {
        state.withLock { current in
            current = RuntimeObservabilitySnapshot.empty
        }
    }

    func record(_ event: RuntimeMetricEvent) {
        state.withLock { snapshot in
            switch event {
            case .discoveryDuration(let seconds):
                snapshot.discoveryDurations.record(seconds: seconds)
            case .activationDuration(let seconds):
                snapshot.activationDurations.record(seconds: seconds)
            case .identityChurn(let count):
                snapshot.identityChurnCount += max(count, 0)
            case .invalidation(let cause, let count):
                guard count > 0 else { return }
                snapshot.invalidationCountsByCause[cause, default: 0] += count
            case .layoutMutation(let count):
                snapshot.layoutMutationCount += max(count, 0)
            case .confidencePromotion(let count):
                snapshot.confidencePromotionCount += max(count, 0)
            case .confidenceDemotion(let count):
                snapshot.confidenceDemotionCount += max(count, 0)
            case .ambiguousCandidate(let count):
                snapshot.ambiguousCandidateCount += max(count, 0)
            }
        }
    }

    func recordDiscoveryDuration(_ seconds: TimeInterval) {
        record(.discoveryDuration(seconds))
    }

    func recordActivationDuration(_ seconds: TimeInterval) {
        record(.activationDuration(seconds))
    }

    func incrementIdentityChurn(by count: Int = 1) {
        record(.identityChurn(count))
    }

    func incrementInvalidationCount(cause: RuntimeInvalidationCause, by count: Int = 1) {
        record(.invalidation(cause: cause, count: count))
    }

    func incrementLayoutMutationCount(by count: Int = 1) {
        record(.layoutMutation(count))
    }

    func incrementConfidencePromotionCount(by count: Int = 1) {
        record(.confidencePromotion(count))
    }

    func incrementConfidenceDemotionCount(by count: Int = 1) {
        record(.confidenceDemotion(count))
    }

    func incrementAmbiguousCandidateCount(by count: Int = 1) {
        record(.ambiguousCandidate(count))
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds + attoseconds
    }
}

extension DiscoveryInvalidation {
    var runtimeMetricCause: RuntimeInvalidationCause {
        switch self {
        case .startup:
            .startup
        case .permissionChanged:
            .permission
        case .appLaunched,
             .appTerminated,
             .appActivated,
             .workspaceActivationSettled:
            .workspace
        case .displayConfigurationChanged:
            .display
        case .axStructureChanged,
             .observationRecoveryRequired:
            .discovery
        case .layoutEditorPresented,
             .layoutReset:
            .layout
        case .panelPreparation,
             .panelPresented:
            .panel
        case .profileApplied:
            .profiles
        case .activationFollowUp:
            .activation
        case .consistencyFollowUp:
            .discovery
        }
    }
}
