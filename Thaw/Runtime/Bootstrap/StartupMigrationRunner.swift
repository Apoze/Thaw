//
//  StartupMigrationRunner.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class StartupMigrationRunner {
    private let migrationCoordinator: MigrationCoordinator
    private let fileManager: FileManager
    private let persistencePaths: ThawPersistencePaths

    init(
        migrationCoordinator: MigrationCoordinator,
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) {
        self.migrationCoordinator = migrationCoordinator
        self.fileManager = fileManager
        persistencePaths = paths
    }

    func perform() async throws -> [MigrationCoordinator.MigrationExecutionReport] {
        try await migrationCoordinator.perform(migrationSteps())
    }

    private func migrationSteps() -> [MigrationCoordinator.MigrationStep] {
        [
            MigrationCoordinator.MigrationStep(
                identifier: "runtime.layout.compatibility-upgrade",
                legacyURL: persistencePaths.layoutV3URL,
                currentURL: persistencePaths.layoutV3URL,
                targetSchemaVersion: 3,
                description: "Rewrite legacy layout compatibility envelopes to canonical V3 layout state",
                currentStateRequiresMigration: { [fileManager, persistencePaths] in
                    LayoutService.persistedLayoutRequiresCompatibilityMigration(
                        fileManager: fileManager,
                        paths: persistencePaths
                    )
                },
                run: { [fileManager, persistencePaths] in
                    try LayoutService.migratePersistedLayoutIfNeeded(
                        fileManager: fileManager,
                        paths: persistencePaths
                    )
                }
            ),
            MigrationCoordinator.MigrationStep(
                identifier: "runtime.identity-registry.canonical-id-upgrade",
                legacyURL: persistencePaths.identityRegistryV3URL,
                currentURL: persistencePaths.identityRegistryV3URL,
                targetSchemaVersion: 3,
                description: "Rewrite legacy identity registry records to canonical opaque IDs",
                currentStateRequiresMigration: { [fileManager, persistencePaths] in
                    IdentityRegistry.persistedStateRequiresCanonicalIDUpgrade(
                        fileManager: fileManager,
                        paths: persistencePaths
                    )
                },
                run: { [fileManager, persistencePaths] in
                    try IdentityRegistry.migratePersistedSnapshotIfNeeded(
                        fileManager: fileManager,
                        paths: persistencePaths
                    )
                }
            ),
        ]
    }
}
