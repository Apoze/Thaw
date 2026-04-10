//
//  IdentityCalibrationReplaySupport.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import Thaw

enum IdentityCalibrationReplaySupport {
    static func loadCorpus(decoder: JSONDecoder = JSONDecoder()) throws -> IdentityCalibrationCorpus {
        try decoder.decode(
            IdentityCalibrationCorpus.self,
            from: Data(contentsOf: resourceURL(named: "corpus-v1", withExtension: "json"))
        )
    }

    static func loadReport(decoder: JSONDecoder = JSONDecoder()) throws -> IdentityCalibrationReport {
        try decoder.decode(
            IdentityCalibrationReport.self,
            from: Data(contentsOf: resourceURL(named: "identity-calibration-report-v1", withExtension: "json"))
        )
    }

    static func replay(
        corpus: IdentityCalibrationCorpus,
        paths: ThawPersistencePaths
    ) async throws -> IdentityCalibrationReplayResult {
        let legacyResolver = FrozenLegacyIdentityResolver()
        var scenarioResults: [IdentityCalibrationScenarioReplayResult] = []

        for scenario in corpus.scenarios {
            let scenarioPaths = paths.rootDirectory
                .appendingPathComponent(scenario.id, isDirectory: true)
            try FileManager.default.createDirectory(at: scenarioPaths, withIntermediateDirectories: true)
            let persistencePaths = ThawPersistencePaths(rootDirectory: scenarioPaths)
            var registry = IdentityRegistry(paths: persistencePaths, mode: .shadow)
            var legacyMetrics = IdentityCalibrationMetricsAccumulator()
            var shadowMetrics = IdentityCalibrationMetricsAccumulator()
            var cumulativeObservationCount = 0
            var identityParityMismatchCount = 0
            var confidenceParityMismatchCount = 0

            for frame in scenario.frames {
                if frame.reloadRegistryBeforeFrame {
                    registry = IdentityRegistry(paths: persistencePaths, mode: .shadow)
                }

                let candidates = frame.observations.map(makeCandidate(from:))
                let legacyResolved = legacyResolver.resolve(frame.observations)
                let resolved = await registry.resolve(candidates)
                cumulativeObservationCount += frame.observations.count

                guard resolved.count == frame.observations.count else {
                    throw IdentityCalibrationReplayError.resolvedCountMismatch(
                        expected: frame.observations.count,
                        actual: resolved.count,
                        scenarioID: scenario.id,
                        frameID: frame.id
                    )
                }

                let snapshot = await registry.snapshot()
                guard snapshot.mode == .shadow else {
                    throw IdentityCalibrationReplayError.unexpectedRegistryMode(
                        actual: snapshot.mode,
                        scenarioID: scenario.id,
                        frameID: frame.id
                    )
                }
                guard snapshot.diagnostics.shadowObservationCount == cumulativeObservationCount else {
                    throw IdentityCalibrationReplayError.shadowObservationCountMismatch(
                        expected: cumulativeObservationCount,
                        actual: snapshot.diagnostics.shadowObservationCount,
                        scenarioID: scenario.id,
                        frameID: frame.id
                    )
                }

                for ((observation, legacyCandidate), candidate) in zip(zip(frame.observations, legacyResolved), resolved) {
                    legacyMetrics.record(
                        label: observation.label,
                        identityKey: legacyCandidate.identity.id,
                        confidence: legacyCandidate.confidence
                    )
                    shadowMetrics.record(
                        label: observation.label,
                        identityKey: candidate.canonicalID.rawValue,
                        confidence: candidate.confidence,
                        countsAsFalseAutoBind: candidate.identity.id != legacyCandidate.identity.id
                    )

                    if candidate.identity.id != legacyCandidate.identity.id {
                        identityParityMismatchCount += 1
                    }
                    if candidate.confidence != legacyCandidate.confidence {
                        confidenceParityMismatchCount += 1
                    }
                }
            }

            scenarioResults.append(
                IdentityCalibrationScenarioReplayResult(
                    id: scenario.id,
                    description: scenario.description,
                    legacyReferenceMetrics: legacyMetrics.metrics,
                    shadowMetrics: shadowMetrics.metrics,
                    expectedMetrics: scenario.expectedMetrics,
                    identityParityMismatchCount: identityParityMismatchCount,
                    confidenceParityMismatchCount: confidenceParityMismatchCount
                )
            )
        }

        return IdentityCalibrationReplayResult(
            corpusVersion: corpus.version,
            thresholdSnapshot: .current,
            scenarioResults: scenarioResults,
            acceptanceSummary: makeAcceptanceSummary(
                from: scenarioResults,
                categories: IdentityCalibrationScenarioCategories.fromScenarioIDs(
                    scenarioResults.map(\.id)
                )
            ),
            totalLegacyReferenceMetrics: summedMetrics(from: scenarioResults.map(\.legacyReferenceMetrics)),
            totalShadowMetrics: summedMetrics(from: scenarioResults.map(\.shadowMetrics)),
            totalIdentityParityMismatchCount: scenarioResults.reduce(into: 0) { total, result in
                total += result.identityParityMismatchCount
            },
            totalConfidenceParityMismatchCount: scenarioResults.reduce(into: 0) { total, result in
                total += result.confidenceParityMismatchCount
            }
        )
    }

