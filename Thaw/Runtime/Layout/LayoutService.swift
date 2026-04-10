//
//  LayoutService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

final class LayoutService: ObservableObject {
    struct ReconcileSummary: Sendable {
        let liveDescriptorCount: Int
        let liveGroupCounts: [VirtualGroup: Int]
        let retainedAssignmentCount: Int
        let didChange: Bool

        func liveCount(for group: VirtualGroup) -> Int {
            liveGroupCounts[group, default: 0]
        }
    }

    @Published private(set) var layout = ProfileLayoutV3.empty

    private let diagLog = DiagLog(category: .layout)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager
    private let paths: ThawPersistencePaths

    init(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) {
        self.fileManager = fileManager
        self.paths = paths
        load()
    }

    func load() {
        layout = Self.loadPersistedLayout(
            fileManager: fileManager,
            paths: paths,
            decoder: decoder,
            diagLog: diagLog
        )
    }

    func snapshot() -> ProfileLayoutV3 {
        layout
    }

    func reconcile(with descriptors: [MenuExtraDescriptor]) -> ReconcileSummary {
        guard !descriptors.isEmpty else {
            return ReconcileSummary(
                liveDescriptorCount: 0,
                liveGroupCounts: [:],
                retainedAssignmentCount: retainedAssignmentCount(in: layout, liveCanonicalIDs: []),
                didChange: false
            )
        }

        var updated = layout
        var didChange = false
        let liveCanonicalIDs = Set(descriptors.map(\.canonicalID.rawValue))

        let unassignedDescriptors = descriptors.filter { storedGroup(for: $0, in: updated) == nil }
        if !unassignedDescriptors.isEmpty {
            for descriptor in unassignedDescriptors {
                updated.groupsByCanonicalID[descriptor.canonicalID.rawValue] = .hidden
            }
            didChange = true
        }

        let reconciledOrder = VirtualGroup.allCases.reduce(into: [VirtualGroup: [String]]()) { result, group in
            let assignedIDs = Set(
                updated.groupsByCanonicalID.compactMap { storedID, assignedGroup in
                    assignedGroup == group ? storedID : nil
                }
            )
            let currentGroupIDs = descriptors
                .filter { resolvedGroup(for: $0, in: updated) == group }
                .map(\.canonicalID.rawValue)
            let preservedOrder = uniqued(
                (updated.orderedCanonicalIDsByGroup[group] ?? []).filter { assignedIDs.contains($0) }
            )
            let appendedIDs = currentGroupIDs.filter { !preservedOrder.contains($0) }
            result[group] = preservedOrder + appendedIDs
        }

        if reconciledOrder != updated.orderedCanonicalIDsByGroup {
            updated.orderedCanonicalIDsByGroup = reconciledOrder
            didChange = true
        }

        let liveGroupCounts = descriptors.reduce(into: [VirtualGroup: Int]()) { result, descriptor in
            let group = resolvedGroup(for: descriptor, in: updated)
            result[group, default: 0] += 1
        }
        let retainedAssignmentCount = retainedAssignmentCount(
            in: updated,
            liveCanonicalIDs: liveCanonicalIDs
        )
        let summary = ReconcileSummary(
            liveDescriptorCount: descriptors.count,
            liveGroupCounts: liveGroupCounts,
            retainedAssignmentCount: retainedAssignmentCount,
            didChange: didChange
        )

        guard didChange else {
            return summary
        }

        layout = updated
        RuntimeMetrics.shared.incrementLayoutMutationCount()
        persist()
        diagLog.info(
            """
            Reconciled layout with \(summary.liveDescriptorCount) live descriptors \
            (\(summary.liveCount(for: .pinned)) pinned, \
            \(summary.liveCount(for: .hidden)) hidden, \
            \(summary.liveCount(for: .archive)) archive, \
            \(summary.retainedAssignmentCount) retained assignments)
            """
        )

        return summary
    }

    func apply(_ profileLayout: ProfileLayoutV3) {
        let previousLayout = layout
        layout = profileLayout
        guard layout != previousLayout else {
            return
        }
        RuntimeMetrics.shared.incrementLayoutMutationCount()
        persist()
    }

