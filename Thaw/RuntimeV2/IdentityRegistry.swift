//
//  IdentityRegistry.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

enum IdentityMatchConfidence: String, Codable, Hashable {
    case exact
    case high
    case provisional
    case ambiguous
}

enum IdentityRegistryMode: String, Codable, Hashable {
    case active
    case shadow
}

enum IdentityRegistryThresholds {
    static let autoBindMaximumScore: CGFloat = 72
    static let provisionalMaximumScore: CGFloat = 180
    static let minimumWinnerMargin: CGFloat = 24
    static let displayMismatchPenalty: CGFloat = 120
    static let axIdentifierMismatchPenalty: CGFloat = 240
    static let slotMismatchPenalty: CGFloat = 36
    static let frameDistanceTolerance: CGFloat = 18
    static let provisionalPromotionObservationCount = 3
}

struct IdentityRegistryDiagnostics: Codable, Hashable {
    var identityChurnCount: Int
    var canonicalReassignmentCount: Int
    var ambiguousMatchCount: Int
    var provisionalPromotionCount: Int
    var shadowObservationCount: Int

    static let empty = IdentityRegistryDiagnostics(
        identityChurnCount: 0,
        canonicalReassignmentCount: 0,
        ambiguousMatchCount: 0,
        provisionalPromotionCount: 0,
        shadowObservationCount: 0
    )

    private enum CodingKeys: String, CodingKey {
        case identityChurnCount
        case canonicalReassignmentCount
        case ambiguousMatchCount
        case provisionalPromotionCount
        case shadowObservationCount
    }

    init(
        identityChurnCount: Int,
        canonicalReassignmentCount: Int,
        ambiguousMatchCount: Int,
        provisionalPromotionCount: Int,
        shadowObservationCount: Int
    ) {
        self.identityChurnCount = identityChurnCount
        self.canonicalReassignmentCount = canonicalReassignmentCount
        self.ambiguousMatchCount = ambiguousMatchCount
        self.provisionalPromotionCount = provisionalPromotionCount
        self.shadowObservationCount = shadowObservationCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identityChurnCount = try container.decodeIfPresent(Int.self, forKey: .identityChurnCount) ?? 0
        canonicalReassignmentCount = try container.decodeIfPresent(Int.self, forKey: .canonicalReassignmentCount) ?? 0
        ambiguousMatchCount = try container.decodeIfPresent(Int.self, forKey: .ambiguousMatchCount) ?? 0
        provisionalPromotionCount = try container.decodeIfPresent(Int.self, forKey: .provisionalPromotionCount) ?? 0
        shadowObservationCount = try container.decodeIfPresent(Int.self, forKey: .shadowObservationCount) ?? 0
    }
}

struct IdentityRegistryFrame: Codable, Hashable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct IdentityRegistryRecord: Codable, Hashable, Identifiable {
    let canonicalID: MenuExtraCanonicalID
    let bundleID: String
    let role: String
    let locator: String
    var slot: Int
    var stableKey: String
    var normalizedTitle: String
    var axIdentifier: String?
    var slotSignature: String
    var lastDisplayUUID: String?
    var lastFrame: IdentityRegistryFrame?
    var confidence: IdentityMatchConfidence
    var consistencyCount: Int
    var isDormant: Bool

    var id: String {
        canonicalID.rawValue
    }

    var legacyIdentityID: String {
        [bundleID, stableKey, role].joined(separator: "::")
    }

    private enum CodingKeys: String, CodingKey {
        case canonicalID
        case bundleID
        case role
        case locator
        case slot
        case stableKey
        case normalizedTitle
        case axIdentifier
        case slotSignature
        case lastDisplayUUID
        case lastFrame
        case confidence
        case consistencyCount
        case isDormant
    }

