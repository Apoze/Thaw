//
//  IdentityRegistryTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

final class IdentityRegistryTests: XCTestCase {
    private var tempDirectory: URL?
    private var paths: ThawPersistencePaths?

    override func setUp() {
        super.setUp()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IdentityRegistryTests.\(UUID().uuidString)", isDirectory: true)
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

    func testRegistryPersistsCanonicalIdentityAcrossReload() async {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }
        let firstRegistry = IdentityRegistry(paths: paths)
        let firstPass = await firstRegistry.resolve([
            makeCandidate(
                bundleID: "com.example.alpha",
                title: "Alpha",
                axIdentifier: "alpha-item",
                slotIndex: 0,
            ),
        ])

        let secondRegistry = IdentityRegistry(paths: paths)
        let secondPass = await secondRegistry.resolve([
            makeCandidate(
                bundleID: "com.example.alpha",
                title: "Alpha",
                axIdentifier: "alpha-item",
                slotIndex: 0,
            ),
        ])

        XCTAssertEqual(firstPass.first?.identity.id, secondPass.first?.identity.id)
        XCTAssertEqual(firstPass.first?.canonicalID, secondPass.first?.canonicalID)
        XCTAssertNotEqual(firstPass.first?.canonicalID.rawValue, firstPass.first?.identity.id)
        XCTAssertEqual(secondPass.first?.confidence, .exact)
    }

    func testRegistryPromotesStableNonAXMatches() async {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }
        let registry = IdentityRegistry(paths: paths)
        let candidate = makeCandidate(
            bundleID: "com.example.beta",
            title: "Beta",
            axIdentifier: nil,
            slotIndex: 1
        )

        let first = await registry.resolve([candidate])
        let second = await registry.resolve([candidate])
        let third = await registry.resolve([candidate])

