//
//  ProfileLayoutMigration.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

struct ProfileLayoutV2: Codable, Hashable, Sendable {
    var groupsByIdentityID: [String: VirtualGroup]
    var orderedIdentityIDsByGroup: [VirtualGroup: [String]]
    var customNamesByIdentityID: [String: String]

    static let empty = ProfileLayoutV2(
        groupsByIdentityID: [:],
        orderedIdentityIDsByGroup: [:],
        customNamesByIdentityID: [:]
    )

    var referencedIdentityIDs: [String] {
        let orderedIDs = orderedIdentityIDsByGroup.values.flatMap { $0 }
        let customNameIDs = customNamesByIdentityID.keys
        return Array(Set(groupsByIdentityID.keys).union(orderedIDs).union(customNameIDs)).sorted()
    }
}

enum ProfileLayoutMigration {
    static func migrate(_ layout: ProfileLayoutV2) -> ProfileLayoutV3 {
        ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: layout.groupsByIdentityID,
                orderedCanonicalIDsByGroup: layout.orderedIdentityIDsByGroup,
                aliasesByCanonicalID: layout.customNamesByIdentityID
            )
        )
    }

    static func legacyCompatibilityLayout(from layout: ProfileLayoutV3) -> ProfileLayoutV2 {
        ProfileLayoutV2(
            groupsByIdentityID: layout.groupsByCanonicalID,
            orderedIdentityIDsByGroup: layout.orderedCanonicalIDsByGroup,
            customNamesByIdentityID: layout.customNamesByCanonicalID
        )
    }

    static func decodePersistedLayoutEnvelope(
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> ProfileLayoutV3? {
        guard let envelope = try? decoder.decode(PersistentEnvelope<ProfileLayoutV2>.self, from: data) else {
            return nil
        }
        return migrate(envelope.payload)
    }

    static func decodeMenuBarLayoutSnapshot(from decoder: Decoder) throws -> ProfileLayoutV3 {
        let legacySnapshot = try LegacyMenuBarLayoutSnapshot(from: decoder)

        if let virtualLayout = legacySnapshot.virtualLayout {
            return migrate(virtualLayout)
        }

        let groupsByIdentityID = legacySnapshot.itemSectionMap.reduce(into: [String: VirtualGroup]()) { result, entry in
            let group: VirtualGroup = switch entry.value {
            case "visible":
                .pinned
            case "alwaysHidden":
                .archive
            default:
                .hidden
            }
            result[entry.key] = group
        }

        let orderedIdentityIDsByGroup = legacySnapshot.itemOrder.reduce(into: [VirtualGroup: [String]]()) { result, entry in
            let group: VirtualGroup = switch entry.key {
            case "visible":
                .pinned
            case "alwaysHidden":
                .archive
            default:
                .hidden
            }
            result[group] = entry.value
        }

        return ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: groupsByIdentityID,
                orderedCanonicalIDsByGroup: orderedIdentityIDsByGroup,
                aliasesByCanonicalID: legacySnapshot.customNames
            )
        )
    }

    private struct LegacyMenuBarLayoutSnapshot: Decodable {
        let virtualLayout: ProfileLayoutV2?
        let customNames: [String: String]
        let itemSectionMap: [String: String]
        let itemOrder: [String: [String]]

        private enum CodingKeys: String, CodingKey {
            case virtualLayout
            case customNames
            case itemSectionMap
            case itemOrder
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            virtualLayout = try container.decodeIfPresent(ProfileLayoutV2.self, forKey: .virtualLayout)
            customNames = try container.decodeIfPresent([String: String].self, forKey: .customNames) ?? [:]
            itemSectionMap = try container.decodeIfPresent([String: String].self, forKey: .itemSectionMap) ?? [:]
            itemOrder = try container.decodeIfPresent([String: [String]].self, forKey: .itemOrder) ?? [:]
        }
    }
}