    init(
        canonicalID: MenuExtraCanonicalID,
        bundleID: String,
        role: String,
        locator: String,
        slot: Int,
        stableKey: String,
        normalizedTitle: String,
        axIdentifier: String?,
        slotSignature: String,
        lastDisplayUUID: String?,
        lastFrame: IdentityRegistryFrame?,
        confidence: IdentityMatchConfidence,
        consistencyCount: Int,
        isDormant: Bool
    ) {
        self.canonicalID = canonicalID
        self.bundleID = bundleID
        self.role = role
        self.locator = locator
        self.slot = slot
        self.stableKey = stableKey
        self.normalizedTitle = normalizedTitle
        self.axIdentifier = axIdentifier
        self.slotSignature = slotSignature
        self.lastDisplayUUID = lastDisplayUUID
        self.lastFrame = lastFrame
        self.confidence = confidence
        self.consistencyCount = consistencyCount
        self.isDormant = isDormant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        role = try container.decode(String.self, forKey: .role)
        locator = try container.decode(String.self, forKey: .locator)
        slot = try container.decode(Int.self, forKey: .slot)
        stableKey = try container.decode(String.self, forKey: .stableKey)
        normalizedTitle = try container.decode(String.self, forKey: .normalizedTitle)
        axIdentifier = try container.decodeIfPresent(String.self, forKey: .axIdentifier)
        slotSignature = try container.decode(String.self, forKey: .slotSignature)
        lastDisplayUUID = try container.decodeIfPresent(String.self, forKey: .lastDisplayUUID)
        lastFrame = try container.decodeIfPresent(IdentityRegistryFrame.self, forKey: .lastFrame)
        confidence = try container.decode(IdentityMatchConfidence.self, forKey: .confidence)
        consistencyCount = try container.decode(Int.self, forKey: .consistencyCount)
        isDormant = try container.decode(Bool.self, forKey: .isDormant)
        canonicalID = try container.decodeIfPresent(MenuExtraCanonicalID.self, forKey: .canonicalID)
            ?? Self.derivedLegacyCanonicalID(
                bundleID: bundleID,
                role: role,
                locator: locator,
                slot: slot,
                stableKey: stableKey,
                normalizedTitle: normalizedTitle,
                axIdentifier: axIdentifier,
                slotSignature: slotSignature
            )
    }

    static func dormantRecord(forLegacyIdentityID legacyIdentityID: String) -> IdentityRegistryRecord? {
        let components = legacyIdentityID.components(separatedBy: "::")
        guard components.count >= 3 else {
            return nil
        }

        let bundleID = components[0]
        let stableKey = components[1]
        let role = components.last ?? "AXUnknown"
        let normalizedTitle = components.count > 3 ? components[2] : ""
        let locator = normalizedTitle.isEmpty ? stableKey : normalizedTitle

        return IdentityRegistryRecord(
            canonicalID: derivedLegacyCanonicalID(
                bundleID: bundleID,
                role: role,
                locator: locator,
                slot: 0,
                stableKey: stableKey,
                normalizedTitle: normalizedTitle,
                axIdentifier: nil,
                slotSignature: "dormant"
            ),
            bundleID: bundleID,
            role: role,
            locator: locator,
            slot: 0,
            stableKey: stableKey,
            normalizedTitle: normalizedTitle,
            axIdentifier: nil,
            slotSignature: "dormant",
            lastDisplayUUID: nil,
            lastFrame: nil,
            confidence: .ambiguous,
            consistencyCount: 0,
            isDormant: true
        )
    }

    private static func derivedLegacyCanonicalID(
        bundleID: String,
        role: String,
        locator: String,
        slot: Int,
        stableKey: String,
        normalizedTitle: String,
        axIdentifier: String?,
        slotSignature: String
    ) -> MenuExtraCanonicalID {
        let seed = [
            "identity-registry-v3",
            bundleID,
            role,
            locator,
            String(slot),
            stableKey,
            normalizedTitle,
            axIdentifier ?? "",
            slotSignature,
        ].joined(separator: "|")

        return .deterministic(fromStableSeed: seed)
    }
}

struct IdentityRegistrySnapshot: Codable, Hashable {
    var mode: IdentityRegistryMode
    var diagnostics: IdentityRegistryDiagnostics
    var records: [IdentityRegistryRecord]
}

struct CanonicalizedMenuExtraCandidate: Hashable {
    let canonicalID: MenuExtraCanonicalID
    let source: DiscoveredMenuExtraCandidate
    let identity: MenuExtraIdentity
    let confidence: IdentityMatchConfidence
}

