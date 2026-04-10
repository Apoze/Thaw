//
//  StartupMigrationRunnerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class StartupMigrationRunnerTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ThawPersistencePaths!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StartupMigrationRunnerTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        paths = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testRunnerMigratesLegacyLayoutOnceAndSkipsSecondBootstrap() async throws {
        let legacyLayout = ProfileLayoutV2(
            groupsByIdentityID: ["11111111-1111-1111-1111-111111111111": .archive],
            orderedIdentityIDsByGroup: [.archive: ["11111111-1111-1111-1111-111111111111"]],
            customNamesByIdentityID: ["11111111-1111-1111-1111-111111111111": "Legacy Alpha"]
        )
        let legacyEnvelope = PersistentEnvelope(
            schemaVersion: 3,
            payload: legacyLayout,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacyEnvelope).write(to: paths.layoutV3URL, options: .atomic)

        let firstRunner = StartupMigrationRunner(
            migrationCoordinator: MigrationCoordinator(
                fileManager: .default,
                paths: paths,
                dateProvider: { Date(timeIntervalSince1970: 1_710_000_100) }
            ),
            fileManager: .default,
            paths: paths
        )
        let firstReports = try await firstRunner.perform()

        XCTAssertEqual(
            firstReports.first(where: { $0.identifier == "runtime.layout.compatibility-upgrade" })?.outcome,
            .migrated
        )

        let migratedData = try Data(contentsOf: paths.layoutV3URL)
        let bookkeepingURL = paths.runtimeDirectory.appendingPathComponent("migration-metadata-v1.json")
        let bookkeepingData = try Data(contentsOf: bookkeepingURL)

        let secondRunner = StartupMigrationRunner(
            migrationCoordinator: MigrationCoordinator(
                fileManager: .default,
                paths: paths,
                dateProvider: { Date(timeIntervalSince1970: 1_710_000_200) }
            ),
            fileManager: .default,
            paths: paths
        )
        let secondReports = try await secondRunner.perform()

        XCTAssertEqual(
            secondReports.first(where: { $0.identifier == "runtime.layout.compatibility-upgrade" })?.outcome,
            .skippedAlreadyCompleted
        )
        XCTAssertEqual(migratedData, try Data(contentsOf: paths.layoutV3URL))
        XCTAssertEqual(bookkeepingData, try Data(contentsOf: bookkeepingURL))
    }
}
