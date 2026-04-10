//
//  ProfileLayoutV3.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

struct LayoutStateV3: Codable, Hashable, Sendable {
    var groupsByCanonicalID: [String: VirtualGroup]
    var orderedCanonicalIDsByGroup: [VirtualGroup: [String]]
    var aliasesByCanonicalID: [String: String]
    var dormantIDs: Set<String>

    static let empty = LayoutStateV3(
        groupsByCanonicalID: [:],
        orderedCanonicalIDsByGroup: [:],
        aliasesByCanonicalID: [:],
        dormantIDs: []
    )

    init(
        groupsByCanonicalID: [String: VirtualGroup],
        orderedCanonicalIDsByGroup: [VirtualGroup: [String]],
        aliasesByCanonicalID: [String: String],
        dormantIDs: Set<String> = []
    ) {
        self.groupsByCanonicalID = groupsByCanonicalID
        self.orderedCanonicalIDsByGroup = orderedCanonicalIDsByGroup
        self.aliasesByCanonicalID = aliasesByCanonicalID
        self.dormantIDs = dormantIDs
    }
}

struct ProfileLayoutV3: Codable, Hashable, Sendable {
    var defaultLayout: LayoutStateV3

    static let empty = ProfileLayoutV3(defaultLayout: .empty)

    init(defaultLayout: LayoutStateV3 = .empty) {
        self.defaultLayout = defaultLayout
    }

    var groupsByCanonicalID: [String: VirtualGroup] {
        get { defaultLayout.groupsByCanonicalID }
        set { defaultLayout.groupsByCanonicalID = newValue }
    }

    var orderedCanonicalIDsByGroup: [VirtualGroup: [String]] {
        get { defaultLayout.orderedCanonicalIDsByGroup }
        set { defaultLayout.orderedCanonicalIDsByGroup = newValue }
    }

    var customNamesByCanonicalID: [String: String] {
        get { defaultLayout.aliasesByCanonicalID }
        set { defaultLayout.aliasesByCanonicalID = newValue }
    }

    var dormantIDs: Set<String> {
        get { defaultLayout.dormantIDs }
        set { defaultLayout.dormantIDs = newValue }
    }

    var referencedCanonicalIDs: [String] {
        let orderedIDs = orderedCanonicalIDsByGroup.values.flatMap { $0 }
        let customNameIDs = customNamesByCanonicalID.keys
        return Array(
            Set(groupsByCanonicalID.keys)
                .union(orderedIDs)
                .union(customNameIDs)
                .union(dormantIDs)
        ).sorted()
    }

    var legacyReferencedIDs: Set<String> {
        Set(referencedCanonicalIDs.filter { !MenuExtraCanonicalID.isOpaquePersistentIdentifier($0) })
    }

    var requiresCanonicalIDUpgrade: Bool {
        !legacyReferencedIDs.isEmpty
    }

    func canonicalized(using mapping: [String: MenuExtraCanonicalID]) -> ProfileLayoutV3 {
        guard !mapping.isEmpty else {
            return self
        }

        func canonicalKey(for storedID: String) -> String {
            mapping[storedID]?.rawValue ?? storedID
        }

        let remappedGroups = groupsByCanonicalID.reduce(into: [String: VirtualGroup]()) { result, entry in
            result[canonicalKey(for: entry.key)] = entry.value
        }
        let remappedAliases = customNamesByCanonicalID.reduce(into: [String: String]()) { result, entry in
            result[canonicalKey(for: entry.key)] = entry.value
        }
        let remappedOrder = orderedCanonicalIDsByGroup.reduce(into: [VirtualGroup: [String]]()) { result, entry in
            var seen = Set<String>()
            result[entry.key] = entry.value.compactMap { storedID in
                let canonicalID = canonicalKey(for: storedID)
                return seen.insert(canonicalID).inserted ? canonicalID : nil
            }
        }
        let remappedDormantIDs = Set(dormantIDs.map(canonicalKey(for:)))

        return ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: remappedGroups,
                orderedCanonicalIDsByGroup: remappedOrder,
                aliasesByCanonicalID: remappedAliases,
                dormantIDs: remappedDormantIDs
            )
        )
    }
}