actor IdentityRegistry {
    private struct Signature: Hashable {
        let bundleID: String
        let role: String
        let locator: String
    }

    private struct IndexedCandidate {
        let index: Int
        let candidate: DiscoveredMenuExtraCandidate
    }

    private struct IndexedResolvedCandidate {
        let index: Int
        let candidate: CanonicalizedMenuExtraCandidate
    }

    private struct MatchResult {
        let matchedIndex: Int?
        let bestScore: CGFloat?
        let runnerUpScore: CGFloat?
    }

    private struct GroupResolution {
        let resolvedCandidates: [IndexedResolvedCandidate]
        let updatedRecords: [IdentityRegistryRecord]
        let diagnosticsDelta: IdentityRegistryDiagnostics
        let confidenceDemotionCount: Int
    }

    private let diagLog = DiagLog(category: .identity)
    private let fileManager: FileManager
    private let paths: ThawPersistencePaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var mode: IdentityRegistryMode
    private var diagnostics: IdentityRegistryDiagnostics
    private var recordsBySignature = [Signature: [IdentityRegistryRecord]]()

    init(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default(),
        mode: IdentityRegistryMode = .active
    ) {
        self.fileManager = fileManager
        self.paths = paths

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder

        let persistedState = Self.loadPersistedState(
            fileManager: fileManager,
            paths: paths,
            decoder: decoder
        )
        self.mode = mode
        diagnostics = persistedState.diagnostics
        recordsBySignature = persistedState.recordsBySignature
    }

    func resolve(_ candidates: [DiscoveredMenuExtraCandidate]) -> [CanonicalizedMenuExtraCandidate] {
        guard !candidates.isEmpty else {
            return []
        }

        let indexedCandidates = candidates.enumerated().map { index, candidate in
            IndexedCandidate(index: index, candidate: candidate)
        }
        let groupedCandidates = Dictionary(grouping: indexedCandidates, by: signature(for:))

        var nextRecordsBySignature = recordsBySignature
        var resolvedByIndex = [Int: CanonicalizedMenuExtraCandidate]()
        var nextDiagnostics = diagnostics
        var confidenceDemotionCount = 0

        if mode == .shadow {
            nextDiagnostics.shadowObservationCount += candidates.count
        }

        for (signature, groupCandidates) in groupedCandidates {
            let previousRecords = nextRecordsBySignature[signature] ?? []
            let resolution = resolveGroup(
                signature: signature,
                candidates: groupCandidates,
                previousRecords: previousRecords
            )

            nextRecordsBySignature[signature] = resolution.updatedRecords
            nextDiagnostics.identityChurnCount += resolution.diagnosticsDelta.identityChurnCount
            nextDiagnostics.canonicalReassignmentCount += resolution.diagnosticsDelta.canonicalReassignmentCount
            nextDiagnostics.ambiguousMatchCount += resolution.diagnosticsDelta.ambiguousMatchCount
            nextDiagnostics.provisionalPromotionCount += resolution.diagnosticsDelta.provisionalPromotionCount
            confidenceDemotionCount += resolution.confidenceDemotionCount
            for resolved in resolution.resolvedCandidates {
                resolvedByIndex[resolved.index] = resolved.candidate
            }
        }

        let identityChurnDelta = nextDiagnostics.identityChurnCount - diagnostics.identityChurnCount
        let ambiguousMatchDelta = nextDiagnostics.ambiguousMatchCount - diagnostics.ambiguousMatchCount
        let confidencePromotionDelta = nextDiagnostics.provisionalPromotionCount - diagnostics.provisionalPromotionCount

        recordsBySignature = nextRecordsBySignature
        diagnostics = nextDiagnostics
        RuntimeMetrics.shared.incrementIdentityChurn(by: identityChurnDelta)
        RuntimeMetrics.shared.incrementAmbiguousCandidateCount(by: ambiguousMatchDelta)
        RuntimeMetrics.shared.incrementConfidencePromotionCount(by: confidencePromotionDelta)
        RuntimeMetrics.shared.incrementConfidenceDemotionCount(by: confidenceDemotionCount)
        persist()

        return indexedCandidates
            .sorted { $0.index < $1.index }
            .compactMap { resolvedByIndex[$0.index] }
    }

    func ensureCanonicalIDs(forLegacyIdentityIDs identityIDs: [String]) -> [String: MenuExtraCanonicalID] {
        let ensured = ensureCanonicalIDMapping(forLegacyIdentityIDs: identityIDs)
        if ensured.insertedCount > 0 {
            diagLog.info("Registered \(ensured.insertedCount) dormant identity references")
            persist()
        }
        return ensured.mapping
    }

    // Layout/profile persistence still references legacy identity IDs until the layout V3 cutover.
    func registerDormantReferencedIdentityIDs(_ identityIDs: [String]) {
        _ = ensureCanonicalIDs(forLegacyIdentityIDs: identityIDs)
    }

    func snapshot() -> IdentityRegistrySnapshot {
        IdentityRegistrySnapshot(
            mode: mode,
            diagnostics: diagnostics,
            records: flattenedRecords()
        )
    }

    static func canonicalizeLayoutReferences(
        _ layout: ProfileLayoutV3,
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) -> ProfileLayoutV3 {
        let decoder = JSONDecoder()
        let persistedState = loadPersistedState(
            fileManager: fileManager,
            paths: paths,
            decoder: decoder
        )
        var recordsBySignature = persistedState.recordsBySignature
        let canonicalizedLayout = canonicalizedLayoutReferences(
            layout,
            recordsBySignature: &recordsBySignature
        )

        guard recordsBySignature != persistedState.recordsBySignature else {
            return canonicalizedLayout
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let diagLog = DiagLog(category: .identity)
        persist(
            snapshot: IdentityRegistrySnapshot(
                mode: persistedState.persistedMode ?? .active,
                diagnostics: persistedState.diagnostics,
                records: flattenedRecords(from: recordsBySignature)
            ),
            encoder: encoder,
            fileManager: fileManager,
            paths: paths,
            diagLog: diagLog
        )

        return canonicalizedLayout
    }

    static func persistedStateRequiresCanonicalIDUpgrade(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) -> Bool {
        guard fileManager.fileExists(atPath: paths.identityRegistryV3URL.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: paths.identityRegistryV3URL)
            return snapshotNeedsCanonicalIDUpgrade(data: data)
        } catch {
            return false
        }
    }

    @discardableResult
    static func migratePersistedSnapshotIfNeeded(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default(),
        mode overrideMode: IdentityRegistryMode? = nil
    ) throws -> Bool {
        let decoder = JSONDecoder()
        let persistedState = loadPersistedState(
            fileManager: fileManager,
            paths: paths,
            decoder: decoder
        )
        guard persistedState.needsPersistenceUpgrade else {
            return false
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let diagLog = DiagLog(category: .identity)
        persist(
            snapshot: IdentityRegistrySnapshot(
                mode: overrideMode ?? persistedState.persistedMode ?? .active,
                diagnostics: persistedState.diagnostics,
                records: flattenedRecords(from: persistedState.recordsBySignature)
            ),
            encoder: encoder,
            fileManager: fileManager,
            paths: paths,
            diagLog: diagLog
        )
        return true
    }

    private static func loadPersistedState(
        fileManager: FileManager,
        paths: ThawPersistencePaths,
        decoder: JSONDecoder
    ) -> (
        persistedMode: IdentityRegistryMode?,
        diagnostics: IdentityRegistryDiagnostics,
        recordsBySignature: [Signature: [IdentityRegistryRecord]],
        needsPersistenceUpgrade: Bool
    ) {
        guard fileManager.fileExists(atPath: paths.identityRegistryV3URL.path) else {
            return (nil, .empty, [:], false)
        }

        do {
            let data = try Data(contentsOf: paths.identityRegistryV3URL)
            let needsPersistenceUpgrade = snapshotNeedsCanonicalIDUpgrade(data: data)
            let envelope = try decoder.decode(
                PersistentEnvelope<IdentityRegistrySnapshot>.self,
                from: data
            )
            let recordsBySignature = Dictionary(grouping: envelope.payload.records) { record in
                Signature(
                    bundleID: record.bundleID,
                    role: record.role,
                    locator: record.locator
                )
            }
            return (
                envelope.payload.mode,
                envelope.payload.diagnostics,
                recordsBySignature,
                needsPersistenceUpgrade
            )
        } catch {
            return (nil, .empty, [:], false)
        }
    }

    private static func snapshotNeedsCanonicalIDUpgrade(data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = object["payload"] as? [String: Any],
            let records = payload["records"] as? [[String: Any]]
        else {
            return false
        }

        return records.contains { $0["canonicalID"] == nil }
    }

    private static func canonicalizedLayoutReferences(
        _ layout: ProfileLayoutV3,
        recordsBySignature: inout [Signature: [IdentityRegistryRecord]]
    ) -> ProfileLayoutV3 {
        var canonicalizationCache = [String: String]()

        func canonicalID(for referenceID: String) -> String {
            if let cached = canonicalizationCache[referenceID] {
                return cached
            }

            let resolvedID = resolveCanonicalReferenceID(
                for: referenceID,
                recordsBySignature: &recordsBySignature
            )
            canonicalizationCache[referenceID] = resolvedID
            return resolvedID
        }

        var canonicalized = ProfileLayoutV3.empty

        let orderedGroupEntries = layout.groupsByCanonicalID
            .map { (referenceID: $0.key, group: $0.value) }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.referenceID == canonicalID(for: lhs.referenceID) ? 0 : 1
                let rhsPriority = rhs.referenceID == canonicalID(for: rhs.referenceID) ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.referenceID < rhs.referenceID
            }
        for entry in orderedGroupEntries {
            canonicalized.groupsByCanonicalID[canonicalID(for: entry.referenceID)] = canonicalized.groupsByCanonicalID[
                canonicalID(for: entry.referenceID),
                default: entry.group
            ]
        }

        let orderedAliasEntries = layout.customNamesByCanonicalID
            .map { (referenceID: $0.key, alias: $0.value) }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.referenceID == canonicalID(for: lhs.referenceID) ? 0 : 1
                let rhsPriority = rhs.referenceID == canonicalID(for: rhs.referenceID) ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.referenceID < rhs.referenceID
            }
        for entry in orderedAliasEntries {
            canonicalized.customNamesByCanonicalID[canonicalID(for: entry.referenceID)] = canonicalized.customNamesByCanonicalID[
                canonicalID(for: entry.referenceID),
                default: entry.alias
            ]
        }

        canonicalized.orderedCanonicalIDsByGroup = layout.orderedCanonicalIDsByGroup.reduce(into: [:]) { result, entry in
            result[entry.key] = uniqued(entry.value.map(canonicalID(for:)))
        }

        canonicalized.dormantIDs = Set(layout.dormantIDs.map(canonicalID(for:)))

        return canonicalized
    }

    private static func resolveCanonicalReferenceID(
        for referenceID: String,
        recordsBySignature: inout [Signature: [IdentityRegistryRecord]]
    ) -> String {
        if UUID(uuidString: referenceID) != nil {
            return referenceID
        }

        let flattenedRecords = flattenedRecords(from: recordsBySignature)
        if let persistedRecord = flattenedRecords.first(where: { $0.canonicalID.rawValue == referenceID }) {
            return persistedRecord.canonicalID.rawValue
        }
        if let persistedRecord = flattenedRecords.first(where: { $0.legacyIdentityID == referenceID }) {
            return persistedRecord.canonicalID.rawValue
        }

        guard let dormantRecord = IdentityRegistryRecord.dormantRecord(forLegacyIdentityID: referenceID) else {
            return referenceID
        }

        if let persistedRecord = flattenedRecords.first(where: {
            $0.legacyIdentityID == dormantRecord.legacyIdentityID
        }) {
            return persistedRecord.canonicalID.rawValue
        }

        let signature = Signature(
            bundleID: dormantRecord.bundleID,
            role: dormantRecord.role,
            locator: dormantRecord.locator
        )
        recordsBySignature[signature, default: []].append(dormantRecord)
        return dormantRecord.canonicalID.rawValue
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func persist() {
        Self.persist(
            snapshot: IdentityRegistrySnapshot(
                mode: mode,
                diagnostics: diagnostics,
                records: flattenedRecords()
            ),
            encoder: encoder,
            fileManager: fileManager,
            paths: paths,
            diagLog: diagLog
        )
    }

    private func flattenedRecords() -> [IdentityRegistryRecord] {
        Self.flattenedRecords(from: recordsBySignature)
    }

    private func ensureCanonicalIDMapping(
        forLegacyIdentityIDs identityIDs: [String]
    ) -> (mapping: [String: MenuExtraCanonicalID], insertedCount: Int) {
        var mapping = [String: MenuExtraCanonicalID]()
        var insertedCount = 0

        for identityID in Set(identityIDs).sorted() {
            guard let record = IdentityRegistryRecord.dormantRecord(forLegacyIdentityID: identityID) else {
                continue
            }

            let signature = Signature(
                bundleID: record.bundleID,
                role: record.role,
                locator: record.locator
            )

            if let existingRecord = recordsBySignature[signature, default: []]
                .first(where: { $0.legacyIdentityID == record.legacyIdentityID })
            {
                mapping[identityID] = existingRecord.canonicalID
                continue
            }

            recordsBySignature[signature, default: []].append(record)
            mapping[identityID] = record.canonicalID
            insertedCount += 1
        }

        return (mapping, insertedCount)
    }

    private static func flattenedRecords(
        from recordsBySignature: [Signature: [IdentityRegistryRecord]]
    ) -> [IdentityRegistryRecord] {
        recordsBySignature.values
            .flatMap { $0 }
            .sorted { lhs, rhs in
                if lhs.bundleID != rhs.bundleID {
                    return lhs.bundleID < rhs.bundleID
                }
                if lhs.role != rhs.role {
                    return lhs.role < rhs.role
                }
                if lhs.locator != rhs.locator {
                    return lhs.locator < rhs.locator
                }
                return lhs.slot < rhs.slot
            }
    }

    private static func persist(
        snapshot: IdentityRegistrySnapshot,
        encoder: JSONEncoder,
        fileManager: FileManager,
        paths: ThawPersistencePaths,
        diagLog: DiagLog
    ) {
        do {
            try ensurePersistenceDirectories(fileManager: fileManager, paths: paths)
            let envelope = PersistentEnvelope(schemaVersion: 3, payload: snapshot)
            let data = try encoder.encode(envelope)
            try data.write(to: paths.identityRegistryV3URL, options: .atomic)
        } catch {
            diagLog.error("Failed to persist identity registry: \(error)")
        }
    }

    private static func ensurePersistenceDirectories(
        fileManager: FileManager,
        paths: ThawPersistencePaths
    ) throws {
        if !fileManager.fileExists(atPath: paths.rootDirectory.path) {
            try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: paths.runtimeDirectory.path) {
            try fileManager.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        }
    }

    private func resolveGroup(
        signature: Signature,
        candidates: [IndexedCandidate],
        previousRecords: [IdentityRegistryRecord]
    ) -> GroupResolution {
        let sortedCandidates = candidates.sorted { lhs, rhs in
            compare(lhs.candidate.frame, rhs.candidate.frame)
        }
        var availableRecords = previousRecords
        var resolvedCandidates = [IndexedResolvedCandidate]()
        var updatedRecords = [IdentityRegistryRecord]()
        var ambiguousMatchCount = 0
        var provisionalPromotionCount = 0
        var confidenceDemotionCount = 0
        var createdRecordCount = 0

        for indexedCandidate in sortedCandidates {
            let match = bestMatchingRecord(for: indexedCandidate.candidate, in: availableRecords)
            let matchedRecord = match.matchedIndex.map { availableRecords[$0] }

            let confidence = confidence(
                for: indexedCandidate.candidate,
                match: match,
                existingRecord: matchedRecord,
                groupCandidateCount: sortedCandidates.count
            )
            if confidence == .ambiguous {
                ambiguousMatchCount += 1
            }

            let record: IdentityRegistryRecord
            let previousConfidence: IdentityMatchConfidence?
            if let matchedIndex = match.matchedIndex,
               confidence != .ambiguous {
                record = availableRecords.remove(at: matchedIndex)
                previousConfidence = record.confidence
            } else {
                let stableKey = stableKey(
                    bundleID: signature.bundleID,
                    role: signature.role,
                    locator: signature.locator,
                    slot: indexedCandidate.candidate.slotIndex
                )
                record = IdentityRegistryRecord(
                    canonicalID: .generated(),
                    bundleID: signature.bundleID,
                    role: signature.role,
                    locator: signature.locator,
                    slot: indexedCandidate.candidate.slotIndex,
                    stableKey: stableKey,
                    normalizedTitle: indexedCandidate.candidate.normalizedTitle,
                    axIdentifier: indexedCandidate.candidate.axIdentifier,
                    slotSignature: indexedCandidate.candidate.slotSignature,
                    lastDisplayUUID: indexedCandidate.candidate.displayUUID,
                    lastFrame: indexedCandidate.candidate.frame.map(IdentityRegistryFrame.init),
                    confidence: indexedCandidate.candidate.axIdentifier == nil ? .ambiguous : .exact,
                    consistencyCount: 0,
                    isDormant: false
                )
                previousConfidence = nil
                createdRecordCount += 1
            }
            var updatedRecord = record
            let nextConsistencyCount = matchedRecord == nil ? 1 : max(record.consistencyCount, 0) + 1
            updatedRecord.normalizedTitle = indexedCandidate.candidate.normalizedTitle
            updatedRecord.axIdentifier = indexedCandidate.candidate.axIdentifier
            updatedRecord.slotSignature = indexedCandidate.candidate.slotSignature
            updatedRecord.lastDisplayUUID = indexedCandidate.candidate.displayUUID
            updatedRecord.lastFrame = indexedCandidate.candidate.frame.map(IdentityRegistryFrame.init)
            updatedRecord.confidence = confidence
            updatedRecord.consistencyCount = nextConsistencyCount
            updatedRecord.isDormant = false

            if previousConfidence == .provisional,
               confidence == .high,
               nextConsistencyCount >= IdentityRegistryThresholds.provisionalPromotionObservationCount {
                provisionalPromotionCount += 1
            }
            if let previousConfidence,
               confidenceRank(previousConfidence) > confidenceRank(confidence) {
                confidenceDemotionCount += 1
            }

            let resolvedIdentity = MenuExtraIdentity.make(
                bundleID: updatedRecord.bundleID,
                title: indexedCandidate.candidate.title,
                role: updatedRecord.role,
                stableKey: updatedRecord.stableKey
            )

            updatedRecords.append(updatedRecord)
            resolvedCandidates.append(
                IndexedResolvedCandidate(
                    index: indexedCandidate.index,
                    candidate: CanonicalizedMenuExtraCandidate(
                        canonicalID: updatedRecord.canonicalID,
                        source: indexedCandidate.candidate,
                        identity: resolvedIdentity,
                        confidence: confidence
                    )
                )
            )
        }

        updatedRecords.append(contentsOf: availableRecords.map { record in
            var updated = record
            updated.isDormant = true
            return updated
        })
        updatedRecords.sort { lhs, rhs in
            if lhs.slot != rhs.slot {
                return lhs.slot < rhs.slot
            }
            return compare(lhs.lastFrame?.cgRect, rhs.lastFrame?.cgRect)
        }

        let churnCount = min(
            createdRecordCount,
            availableRecords.filter { !$0.isDormant }.count
        )
        let diagnosticsDelta = IdentityRegistryDiagnostics(
            identityChurnCount: churnCount,
            canonicalReassignmentCount: canonicalReassignmentViolations(in: updatedRecords),
            ambiguousMatchCount: ambiguousMatchCount,
            provisionalPromotionCount: provisionalPromotionCount,
            shadowObservationCount: 0
        )

        return GroupResolution(
            resolvedCandidates: resolvedCandidates,
            updatedRecords: updatedRecords,
            diagnosticsDelta: diagnosticsDelta,
            confidenceDemotionCount: confidenceDemotionCount
        )
    }

    private func canonicalReassignmentViolations(in records: [IdentityRegistryRecord]) -> Int {
        Dictionary(grouping: records, by: \.canonicalID)
            .values
            .reduce(into: 0) { count, groupedRecords in
                let legacyIdentityIDs = Set(groupedRecords.map(\.legacyIdentityID))
                count += max(legacyIdentityIDs.count - 1, 0)
            }
    }

    private func signature(for indexedCandidate: IndexedCandidate) -> Signature {
        let candidate = indexedCandidate.candidate
        return Signature(
            bundleID: candidate.bundleIdentifier,
            role: candidate.rawRole,
            locator: candidate.axIdentifier ?? candidate.normalizedTitle
        )
    }

    private func bestMatchingRecord(
        for candidate: DiscoveredMenuExtraCandidate,
        in records: [IdentityRegistryRecord]
    ) -> MatchResult {
        guard !records.isEmpty else {
            return MatchResult(matchedIndex: nil, bestScore: nil, runnerUpScore: nil)
        }

        let scoredRecords = records.enumerated().map { index, record in
            (index, score(candidate, against: record))
        }.sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return records[lhs.0].slot < records[rhs.0].slot
            }
            return lhs.1 < rhs.1
        }

        let best = scoredRecords.first
        let runnerUp = scoredRecords.dropFirst().first

        return MatchResult(
            matchedIndex: best?.0,
            bestScore: best?.1,
            runnerUpScore: runnerUp?.1
        )
    }

    private func confidence(
        for candidate: DiscoveredMenuExtraCandidate,
        match: MatchResult,
        existingRecord: IdentityRegistryRecord?,
        groupCandidateCount: Int
    ) -> IdentityMatchConfidence {
        if candidate.axIdentifier != nil {
            return .exact
        }

        guard let bestScore = match.bestScore else {
            return groupCandidateCount == 1 ? .provisional : .ambiguous
        }

        let margin = (match.runnerUpScore ?? CGFloat.greatestFiniteMagnitude) - bestScore
        if bestScore <= IdentityRegistryThresholds.autoBindMaximumScore,
           margin >= IdentityRegistryThresholds.minimumWinnerMargin {
            let nextConsistencyCount = (existingRecord?.consistencyCount ?? 0) + 1
            return nextConsistencyCount >= IdentityRegistryThresholds.provisionalPromotionObservationCount
                ? .high
                : .provisional
        }

        if bestScore <= IdentityRegistryThresholds.provisionalMaximumScore {
            return .provisional
        }

        return .ambiguous
    }

    private func score(_ candidate: DiscoveredMenuExtraCandidate, against record: IdentityRegistryRecord) -> CGFloat {
        let axIdentifierPenalty: CGFloat =
            if let candidateAXIdentifier = candidate.axIdentifier {
                candidateAXIdentifier == record.axIdentifier
                    ? 0
                    : IdentityRegistryThresholds.axIdentifierMismatchPenalty
            } else {
                0
            }

        let displayPenalty: CGFloat =
            if let candidateDisplayUUID = candidate.displayUUID,
               let recordDisplayUUID = record.lastDisplayUUID,
               candidateDisplayUUID != recordDisplayUUID {
                IdentityRegistryThresholds.displayMismatchPenalty
            } else {
                0
            }

        let slotPenalty: CGFloat =
            candidate.slotSignature == record.slotSignature
                ? 0
                : IdentityRegistryThresholds.slotMismatchPenalty

        let frameDistance: CGFloat =
            if let candidateFrame = candidate.frame,
               let recordFrame = record.lastFrame?.cgRect {
                max(
                    0,
                    abs(candidateFrame.midX - recordFrame.midX) +
                        abs(candidateFrame.midY - recordFrame.midY) -
                        IdentityRegistryThresholds.frameDistanceTolerance
                )
            } else {
                CGFloat(abs(candidate.slotIndex - record.slot)) * 10
            }

        return axIdentifierPenalty + displayPenalty + slotPenalty + frameDistance
    }

    private func confidenceRank(_ confidence: IdentityMatchConfidence) -> Int {
        switch confidence {
        case .ambiguous:
            0
        case .provisional:
            1
        case .high:
            2
        case .exact:
            3
        }
    }

    private func compare(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        let leftFrame = lhs ?? .zero
        let rightFrame = rhs ?? .zero

        if leftFrame.minY != rightFrame.minY {
            return leftFrame.minY < rightFrame.minY
        }
        return leftFrame.minX < rightFrame.minX
    }

    private func stableKey(
        bundleID: String,
        role: String,
        locator: String,
        slot: Int
    ) -> String {
        MenuExtraIdentity.make(
            bundleID: bundleID,
            title: locator,
            role: role,
            stableKeyBasis: [bundleID, role, locator, String(slot)].joined(separator: "|")
        ).stableKey
    }
}