    func resetSuggestedLayout(for descriptors: [MenuExtraDescriptor]) {
        let nextLayout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: descriptors.reduce(into: [String: VirtualGroup]()) { result, descriptor in
                    result[descriptor.canonicalID.rawValue] = .hidden
                },
                orderedCanonicalIDsByGroup: [:],
                aliasesByCanonicalID: [:]
            )
        )
        guard nextLayout != layout else {
            return
        }
        layout = nextLayout
        RuntimeMetrics.shared.incrementLayoutMutationCount()
        persist()
    }

    func resolvedGroup(for descriptor: MenuExtraDescriptor) -> VirtualGroup {
        resolvedGroup(for: descriptor, in: layout)
    }

    func customName(for descriptor: MenuExtraDescriptor) -> String? {
        storedCustomName(for: descriptor, in: layout)
    }

    func assign(group: VirtualGroup, to canonicalID: MenuExtraCanonicalID) {
        let canonicalKey = canonicalID.rawValue
        let previousLayout = layout
        layout.groupsByCanonicalID[canonicalKey] = group

        for existingGroup in VirtualGroup.allCases where existingGroup != group {
            layout.orderedCanonicalIDsByGroup[existingGroup]?.removeAll { storedID in
                storedID == canonicalKey
            }
        }

        if layout.orderedCanonicalIDsByGroup[group] == nil {
            layout.orderedCanonicalIDsByGroup[group] = []
        }
        if !(layout.orderedCanonicalIDsByGroup[group] ?? []).contains(canonicalKey) {
            layout.orderedCanonicalIDsByGroup[group, default: []].append(canonicalKey)
        }

        guard layout != previousLayout else {
            return
        }
        RuntimeMetrics.shared.incrementLayoutMutationCount()
        persist()
    }

    func rename(canonicalID: MenuExtraCanonicalID, to customName: String?) {
        let canonicalKey = canonicalID.rawValue
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let previousLayout = layout

        if trimmed.isEmpty {
            layout.customNamesByCanonicalID.removeValue(forKey: canonicalKey)
        } else {
            layout.customNamesByCanonicalID[canonicalKey] = trimmed
        }

        guard layout != previousLayout else {
            return
        }
        RuntimeMetrics.shared.incrementLayoutMutationCount()
        persist()
    }

    func setOrder(for group: VirtualGroup, canonicalIDs: [MenuExtraCanonicalID]) {
        let nextOrder = canonicalIDs.map(\.rawValue)
        guard layout.orderedCanonicalIDsByGroup[group] != nextOrder else {
            return
        }
        layout.orderedCanonicalIDsByGroup[group] = nextOrder
        RuntimeMetrics.shared.incrementLayoutMutationCount()
        persist()
    }

    func orderedDescriptors(from descriptors: [MenuExtraDescriptor]) -> [MenuExtraDescriptor] {
        let decorated = descriptors.map { descriptor -> MenuExtraDescriptor in
            var copy = descriptor
            copy.group = resolvedGroup(for: descriptor)
            copy.customName = customName(for: descriptor)
            return copy
        }

        return VirtualGroup.allCases.flatMap { group in
            let groupItems = decorated.filter { $0.group == group }
            let savedOrder = layout.orderedCanonicalIDsByGroup[group] ?? []

            return groupItems.sorted { lhs, rhs in
                let leftIndex = firstStoredIndex(of: lhs, in: savedOrder)
                let rightIndex = firstStoredIndex(of: rhs, in: savedOrder)
                switch (leftIndex, rightIndex) {
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    if lhs.applicationName != rhs.applicationName {
                        return lhs.applicationName.localizedCaseInsensitiveCompare(rhs.applicationName) == .orderedAscending
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
        }
    }

    private func persist() {
        do {
            try ensurePersistenceDirectories()
            let envelope = PersistentEnvelope(schemaVersion: 3, payload: layout)
            let data = try encoder.encode(envelope)
            try data.write(to: paths.layoutV3URL, options: .atomic)
        } catch {
            diagLog.error("Failed to encode layout state: \(error)")
        }
    }

    private func ensurePersistenceDirectories() throws {
        if !fileManager.fileExists(atPath: paths.rootDirectory.path) {
            try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: paths.runtimeDirectory.path) {
            try fileManager.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        }
    }

    private func storedGroup(
        for descriptor: MenuExtraDescriptor,
        in layout: ProfileLayoutV3
    ) -> VirtualGroup? {
        layout.groupsByCanonicalID[descriptor.canonicalID.rawValue]
    }

    private func resolvedGroup(
        for descriptor: MenuExtraDescriptor,
        in layout: ProfileLayoutV3
    ) -> VirtualGroup {
        storedGroup(for: descriptor, in: layout) ?? .hidden
    }

    private func storedCustomName(
        for descriptor: MenuExtraDescriptor,
        in layout: ProfileLayoutV3
    ) -> String? {
        layout.customNamesByCanonicalID[descriptor.canonicalID.rawValue]
    }

    private func firstStoredIndex(
        of descriptor: MenuExtraDescriptor,
        in savedOrder: [String]
    ) -> Int? {
        savedOrder.firstIndex(of: descriptor.canonicalID.rawValue)
    }

    private func retainedAssignmentCount(
        in layout: ProfileLayoutV3,
        liveCanonicalIDs: Set<String>
    ) -> Int {
        Set(layout.referencedCanonicalIDs).subtracting(liveCanonicalIDs).count
    }

    private func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static func persistedLayoutRequiresCompatibilityMigration(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) -> Bool {
        guard fileManager.fileExists(atPath: paths.layoutV3URL.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: paths.layoutV3URL)
            let decoder = JSONDecoder()
            return persistedLayoutRequiresCompatibilityMigration(data: data, decoder: decoder)
        } catch {
            return false
        }
    }

    @discardableResult
    static func migratePersistedLayoutIfNeeded(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: paths.layoutV3URL.path) else {
            return false
        }

        let decoder = JSONDecoder()
        let data = try Data(contentsOf: paths.layoutV3URL)
        guard persistedLayoutRequiresCompatibilityMigration(data: data, decoder: decoder),
              let decodedLayout = try decodePersistedLayout(data: data, decoder: decoder)
        else {
            return false
        }
        let migratedLayout = IdentityRegistry.canonicalizeLayoutReferences(
            decodedLayout,
            fileManager: fileManager,
            paths: paths
        )

        let encoder = JSONEncoder()
        try persist(
            layout: migratedLayout,
            fileManager: fileManager,
            paths: paths,
            encoder: encoder
        )
        return true
    }

    private static func loadPersistedLayout(
        fileManager: FileManager,
        paths: ThawPersistencePaths,
        decoder: JSONDecoder,
        diagLog: DiagLog
    ) -> ProfileLayoutV3 {
        guard fileManager.fileExists(atPath: paths.layoutV3URL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: paths.layoutV3URL)
            if let layout = try decodePersistedLayout(data: data, decoder: decoder) {
                return layout
            }
            return .empty
        } catch {
            diagLog.error("Failed to decode persisted layout state: \(error)")
            return .empty
        }
    }

    private static func decodePersistedLayout(
        data: Data,
        decoder: JSONDecoder
    ) throws -> ProfileLayoutV3? {
        if let envelope = try? decoder.decode(
            PersistentEnvelope<ProfileLayoutV3>.self,
            from: data
        ) {
            return envelope.payload
        }

        return try ProfileLayoutMigration.decodePersistedLayoutEnvelope(
            from: data,
            using: decoder
        )
    }

    private static func persistedLayoutRequiresCompatibilityMigration(
        data: Data,
        decoder: JSONDecoder
    ) -> Bool {
        if let envelope = try? decoder.decode(
            PersistentEnvelope<ProfileLayoutV3>.self,
            from: data
        ) {
            return envelope.payload.requiresCanonicalIDUpgrade
        }

        return (try? ProfileLayoutMigration.decodePersistedLayoutEnvelope(
            from: data,
            using: decoder
        )) != nil
    }

    private static func persist(
        layout: ProfileLayoutV3,
        fileManager: FileManager,
        paths: ThawPersistencePaths,
        encoder: JSONEncoder
    ) throws {
        if !fileManager.fileExists(atPath: paths.rootDirectory.path) {
            try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: paths.runtimeDirectory.path) {
            try fileManager.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        }

        let envelope = PersistentEnvelope(schemaVersion: 3, payload: layout)
        let data = try encoder.encode(envelope)
        try data.write(to: paths.layoutV3URL, options: .atomic)
    }
}