    static func makeReport(from replayResult: IdentityCalibrationReplayResult) -> IdentityCalibrationReport {
        let scenarioCategories = IdentityCalibrationScenarioCategories.fromScenarioIDs(
            replayResult.scenarioResults.map(\.id)
        )

        return IdentityCalibrationReport(
            version: 1,
            corpusVersion: replayResult.corpusVersion,
            thresholdSnapshot: replayResult.thresholdSnapshot,
            scenarioIDsByCategory: scenarioCategories,
            scenarioMetrics: replayResult.scenarioResults.map {
                IdentityCalibrationScenarioMetrics(
                    id: $0.id,
                    legacyReferenceMetrics: $0.legacyReferenceMetrics,
                    shadowMetrics: $0.shadowMetrics,
                    identityParityMismatchCount: $0.identityParityMismatchCount,
                    confidenceParityMismatchCount: $0.confidenceParityMismatchCount
                )
            },
            acceptanceSummary: replayResult.acceptanceSummary,
            totalLegacyReferenceMetrics: replayResult.totalLegacyReferenceMetrics,
            totalShadowMetrics: replayResult.totalShadowMetrics,
            totalIdentityParityMismatchCount: replayResult.totalIdentityParityMismatchCount,
            totalConfidenceParityMismatchCount: replayResult.totalConfidenceParityMismatchCount,
            signOff: .engineeringApproved()
        )
    }

    private static func resourceURL(named name: String, withExtension fileExtension: String) -> URL {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            preconditionFailure("Missing identity calibration resource \(name).\(fileExtension)")
        }
        return url
    }

    private static let bundle = Bundle(for: IdentityCalibrationReplaySupportBundleToken.self)

    private static func makeCandidate(from observation: IdentityCalibrationObservation) -> DiscoveredMenuExtraCandidate {
        let normalizedTitle = MenuExtraIdentity.normalizedTitle(observation.title)
        return DiscoveredMenuExtraCandidate(
            ownerPID: observation.ownerPID,
            bundleIdentifier: observation.bundleID,
            bundleURL: nil,
            applicationName: observation.bundleID,
            title: observation.title,
            normalizedTitle: normalizedTitle,
            rawRole: observation.role,
            axIdentifier: observation.axIdentifier,
            slotIndex: observation.slotIndex,
            slotSignature: "\(observation.displayUUID ?? "display-unknown"):\(observation.slotIndex)",
            frame: CGRect(x: CGFloat(observation.slotIndex * 24), y: 0, width: 18, height: 18),
            displayID: nil,
            displayUUID: observation.displayUUID,
            capability: .axPress
        )
    }

    private static func summedMetrics(from metrics: [IdentityCalibrationMetrics]) -> IdentityCalibrationMetrics {
        metrics.reduce(into: IdentityCalibrationMetrics()) { total, metric in
            total.identityChurnCount += metric.identityChurnCount
            total.canonicalReassignmentCount += metric.canonicalReassignmentCount
            total.ambiguousObservationCount += metric.ambiguousObservationCount
            total.provisionalPromotionCount += metric.provisionalPromotionCount
            total.falseAutoBindCount += metric.falseAutoBindCount
            total.shadowObservationCount += metric.shadowObservationCount
        }
    }

    private static func makeAcceptanceSummary(
        from scenarioResults: [IdentityCalibrationScenarioReplayResult],
        categories: IdentityCalibrationScenarioCategories
    ) -> IdentityCalibrationAcceptanceSummary {
        let stabilizationScenarioIDs =
            categories.stableSingleExtra +
            categories.sameBundleCollision +
            categories.provisionalPromotion +
            categories.ambiguousIsolation
        let probeScenarioIDs = categories.churnProbe + categories.reassignmentProbe
        let scenarioIDs = Set(scenarioResults.map(\.id))
        let stabilizationScenarioIDSet = Set(stabilizationScenarioIDs)
        let probeScenarioIDSet = Set(probeScenarioIDs)

        precondition(
            stabilizationScenarioIDSet.isDisjoint(with: probeScenarioIDSet),
            "Identity calibration acceptance categories must be disjoint"
        )
        precondition(
            stabilizationScenarioIDSet.union(probeScenarioIDSet) == scenarioIDs,
            "Identity calibration acceptance categories must partition the replay corpus"
        )

        let stabilizationResults = scenarioResults.filter {
            stabilizationScenarioIDs.contains($0.id)
        }
        let probeResults = scenarioResults.filter {
            probeScenarioIDs.contains($0.id)
        }
        let stabilizationLegacyMetrics = summedMetrics(
            from: stabilizationResults.map(\.legacyReferenceMetrics)
        )
        let stabilizationShadowMetrics = summedMetrics(
            from: stabilizationResults.map(\.shadowMetrics)
        )
        let probeLegacyMetrics = summedMetrics(
            from: probeResults.map(\.legacyReferenceMetrics)
        )
        let probeShadowMetrics = summedMetrics(
            from: probeResults.map(\.shadowMetrics)
        )

        func rate(_ numerator: Int, _ denominator: Int) -> Double {
            guard denominator > 0 else {
                return 0
            }
            return Double(numerator) / Double(denominator)
        }

        return IdentityCalibrationAcceptanceSummary(
            stabilizationScenarioIDs: stabilizationScenarioIDs.sorted(),
            probeScenarioIDs: probeScenarioIDs.sorted(),
            stabilizationLegacyReferenceMetrics: stabilizationLegacyMetrics,
            stabilizationShadowMetrics: stabilizationShadowMetrics,
            probeLegacyReferenceMetrics: probeLegacyMetrics,
            probeShadowMetrics: probeShadowMetrics,
            stabilizationLegacyChurnRate: rate(
                stabilizationLegacyMetrics.identityChurnCount,
                stabilizationLegacyMetrics.shadowObservationCount
            ),
            stabilizationShadowChurnRate: rate(
                stabilizationShadowMetrics.identityChurnCount,
                stabilizationShadowMetrics.shadowObservationCount
            ),
            stabilizationShadowFalseAutoBindRate: rate(
                stabilizationShadowMetrics.falseAutoBindCount,
                stabilizationShadowMetrics.shadowObservationCount
            )
        )
    }
}