        XCTAssertEqual(first.first?.confidence, .provisional)
        XCTAssertEqual(second.first?.confidence, .provisional)
        XCTAssertEqual(third.first?.confidence, .high)
        XCTAssertEqual(first.first?.identity.id, third.first?.identity.id)
        XCTAssertEqual(first.first?.canonicalID, third.first?.canonicalID)
        XCTAssertNotEqual(first.first?.canonicalID.rawValue, first.first?.identity.id)
    }

    func testRegisterDormantReferencedIdentityIDsSeedsSnapshot() async {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }
        let registry = IdentityRegistry(paths: paths)
        await registry.registerDormantReferencedIdentityIDs([
            "com.example.gamma::stable-key::AXMenuBarItem",
            "com.example.gamma::stable-key::AXMenuBarItem",
        ])

        let snapshot = await registry.snapshot()

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records[0].legacyIdentityID, "com.example.gamma::stable-key::AXMenuBarItem")
        XCTAssertNotEqual(snapshot.records[0].id, snapshot.records[0].legacyIdentityID)
        XCTAssertNotNil(UUID(uuidString: snapshot.records[0].canonicalID.rawValue))
        XCTAssertTrue(snapshot.records[0].isDormant)
    }

    func testDormantLegacyIdentityIsReusedByLiveResolution() async throws {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }

        let registry = IdentityRegistry(paths: paths)
        let legacyIdentityID = "com.example.delta::stable-key::alpha::AXMenuBarItem"
        await registry.registerDormantReferencedIdentityIDs([legacyIdentityID])

        let dormantSnapshot = await registry.snapshot()
        XCTAssertEqual(dormantSnapshot.records.count, 1)
        let dormantRecord = try XCTUnwrap(dormantSnapshot.records.first)
        XCTAssertTrue(dormantRecord.isDormant)
        XCTAssertEqual(dormantRecord.legacyIdentityID, "com.example.delta::stable-key::AXMenuBarItem")
        XCTAssertNotEqual(dormantRecord.id, dormantRecord.legacyIdentityID)
        XCTAssertEqual(dormantRecord.bundleID, "com.example.delta")
        XCTAssertEqual(dormantRecord.stableKey, "stable-key")
        XCTAssertEqual(dormantRecord.normalizedTitle, "alpha")

        let resolved = await registry.resolve([
            makeCandidate(
                bundleID: "com.example.delta",
                title: "Alpha",
                axIdentifier: nil,
                slotIndex: 0,
            ),
        ])

        XCTAssertEqual(resolved.count, 1)
        let resolvedDescriptor = try XCTUnwrap(resolved.first)
        XCTAssertEqual(resolvedDescriptor.canonicalID, dormantRecord.canonicalID)
        XCTAssertEqual(resolvedDescriptor.identity.id, "com.example.delta::stable-key::AXMenuBarItem")
        XCTAssertEqual(resolvedDescriptor.identity.stableKey, "stable-key")
        XCTAssertNotEqual(resolvedDescriptor.canonicalID.rawValue, resolvedDescriptor.identity.id)

        let reloadedRegistry = IdentityRegistry(paths: paths)
        let reloadedSnapshot = await reloadedRegistry.snapshot()
        XCTAssertEqual(reloadedSnapshot.records.count, 1)
        XCTAssertEqual(reloadedSnapshot.records.first?.canonicalID, dormantRecord.canonicalID)
        XCTAssertFalse(reloadedSnapshot.records.first?.isDormant ?? true)
    }

    func testLegacyRegistrySnapshotIsReadWithoutRewritingOnDisk() async throws {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        let legacyData = try makeLegacyRegistryEnvelopeData()
        try legacyData.write(to: paths.identityRegistryV3URL, options: .atomic)

        let firstRegistry = IdentityRegistry(paths: paths)
        let firstSnapshot = await firstRegistry.snapshot()

        XCTAssertEqual(firstSnapshot.records.count, 1)
        XCTAssertEqual(firstSnapshot.records[0].legacyIdentityID, "com.example.delta::stable-key::AXMenuBarItem")
        XCTAssertNotEqual(firstSnapshot.records[0].id, firstSnapshot.records[0].legacyIdentityID)
        XCTAssertNotNil(UUID(uuidString: firstSnapshot.records[0].canonicalID.rawValue))
        XCTAssertEqual(try Data(contentsOf: paths.identityRegistryV3URL), legacyData)

        let secondRegistry = IdentityRegistry(paths: paths)
        let secondSnapshot = await secondRegistry.snapshot()

        XCTAssertEqual(secondSnapshot.records.count, 1)
        XCTAssertEqual(secondSnapshot.records[0].legacyIdentityID, firstSnapshot.records[0].legacyIdentityID)
        XCTAssertNotEqual(secondSnapshot.records[0].id, secondSnapshot.records[0].legacyIdentityID)
        XCTAssertNotNil(UUID(uuidString: secondSnapshot.records[0].canonicalID.rawValue))
        XCTAssertEqual(try Data(contentsOf: paths.identityRegistryV3URL), legacyData)
    }

    func testLegacyRegistrySnapshotMigrationAssignsStableCanonicalIDsAcrossReloads() async throws {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        let legacyData = try makeLegacyRegistryEnvelopeData()
        try legacyData.write(to: paths.identityRegistryV3URL, options: .atomic)

        XCTAssertTrue(
            try IdentityRegistry.migratePersistedSnapshotIfNeeded(
                fileManager: .default,
                paths: paths
            )
        )

        let firstRegistry = IdentityRegistry(paths: paths)
        let firstSnapshot = await firstRegistry.snapshot()
        let firstRecord = try XCTUnwrap(firstSnapshot.records.first)

        XCTAssertEqual(firstSnapshot.records.count, 1)
        XCTAssertEqual(firstRecord.legacyIdentityID, "com.example.delta::stable-key::AXMenuBarItem")
        XCTAssertEqual(firstRecord.bundleID, "com.example.delta")
        XCTAssertEqual(firstRecord.role, "AXMenuBarItem")
        XCTAssertTrue(firstRecord.isDormant)
        XCTAssertNotNil(UUID(uuidString: firstRecord.canonicalID.rawValue))

        let secondRegistry = IdentityRegistry(paths: paths)
        let secondSnapshot = await secondRegistry.snapshot()
        let secondRecord = try XCTUnwrap(secondSnapshot.records.first)

        XCTAssertEqual(secondSnapshot.records.count, 1)
        XCTAssertEqual(secondRecord.legacyIdentityID, firstRecord.legacyIdentityID)
        XCTAssertEqual(secondRecord.canonicalID, firstRecord.canonicalID)
        XCTAssertEqual(secondRecord.isDormant, firstRecord.isDormant)
        XCTAssertEqual(secondSnapshot.mode, firstSnapshot.mode)
        XCTAssertEqual(secondSnapshot.diagnostics, firstSnapshot.diagnostics)

        XCTAssertFalse(
            try IdentityRegistry.migratePersistedSnapshotIfNeeded(
                fileManager: .default,
                paths: paths
            )
        )

        let migratedData = try Data(contentsOf: paths.identityRegistryV3URL)
        let migratedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        let payload = try XCTUnwrap(migratedObject["payload"] as? [String: Any])
        let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertNotNil(records[0]["canonicalID"] as? String)
    }

    func testShadowModeTracksCalibrationDiagnosticsAcrossReloads() async throws {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }

        let registry = IdentityRegistry(paths: paths, mode: .shadow)
        let ambiguousCandidates = [
            makeCandidate(
                bundleID: "com.example.gamma",
                title: "Gamma",
                axIdentifier: nil,
                slotIndex: 0,
            ),
            makeCandidate(
                bundleID: "com.example.gamma",
                title: "Gamma",
                axIdentifier: nil,
                slotIndex: 1,
            ),
        ]

        let ambiguousResolution = await registry.resolve(ambiguousCandidates)
        XCTAssertEqual(ambiguousResolution.count, 2)

        let stableCandidate = makeCandidate(
            bundleID: "com.example.delta",
            title: "Delta",
            axIdentifier: nil,
            slotIndex: 0,
        )
        _ = await registry.resolve([stableCandidate])
        _ = await registry.resolve([stableCandidate])
        _ = await registry.resolve([stableCandidate])

        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.mode, .shadow)
        XCTAssertEqual(snapshot.diagnostics.shadowObservationCount, 5)
        XCTAssertEqual(snapshot.diagnostics.ambiguousMatchCount, 2)
        XCTAssertEqual(snapshot.diagnostics.provisionalPromotionCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.identityRegistryV3URL.path))

        let reloadedRegistry = IdentityRegistry(paths: paths, mode: .shadow)
        let reloadedSnapshot = await reloadedRegistry.snapshot()
        XCTAssertEqual(reloadedSnapshot.mode, .shadow)
        XCTAssertEqual(reloadedSnapshot.records.count, snapshot.records.count)
        XCTAssertEqual(reloadedSnapshot.diagnostics.shadowObservationCount, snapshot.diagnostics.shadowObservationCount)
    }

    func testShadowModeKeepsLegacySnapshotOnDiskWhileHydrating() async throws {
        guard let paths else {
            XCTFail("Missing persistence paths")
            return
        }
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        let legacyData = try makeLegacyRegistryEnvelopeData()
        try legacyData.write(to: paths.identityRegistryV3URL, options: .atomic)

        let registry = IdentityRegistry(paths: paths, mode: .shadow)
        let snapshot = await registry.snapshot()

        XCTAssertEqual(snapshot.mode, .shadow)
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertNotNil(UUID(uuidString: snapshot.records[0].canonicalID.rawValue))
        XCTAssertEqual(try Data(contentsOf: paths.identityRegistryV3URL), legacyData)

        let reloadedRegistry = IdentityRegistry(paths: paths, mode: .shadow)
        let reloadedSnapshot = await reloadedRegistry.snapshot()

        XCTAssertEqual(reloadedSnapshot.mode, .shadow)
        XCTAssertEqual(reloadedSnapshot.records.count, 1)
        XCTAssertNotEqual(
            reloadedSnapshot.records.first?.legacyIdentityID,
            reloadedSnapshot.records.first?.canonicalID.rawValue
        )
        XCTAssertNotNil(UUID(uuidString: reloadedSnapshot.records.first?.canonicalID.rawValue ?? ""))
        XCTAssertEqual(try Data(contentsOf: paths.identityRegistryV3URL), legacyData)
    }

    private func makeCandidate(
        bundleID: String,
        title: String,
        axIdentifier: String?,
        slotIndex: Int
    ) -> DiscoveredMenuExtraCandidate {
        let normalizedTitle = MenuExtraIdentity.normalizedTitle(title)
        return DiscoveredMenuExtraCandidate(
            ownerPID: 42,
            bundleIdentifier: bundleID,
            bundleURL: nil,
            applicationName: bundleID,
            title: title,
            normalizedTitle: normalizedTitle,
            rawRole: "AXMenuBarItem",
            axIdentifier: axIdentifier,
            slotIndex: slotIndex,
            slotSignature: "display-1:\(slotIndex)",
            frame: CGRect(x: CGFloat(slotIndex * 20), y: 0, width: 18, height: 18),
            displayID: nil,
            displayUUID: "display-1",
            capability: .axPress
        )
    }

    private func makeLegacyRegistryEnvelopeData() throws -> Data {
        let snapshot = LegacyIdentityRegistrySnapshot(
            mode: .active,
            diagnostics: .empty,
            records: [
                LegacyIdentityRegistryRecord(
                    bundleID: "com.example.delta",
                    role: "AXMenuBarItem",
                    locator: "stable-key",
                    slot: 0,
                    stableKey: "stable-key",
                    normalizedTitle: "",
                    axIdentifier: nil,
                    slotSignature: "dormant",
                    lastDisplayUUID: nil,
                    lastFrame: nil,
                    confidence: .ambiguous,
                    consistencyCount: 0,
                    isDormant: true
                ),
            ]
        )

        let envelope = PersistentEnvelope(schemaVersion: 3, payload: snapshot)
        return try JSONEncoder().encode(envelope)
    }
}

private struct LegacyIdentityRegistrySnapshot: Codable {
    let mode: IdentityRegistryMode
    let diagnostics: IdentityRegistryDiagnostics
    let records: [LegacyIdentityRegistryRecord]
}

private struct LegacyIdentityRegistryRecord: Codable {
    let bundleID: String
    let role: String
    let locator: String
    let slot: Int
    let stableKey: String
    let normalizedTitle: String
    let axIdentifier: String?
    let slotSignature: String
    let lastDisplayUUID: String?
    let lastFrame: IdentityRegistryFrame?
    let confidence: IdentityMatchConfidence
    let consistencyCount: Int
    let isDormant: Bool
}
