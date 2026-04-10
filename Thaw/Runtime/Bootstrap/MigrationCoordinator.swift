//
//  MigrationCoordinator.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class MigrationCoordinator {
    struct MigrationStep {
        let identifier: String
        let legacyURL: URL?
        let currentURL: URL?
        let targetSchemaVersion: Int
        let description: String
        let currentStateRequiresMigration: (() async throws -> Bool)?
        let run: () async throws -> Void

        init(
            identifier: String,
            legacyURL: URL?,
            currentURL: URL?,
            targetSchemaVersion: Int,
            description: String,
            currentStateRequiresMigration: (() async throws -> Bool)? = nil,
            run: @escaping () async throws -> Void
        ) {
            self.identifier = identifier
            self.legacyURL = legacyURL
            self.currentURL = currentURL
            self.targetSchemaVersion = targetSchemaVersion
            self.description = description
            self.currentStateRequiresMigration = currentStateRequiresMigration
            self.run = run
        }
    }

    enum MigrationExecutionOutcome: Equatable {
        case migrated
        case skippedAlreadyCompleted
        case skippedCurrentStateWins(schemaVersion: Int)
        case skippedMissingLegacyState
    }

    struct MigrationExecutionReport: Equatable {
        let identifier: String
        let outcome: MigrationExecutionOutcome
        let backupURL: URL?
    }

    struct MigrationBookkeepingSnapshot: Codable, Equatable {
        var completedMigrationIdentifiers: [String]
        var completedSchemaVersions: [String: Int]
        var lastRunAt: Date?
        var lastCompletedMigrationIdentifier: String?

        static let empty = MigrationBookkeepingSnapshot(
            completedMigrationIdentifiers: [],
            completedSchemaVersions: [:],
            lastRunAt: nil,
            lastCompletedMigrationIdentifier: nil
        )
    }

    private struct EnvelopeSchemaVersionOnly: Decodable {
        let schemaVersion: Int
    }

    private let diagLog = DiagLog(category: .startup)
    private let fileManager: FileManager
    private let paths: ThawPersistencePaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateProvider: () -> Date
    private var bookkeeping: MigrationBookkeepingSnapshot

    init(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.paths = paths
        self.dateProvider = dateProvider

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        bookkeeping = Self.loadBookkeeping(
            fileManager: fileManager,
            metadataURL: Self.metadataURL(for: paths),
            decoder: decoder,
            diagLog: diagLog
        )
    }

    func perform(_ steps: [MigrationStep]) async throws -> [MigrationExecutionReport] {
        var reports = [MigrationExecutionReport]()
        reports.reserveCapacity(steps.count)

        for step in steps {
            let report = try await perform(step)
            reports.append(report)
        }

        return reports
    }

    func perform(_ step: MigrationStep) async throws -> MigrationExecutionReport {
        if isCompleted(step.identifier) {
            diagLog.debug("Skipping migration '\(step.identifier)' because it already completed")
            return MigrationExecutionReport(
                identifier: step.identifier,
                outcome: .skippedAlreadyCompleted,
                backupURL: nil
            )
        }

        let currentSchemaVersion = try currentSchemaVersion(for: step.currentURL)
        if let currentStateRequiresMigration = step.currentStateRequiresMigration {
            let shouldRunMigration = try await currentStateRequiresMigration()
            if !shouldRunMigration {
                let winningSchemaVersion = currentSchemaVersion ?? step.targetSchemaVersion
                diagLog.info(
                    "Migration '\(step.identifier)' skipped because current V\(winningSchemaVersion) state wins"
                )
                recordCompletion(identifier: step.identifier, schemaVersion: winningSchemaVersion)
                return MigrationExecutionReport(
                    identifier: step.identifier,
                    outcome: .skippedCurrentStateWins(schemaVersion: winningSchemaVersion),
                    backupURL: nil
                )
            }
        } else if let currentSchemaVersion, currentSchemaVersion >= step.targetSchemaVersion {
            diagLog.info("Migration '\(step.identifier)' skipped because current V\(currentSchemaVersion) state wins")
            recordCompletion(identifier: step.identifier, schemaVersion: currentSchemaVersion)
            return MigrationExecutionReport(
                identifier: step.identifier,
                outcome: .skippedCurrentStateWins(schemaVersion: currentSchemaVersion),
                backupURL: nil
            )
        }

        let migrationSourceURL = step.legacyURL ?? step.currentURL
        guard let migrationSourceURL, fileManager.fileExists(atPath: migrationSourceURL.path) else {
            diagLog.debug("Skipping migration '\(step.identifier)' because legacy state is missing")
            return MigrationExecutionReport(
                identifier: step.identifier,
                outcome: .skippedMissingLegacyState,
                backupURL: nil
            )
        }

        let backupURL = try createBackupIfNeeded(for: migrationSourceURL)
        if let backupURL {
            diagLog.info("Created migration backup for '\(step.identifier)' at \(backupURL.lastPathComponent)")
        }

        diagLog.debug("Running migration '\(step.identifier)': \(step.description)")
        do {
            try await step.run()
            recordCompletion(identifier: step.identifier, schemaVersion: step.targetSchemaVersion)
            return MigrationExecutionReport(
                identifier: step.identifier,
                outcome: .migrated,
                backupURL: backupURL
            )
        } catch {
            diagLog.error("Migration '\(step.identifier)' failed: \(error)")
            throw error
        }
    }

    func createBackupIfNeeded(for sourceURL: URL) throws -> URL? {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let backupURL = sourceURL.appendingPathExtension("bak")
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            return backupURL
        }

        try fileManager.copyItem(at: sourceURL, to: backupURL)
        return backupURL
    }

    func snapshot() -> MigrationBookkeepingSnapshot {
        bookkeeping
    }

    func hasCompletedMigration(_ identifier: String) -> Bool {
        isCompleted(identifier)
    }

    func currentSchemaVersion(for url: URL?) throws -> Int? {
        guard let url, fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let envelope = try decoder.decode(EnvelopeSchemaVersionOnly.self, from: data)
        return envelope.schemaVersion
    }

    private func isCompleted(_ identifier: String) -> Bool {
        bookkeeping.completedMigrationIdentifiers.contains(identifier)
    }

    private func recordCompletion(identifier: String, schemaVersion: Int) {
        if !bookkeeping.completedMigrationIdentifiers.contains(identifier) {
            bookkeeping.completedMigrationIdentifiers.append(identifier)
        }
        bookkeeping.completedSchemaVersions[identifier] = schemaVersion
        bookkeeping.lastRunAt = dateProvider()
        bookkeeping.lastCompletedMigrationIdentifier = identifier
        persistBookkeeping()
    }

    private func persistBookkeeping() {
        do {
            try fileManager.createDirectory(
                at: paths.runtimeDirectory,
                withIntermediateDirectories: true
            )

            let envelope = PersistentEnvelope(schemaVersion: 1, payload: bookkeeping)
            let data = try encoder.encode(envelope)
            try data.write(to: Self.metadataURL(for: paths), options: .atomic)
        } catch {
            diagLog.error("Failed to persist migration bookkeeping: \(error)")
        }
    }

    private static func loadBookkeeping(
        fileManager: FileManager,
        metadataURL: URL,
        decoder: JSONDecoder,
        diagLog: DiagLog
    ) -> MigrationBookkeepingSnapshot {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let envelope = try decoder.decode(
                PersistentEnvelope<MigrationBookkeepingSnapshot>.self,
                from: data
            )
            return envelope.payload
        } catch {
            diagLog.error("Failed to load migration bookkeeping: \(error)")
            return .empty
        }
    }

    private static func metadataURL(for paths: ThawPersistencePaths) -> URL {
        paths.runtimeDirectory.appendingPathComponent("migration-metadata-v1.json")
    }
}