private final class IdentityCalibrationReplaySupportBundleToken {}

enum IdentityCalibrationReplayError: Error, CustomStringConvertible {
    case resolvedCountMismatch(expected: Int, actual: Int, scenarioID: String, frameID: String)
    case unexpectedRegistryMode(actual: IdentityRegistryMode, scenarioID: String, frameID: String)
    case shadowObservationCountMismatch(expected: Int, actual: Int, scenarioID: String, frameID: String)

    var description: String {
        switch self {
        case let .resolvedCountMismatch(expected, actual, scenarioID, frameID):
            return "Resolved count mismatch for \(scenarioID)/\(frameID): expected \(expected), got \(actual)"
        case let .unexpectedRegistryMode(actual, scenarioID, frameID):
            return "Unexpected registry mode for \(scenarioID)/\(frameID): \(actual)"
        case let .shadowObservationCountMismatch(expected, actual, scenarioID, frameID):
            return "Shadow observation count mismatch for \(scenarioID)/\(frameID): expected \(expected), got \(actual)"
        }
    }
}

struct FrozenLegacyIdentityResolver {
    func resolve(_ observations: [IdentityCalibrationObservation]) -> [FrozenLegacyResolvedCandidate] {
        observations.map { observation in
            FrozenLegacyResolvedCandidate(
                identity: IdentityCalibrationLegacyReference.identity(for: observation),
                confidence: observation.expectedConfidence
            )
        }
    }
}

struct FrozenLegacyResolvedCandidate: Equatable {
    let identity: MenuExtraIdentity
    let confidence: IdentityMatchConfidence
}

private struct IdentityCalibrationMetricsAccumulator {
    private(set) var metrics = IdentityCalibrationMetrics()
    private var identityKeysByLabel = [String: String]()
    private var labelsByIdentityKey = [String: String]()
    private var confidencesByLabel = [String: IdentityMatchConfidence]()

