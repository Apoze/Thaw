//
//  MigrationCoordinatorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class MigrationCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ThawPersistencePaths!
    private var fileManager: FileManager!
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationCoordinatorTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)
        fileManager = .default

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    override func tearDown() {
        try? fileManager.removeItem(at: tempDirectory)
        decoder = nil
        encoder = nil
        fileManager = nil
        paths = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testLegacyOnlyMigrationCreatesBackupAndPersistsBookkeeping() async throws {
        let coordinator = MigrationCoordinator(
            fileManager: fileManager,
            paths: paths,
            dateProvider: { Date(timeIntervalSince1970: 1_710_000_000) }
        )
        let legacyURL = tempDirectory.appendingPathComponent("runtime/layout-v2.json")
        let currentURL = tempDirectory.appendingPathComponent("runtime/layout-v3.json")
        try writeEnvelope(schemaVersion: 2, payload: "legacy", to: legacyURL)

        var runCount = 0
        let report = try await coordinator.perform(MigrationCoordinator.MigrationStep(
            identifier: "layout-migration",
            legacyURL: legacyURL,
            currentURL: currentURL,
            targetSchemaVersion: 3,
            description: "Upgrade layout state to V3"
        ) {
            runCount += 1
            try self.writeEnvelope(schemaVersion: 3, payload: "current", to: currentURL)
        })

        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.backupURL, legacyURL.appendingPathExtension("bak"))
        XCTAssertTrue(fileManager.fileExists(atPath: currentURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: legacyURL.appendingPathExtension("bak").path))

        let metadata = try decodeBookkeeping()
        XCTAssertEqual(metadata.payload.completedMigrationIdentifiers, ["layout-migration"])
        XCTAssertEqual(metadata.payload.completedSchemaVersions["layout-migration"], 3)
        XCTAssertEqual(metadata.payload.lastCompletedMigrationIdentifier, "layout-migration")

        let secondReport = try await coordinator.perform(MigrationCoordinator.MigrationStep(
            identifier: "layout-migration",
            legacyURL: legacyURL,
            currentURL: currentURL,
            targetSchemaVersion: 3,
            description: "Upgrade layout state to V3"
        ) {
            runCount += 1
            try self.writeEnvelope(schemaVersion: 3, payload: "current", to: currentURL)
        })

        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(secondReport.outcome, .skippedAlreadyCompleted)
    }

    func testCurrentV3StateWinsWithoutRunningMigration() async throws {
        let coordinator = MigrationCoordinator(
            fileManager: fileManager,
            paths: paths,
            dateProvider: { Date(timeIntervalSince1970: 1_710_000_100) }
        )
        let legacyURL = tempDirectory.appendingPathComponent("runtime/profiles.json")
        let currentURL = tempDirectory.appendingPathComponent("runtime/profiles-v3.json")
        try writeEnvelope(schemaVersion: 2, payload: "legacy", to: legacyURL)
        try writeEnvelope(schemaVersion: 3, payload: "current", to: currentURL)

        var runCount = 0
        let report = try await coordinator.perform(MigrationCoordinator.MigrationStep(
            identifier: "profiles-migration",
            legacyURL: legacyURL,
            currentURL: currentURL,
            targetSchemaVersion: 3,
            description: "Upgrade profile state to V3"
        ) {
            runCount += 1
        })

        XCTAssertEqual(runCount, 0)
        XCTAssertEqual(report.outcome, .skippedCurrentStateWins(schemaVersion: 3))
        XCTAssertNil(report.backupURL)
        XCTAssertTrue(coordinator.hasCompletedMigration("profiles-migration"))

        let metadata = try decodeBookkeeping()
        XCTAssertEqual(metadata.payload.completedMigrationIdentifiers, ["profiles-migration"])
        XCTAssertEqual(metadata.payload.completedSchemaVersions["profiles-migration"], 3)
    }

    func testLegacyStateCanBeMigratedInPlaceWhenCurrentURLMatchesLegacyURL() async throws {
        let coordinator = MigrationCoordinator(
            fileManager: fileManager,
            paths: paths,
            dateProvider: { Date(timeIntervalSince1970: 1_710_000_200) }
        )
        let migrationURL = tempDirectory.appendingPathComponent("runtime/layout-v3.json")
        let legacyData = try writeEnvelope(schemaVersion: 3, payload: "legacy", to: migrationURL)

        var runCount = 0
        let report = try await coordinator.perform(MigrationCoordinator.MigrationStep(
            identifier: "layout-migration-in-place",
            legacyURL: migrationURL,
            currentURL: migrationURL,
            targetSchemaVersion: 3,
            description: "Upgrade layout state in place to V3",
            currentStateRequiresMigration: {
                true
            }
        ) {
            runCount += 1
            try self.writeEnvelope(schemaVersion: 3, payload: "current", to: migrationURL)
        })

        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.backupURL, migrationURL.appendingPathExtension("bak"))
        XCTAssertEqual(try Data(contentsOf: migrationURL.appendingPathExtension("bak")), legacyData)
        XCTAssertEqual(try coordinator.currentSchemaVersion(for: migrationURL), 3)

        let metadata = try decodeBookkeeping()
        XCTAssertEqual(metadata.payload.completedMigrationIdentifiers, ["layout-migration-in-place"])
        XCTAssertEqual(metadata.payload.completedSchemaVersions["layout-migration-in-place"], 3)
        XCTAssertEqual(metadata.payload.lastCompletedMigrationIdentifier, "layout-migration-in-place")
    }

    func testLayoutCompatibilityMigrationRewritesLegacyEnvelopeInPlace() async throws {
        let coordinator = MigrationCoordinator(
            fileManager: fileManager,
            paths: paths,
            dateProvider: { Date(timeIntervalSince1970: 1_710_000_300) }
        )
        let legacyLayout = ProfileLayoutV2(
            groupsByIdentityID: ["legacy-alpha": .archive],
            orderedIdentityIDsByGroup: [.archive: ["legacy-alpha"]],
            customNamesByIdentityID: ["legacy-alpha": "Alpha"]
        )
        let legacyData = try writeRuntimeEnvelope(
            schemaVersion: 3,
            payload: legacyLayout,
            to: paths.layoutV3URL
        )

        let report = try await coordinator.perform(MigrationCoordinator.MigrationStep(
            identifier: "layout-compatibility-upgrade",
            legacyURL: paths.layoutV3URL,
            currentURL: paths.layoutV3URL,
            targetSchemaVersion: 3,
            description: "Rewrite legacy layout compatibility envelope in place",
            currentStateRequiresMigration: { [fileManager, paths] in
                LayoutService.persistedLayoutRequiresCompatibilityMigration(
                    fileManager: fileManager,
                    paths: paths!
                )
            }
        ) {
            try LayoutService.migratePersistedLayoutIfNeeded(
                fileManager: self.fileManager,
                paths: self.paths
            )
        })

        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.backupURL, paths.layoutV3URL.appendingPathExtension("bak"))
        XCTAssertEqual(try Data(contentsOf: paths.layoutV3URL.appendingPathExtension("bak")), legacyData)

        let migratedData = try Data(contentsOf: paths.layoutV3URL)
        let runtimeDecoder = JSONDecoder()
        let migratedEnvelope = try runtimeDecoder.decode(
            PersistentEnvelope<ProfileLayoutV3>.self,
            from: migratedData
        )
        XCTAssertEqual(
            migratedEnvelope.payload,
            ProfileLayoutMigration.migrate(legacyLayout)
        )
    }

    func testIdentityRegistryCanonicalIDMigrationRewritesLegacySnapshotInPlace() async throws {
        let coordinator = MigrationCoordinator(
            fileManager: fileManager,
            paths: paths,
            dateProvider: { Date(timeIntervalSince1970: 1_710_000_400) }
        )
        try fileManager.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        let legacyData = try makeLegacyIdentityRegistryEnvelopeData()
        try legacyData.write(to: paths.identityRegistryV3URL, options: .atomic)

        let report = try await coordinator.perform(MigrationCoordinator.MigrationStep(
            identifier: "identity-registry-canonical-id-upgrade",
            legacyURL: paths.identityRegistryV3URL,
            currentURL: paths.identityRegistryV3URL,
            targetSchemaVersion: 3,
            description: "Rewrite legacy identity registry records with canonical IDs",
            currentStateRequiresMigration: { [fileManager, paths] in
                IdentityRegistry.persistedStateRequiresCanonicalIDUpgrade(
                    fileManager: fileManager,
                    paths: paths!
                )
            }
        ) {
            try IdentityRegistry.migratePersistedSnapshotIfNeeded(
                fileManager: self.fileManager,
                paths: self.paths
            )
        })

        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.backupURL, paths.identityRegistryV3URL.appendingPathExtension("bak"))
        XCTAssertEqual(
            try Data(contentsOf: paths.identityRegistryV3URL.appendingPathExtension("bak")),
            legacyData
        )

        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: paths.identityRegistryV3URL)) as? [String: Any]
        )
        let payload = try XCTUnwrap(migratedObject["payload"] as? [String: Any])
        let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
        XCTAssertTrue(records.allSatisfy { $0["canonicalID"] is String })
    }

    func testBackupCreationIsIdempotent() throws {
        let coordinator = MigrationCoordinator(fileManager: fileManager, paths: paths)
        let legacyURL = tempDirectory.appendingPathComponent("runtime/identity-registry-v2.json")
        _ = try writeEnvelope(schemaVersion: 2, payload: "legacy", to: legacyURL)

        let firstBackupURL = try coordinator.createBackupIfNeeded(for: legacyURL)
        let secondBackupURL = try coordinator.createBackupIfNeeded(for: legacyURL)

        XCTAssertEqual(firstBackupURL, legacyURL.appendingPathExtension("bak"))
        XCTAssertEqual(secondBackupURL, legacyURL.appendingPathExtension("bak"))
        XCTAssertEqual(
            try Data(contentsOf: legacyURL),
            try Data(contentsOf: legacyURL.appendingPathExtension("bak"))
        )
    }

    @discardableResult
    private func writeEnvelope<P: Codable>(schemaVersion: Int, payload: P, to url: URL) throws -> Data {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let envelope = PersistentEnvelope(schemaVersion: schemaVersion, payload: payload)
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: .atomic)
        return data
    }

    private func decodeBookkeeping() throws -> PersistentEnvelope<MigrationCoordinator.MigrationBookkeepingSnapshot> {
        let url = paths.runtimeDirectory.appendingPathComponent("migration-metadata-v1.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(PersistentEnvelope<MigrationCoordinator.MigrationBookkeepingSnapshot>.self, from: data)
    }

    @discardableResult
    private func writeRuntimeEnvelope<P: Codable>(schemaVersion: Int, payload: P, to url: URL) throws -> Data {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let runtimeEncoder = JSONEncoder()
        runtimeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelope = PersistentEnvelope(schemaVersion: schemaVersion, payload: payload)
        let data = try runtimeEncoder.encode(envelope)
        try data.write(to: url, options: .atomic)
        return data
    }

    private func makeLegacyIdentityRegistryEnvelopeData() throws -> Data {
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
        let runtimeEncoder = JSONEncoder()
        runtimeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try runtimeEncoder.encode(envelope)
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
