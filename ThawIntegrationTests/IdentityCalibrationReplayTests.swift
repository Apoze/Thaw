//
//  IdentityCalibrationReplayTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import XCTest
@testable import Thaw

final class IdentityCalibrationReplayTests: XCTestCase {
    private var tempDirectory: URL?
    private var paths: ThawPersistencePaths?

    override func setUp() {
        super.setUp()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IdentityCalibrationReplayTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        self.tempDirectory = tempDirectory
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        paths = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testRedactedCorpusReplayMatchesExpectedIdentityBehavior() async throws {
        guard let paths else {
            XCTFail("Missing replay test dependencies")
            return
        }

        let corpus = try IdentityCalibrationReplaySupport.loadCorpus()
        let replay = try await IdentityCalibrationReplaySupport.replay(corpus: corpus, paths: paths)

        XCTAssertEqual(replay.corpusVersion, corpus.version)
        XCTAssertEqual(replay.thresholdSnapshot, .current)
        XCTAssertEqual(replay.scenarioResults.count, corpus.scenarios.count)
        XCTAssertEqual(replay.totalIdentityParityMismatchCount, 0)
        XCTAssertEqual(replay.totalConfidenceParityMismatchCount, 0)

        for scenario in corpus.scenarios {
            let replayResult = try XCTUnwrap(
                replay.scenarioResults.first(where: { $0.id == scenario.id }),
                "Missing replay result for scenario \(scenario.id)"
            )

            XCTAssertEqual(
                replayResult.legacyReferenceMetrics,
                scenario.expectedMetrics,
                scenarioReport(for: scenario, metricsLabel: "Legacy", metrics: replayResult.legacyReferenceMetrics)
            )
            XCTAssertEqual(
                replayResult.shadowMetrics,
                scenario.expectedMetrics,
                scenarioReport(for: scenario, metricsLabel: "Shadow", metrics: replayResult.shadowMetrics)
            )
            XCTAssertEqual(replayResult.expectedMetrics, scenario.expectedMetrics)
            XCTAssertEqual(replayResult.identityParityMismatchCount, 0)
            XCTAssertEqual(replayResult.confidenceParityMismatchCount, 0)
            XCTAssertTrue(replayResult.matches, "Replay result must match the corpus expectation for \(scenario.id)")
        }

        XCTAssertEqual(
            replay.totalLegacyReferenceMetrics,
            summedMetrics(from: corpus.scenarios.map(\.expectedMetrics))
        )
        XCTAssertEqual(
            replay.totalShadowMetrics,
            summedMetrics(from: corpus.scenarios.map(\.expectedMetrics))
        )
    }

    func testCalibrationReportMatchesReplayAndThresholdSnapshot() async throws {
        guard let paths else {
            XCTFail("Missing replay test dependencies")
            return
        }

        let corpus = try IdentityCalibrationReplaySupport.loadCorpus()
        let replay = try await IdentityCalibrationReplaySupport.replay(corpus: corpus, paths: paths)
        let generatedReport = IdentityCalibrationReplaySupport.makeReport(from: replay)
        let decodedReport = try IdentityCalibrationReplaySupport.loadReport()

        XCTAssertEqual(decodedReport.corpusVersion, corpus.version)
        XCTAssertEqual(generatedReport, decodedReport)
        XCTAssertEqual(decodedReport.thresholdSnapshot, replay.thresholdSnapshot)
        XCTAssertEqual(decodedReport.totalLegacyReferenceMetrics, replay.totalLegacyReferenceMetrics)
        XCTAssertEqual(decodedReport.totalShadowMetrics, replay.totalShadowMetrics)
        XCTAssertEqual(decodedReport.totalIdentityParityMismatchCount, 0)
        XCTAssertEqual(decodedReport.totalConfidenceParityMismatchCount, 0)
        XCTAssertEqual(
            generatedReport.scenarioMetrics.map(\.legacyReferenceMetrics),
            replay.scenarioResults.map(\.legacyReferenceMetrics)
        )
        XCTAssertEqual(
            generatedReport.scenarioMetrics.map(\.shadowMetrics),
            replay.scenarioResults.map(\.shadowMetrics)
        )
        XCTAssertEqual(generatedReport.totalLegacyReferenceMetrics, replay.totalLegacyReferenceMetrics)
        XCTAssertEqual(generatedReport.totalShadowMetrics, replay.totalShadowMetrics)
        XCTAssertEqual(generatedReport.totalIdentityParityMismatchCount, replay.totalIdentityParityMismatchCount)
        XCTAssertEqual(generatedReport.totalConfidenceParityMismatchCount, replay.totalConfidenceParityMismatchCount)
        XCTAssertEqual(
            decodedReport.acceptanceSummary,
            generatedReport.acceptanceSummary
        )
        XCTAssertEqual(
            decodedReport.acceptanceSummary.stabilizationScenarioIDs,
            [
                "ambiguous-identical-nonax",
                "ax-stable-relaunch",
                "multiple-extras-same-bundle",
                "non-ax-promotion",
            ]
        )
        XCTAssertEqual(
            decodedReport.acceptanceSummary.probeScenarioIDs,
            [
                "canonical-reassignment",
                "same-label-churn",
            ]
        )
        XCTAssertTrue(
            Set(decodedReport.acceptanceSummary.stabilizationScenarioIDs)
                .isDisjoint(with: Set(decodedReport.acceptanceSummary.probeScenarioIDs))
        )
        XCTAssertEqual(
            Set(decodedReport.acceptanceSummary.stabilizationScenarioIDs)
                .union(Set(decodedReport.acceptanceSummary.probeScenarioIDs)),
            Set(decodedReport.scenarioMetrics.map(\.id))
        )
        XCTAssertEqual(
            decodedReport.acceptanceSummary.stabilizationShadowMetrics,
            IdentityCalibrationMetrics(
                identityChurnCount: 0,
                canonicalReassignmentCount: 0,
                ambiguousObservationCount: 2,
                provisionalPromotionCount: 1,
                falseAutoBindCount: 0,
                shadowObservationCount: 11
            )
        )
        XCTAssertEqual(
            decodedReport.acceptanceSummary.probeShadowMetrics,
            IdentityCalibrationMetrics(
                identityChurnCount: 1,
                canonicalReassignmentCount: 1,
                ambiguousObservationCount: 1,
                provisionalPromotionCount: 0,
                falseAutoBindCount: 0,
                shadowObservationCount: 4
            )
        )
        XCTAssertEqual(
            decodedReport.acceptanceSummary.probeLegacyReferenceMetrics,
            decodedReport.acceptanceSummary.probeShadowMetrics
        )
        XCTAssertEqual(
            summedMetrics(
                from: [
                    decodedReport.acceptanceSummary.stabilizationLegacyReferenceMetrics,
                    decodedReport.acceptanceSummary.probeLegacyReferenceMetrics,
                ]
            ),
            decodedReport.totalLegacyReferenceMetrics
        )
        XCTAssertEqual(
            summedMetrics(
                from: [
                    decodedReport.acceptanceSummary.stabilizationShadowMetrics,
                    decodedReport.acceptanceSummary.probeShadowMetrics,
                ]
            ),
            decodedReport.totalShadowMetrics
        )
        XCTAssertEqual(decodedReport.acceptanceSummary.stabilizationShadowChurnRate, 0)
        XCTAssertEqual(decodedReport.acceptanceSummary.stabilizationShadowFalseAutoBindRate, 0)
        XCTAssertEqual(decodedReport.signOff.status, .approved)
    }

    private func scenarioReport(
        for scenario: IdentityCalibrationScenario,
        metricsLabel: String,
        metrics: IdentityCalibrationMetrics
    ) -> String {
        """
        Scenario: \(scenario.id)
        Description: \(scenario.description)
        Expected: \(scenario.expectedMetrics)
        \(metricsLabel): \(metrics)
        """
    }

    private func summedMetrics(from metrics: [IdentityCalibrationMetrics]) -> IdentityCalibrationMetrics {
        metrics.reduce(into: IdentityCalibrationMetrics()) { total, metric in
            total.identityChurnCount += metric.identityChurnCount
            total.canonicalReassignmentCount += metric.canonicalReassignmentCount
            total.ambiguousObservationCount += metric.ambiguousObservationCount
            total.provisionalPromotionCount += metric.provisionalPromotionCount
            total.falseAutoBindCount += metric.falseAutoBindCount
            total.shadowObservationCount += metric.shadowObservationCount
        }
    }
}