    mutating func record(
        label: String,
        identityKey: String,
        confidence: IdentityMatchConfidence,
        countsAsFalseAutoBind: Bool = false
    ) {
        if let previousIdentityKey = identityKeysByLabel[label],
           previousIdentityKey != identityKey {
            metrics.identityChurnCount += 1
        }
        identityKeysByLabel[label] = identityKey

        if let previousLabel = labelsByIdentityKey[identityKey],
           previousLabel != label {
            metrics.canonicalReassignmentCount += 1
        } else {
            labelsByIdentityKey[identityKey] = label
        }

        if confidence == .ambiguous {
            metrics.ambiguousObservationCount += 1
        }

        if confidencesByLabel[label] == .provisional,
           confidence == .high {
            metrics.provisionalPromotionCount += 1
        }
        confidencesByLabel[label] = confidence

        if countsAsFalseAutoBind {
            metrics.falseAutoBindCount += 1
        }

        metrics.shadowObservationCount += 1
    }
}

struct IdentityCalibrationReplayResult: Equatable {
    let corpusVersion: Int
    let thresholdSnapshot: IdentityCalibrationThresholdSnapshot
    let scenarioResults: [IdentityCalibrationScenarioReplayResult]
    let acceptanceSummary: IdentityCalibrationAcceptanceSummary
    let totalLegacyReferenceMetrics: IdentityCalibrationMetrics
    let totalShadowMetrics: IdentityCalibrationMetrics
    let totalIdentityParityMismatchCount: Int
    let totalConfidenceParityMismatchCount: Int
}

struct IdentityCalibrationScenarioReplayResult: Equatable {
    let id: String
    let description: String
    let legacyReferenceMetrics: IdentityCalibrationMetrics
    let shadowMetrics: IdentityCalibrationMetrics
    let expectedMetrics: IdentityCalibrationMetrics
    let identityParityMismatchCount: Int
    let confidenceParityMismatchCount: Int

    var matches: Bool {
        legacyReferenceMetrics == expectedMetrics &&
            shadowMetrics == expectedMetrics &&
            identityParityMismatchCount == 0 &&
            confidenceParityMismatchCount == 0
    }
}

struct IdentityCalibrationLegacyReference {
    static func identity(for observation: IdentityCalibrationObservation) -> MenuExtraIdentity {
        MenuExtraIdentity.make(
            bundleID: observation.bundleID,
            title: observation.title,
            role: observation.role,
            stableKeyBasis: observation.expectedStableKeyBasis
        )
    }
}

struct IdentityCalibrationCorpus: Decodable {
    let version: Int
    let scenarios: [IdentityCalibrationScenario]
}

struct IdentityCalibrationScenario: Decodable {
    let id: String
    let description: String
    let frames: [IdentityCalibrationFrame]
    let expectedMetrics: IdentityCalibrationMetrics
}

struct IdentityCalibrationFrame: Decodable {
    let id: String
    let reloadRegistryBeforeFrame: Bool
    let observations: [IdentityCalibrationObservation]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        reloadRegistryBeforeFrame = try container.decodeIfPresent(Bool.self, forKey: .reloadRegistryBeforeFrame) ?? false
        observations = try container.decode([IdentityCalibrationObservation].self, forKey: .observations)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case reloadRegistryBeforeFrame
        case observations
    }
}

struct IdentityCalibrationObservation: Decodable {
    let label: String
    let bundleID: String
    let title: String
    let role: String
    let axIdentifier: String?
    let slotIndex: Int
    let ownerPID: pid_t
    let displayUUID: String?
    let expectedStableKeyBasis: String
    let expectedConfidence: IdentityMatchConfidence
}

struct IdentityCalibrationReport: Codable, Equatable {
    let version: Int
    let corpusVersion: Int
    let thresholdSnapshot: IdentityCalibrationThresholdSnapshot
    let scenarioIDsByCategory: IdentityCalibrationScenarioCategories
    let scenarioMetrics: [IdentityCalibrationScenarioMetrics]
    let acceptanceSummary: IdentityCalibrationAcceptanceSummary
    let totalLegacyReferenceMetrics: IdentityCalibrationMetrics
    let totalShadowMetrics: IdentityCalibrationMetrics
    let totalIdentityParityMismatchCount: Int
    let totalConfidenceParityMismatchCount: Int
    let signOff: IdentityCalibrationSignOff
}

struct IdentityCalibrationThresholdSnapshot: Codable, Equatable {
    let autoBindMaximumScore: Int
    let provisionalMaximumScore: Int
    let minimumWinnerMargin: Int
    let displayMismatchPenalty: Int
    let axIdentifierMismatchPenalty: Int
    let slotMismatchPenalty: Int
    let frameDistanceTolerance: Int
    let provisionalPromotionObservationCount: Int

    static var current: IdentityCalibrationThresholdSnapshot {
        IdentityCalibrationThresholdSnapshot(
            autoBindMaximumScore: Int(IdentityRegistryThresholds.autoBindMaximumScore),
            provisionalMaximumScore: Int(IdentityRegistryThresholds.provisionalMaximumScore),
            minimumWinnerMargin: Int(IdentityRegistryThresholds.minimumWinnerMargin),
            displayMismatchPenalty: Int(IdentityRegistryThresholds.displayMismatchPenalty),
            axIdentifierMismatchPenalty: Int(IdentityRegistryThresholds.axIdentifierMismatchPenalty),
            slotMismatchPenalty: Int(IdentityRegistryThresholds.slotMismatchPenalty),
            frameDistanceTolerance: Int(IdentityRegistryThresholds.frameDistanceTolerance),
            provisionalPromotionObservationCount: IdentityRegistryThresholds.provisionalPromotionObservationCount
        )
    }
}

struct IdentityCalibrationScenarioCategories: Codable, Equatable {
    let stableSingleExtra: [String]
    let sameBundleCollision: [String]
    let provisionalPromotion: [String]
    let ambiguousIsolation: [String]
    let churnProbe: [String]
    let reassignmentProbe: [String]

    static func fromScenarioIDs(_ scenarioIDs: [String]) -> IdentityCalibrationScenarioCategories {
        var categories = CategoryAccumulator()
        for scenarioID in scenarioIDs {
            switch scenarioID {
            case "ax-stable-relaunch":
                categories.stableSingleExtra.append(scenarioID)
            case "multiple-extras-same-bundle":
                categories.sameBundleCollision.append(scenarioID)
            case "non-ax-promotion":
                categories.provisionalPromotion.append(scenarioID)
            case "ambiguous-identical-nonax":
                categories.ambiguousIsolation.append(scenarioID)
            case "same-label-churn":
                categories.churnProbe.append(scenarioID)
            case "canonical-reassignment":
                categories.reassignmentProbe.append(scenarioID)
            default:
                continue
            }
        }

        return IdentityCalibrationScenarioCategories(
            stableSingleExtra: categories.stableSingleExtra,
            sameBundleCollision: categories.sameBundleCollision,
            provisionalPromotion: categories.provisionalPromotion,
            ambiguousIsolation: categories.ambiguousIsolation,
            churnProbe: categories.churnProbe,
            reassignmentProbe: categories.reassignmentProbe
        )
    }

    private struct CategoryAccumulator {
        var stableSingleExtra: [String] = []
        var sameBundleCollision: [String] = []
        var provisionalPromotion: [String] = []
        var ambiguousIsolation: [String] = []
        var churnProbe: [String] = []
        var reassignmentProbe: [String] = []
    }
}

struct IdentityCalibrationScenarioMetrics: Codable, Equatable {
    let id: String
    let legacyReferenceMetrics: IdentityCalibrationMetrics
    let shadowMetrics: IdentityCalibrationMetrics
    let identityParityMismatchCount: Int
    let confidenceParityMismatchCount: Int
}

struct IdentityCalibrationAcceptanceSummary: Codable, Equatable {
    let stabilizationScenarioIDs: [String]
    let probeScenarioIDs: [String]
    let stabilizationLegacyReferenceMetrics: IdentityCalibrationMetrics
    let stabilizationShadowMetrics: IdentityCalibrationMetrics
    let probeLegacyReferenceMetrics: IdentityCalibrationMetrics
    let probeShadowMetrics: IdentityCalibrationMetrics
    let stabilizationLegacyChurnRate: Double
    let stabilizationShadowChurnRate: Double
    let stabilizationShadowFalseAutoBindRate: Double
}

struct IdentityCalibrationSignOff: Codable, Equatable {
    let status: IdentityCalibrationSignOffStatus
    let notes: String

    static func engineeringApproved() -> IdentityCalibrationSignOff {
        IdentityCalibrationSignOff(
            status: .approved,
            notes: "Engineering threshold review recorded on 2026-04-09. Final product cutover remains pending."
        )
    }
}

enum IdentityCalibrationSignOffStatus: String, Codable, Equatable {
    case pending
    case approved
}

struct IdentityCalibrationMetrics: Codable, Equatable, CustomStringConvertible {
    var identityChurnCount: Int = 0
    var canonicalReassignmentCount: Int = 0
    var ambiguousObservationCount: Int = 0
    var provisionalPromotionCount: Int = 0
    var falseAutoBindCount: Int = 0
    var shadowObservationCount: Int = 0

    var description: String {
        """
        churn=\(identityChurnCount), \
        reassignments=\(canonicalReassignmentCount), \
        ambiguous=\(ambiguousObservationCount), \
        promotions=\(provisionalPromotionCount), \
        falseAutoBinds=\(falseAutoBindCount), \
        shadowObservations=\(shadowObservationCount)
        """
    }
}
