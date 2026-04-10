//
//  MenuExtraModels.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CryptoKit
import SwiftUI

enum VirtualGroup: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case pinned
    case hidden
    case archive

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .pinned: "Quick Access"
        case .hidden: "Panel"
        case .archive: "Archive"
        }
    }
}

enum MenuExtraCapability: String, Codable, Hashable, Sendable {
    case axPress
    case openApp
    case unsupported
}

enum ActivationSurface: String, Codable, Hashable, Sendable {
    case quickAccess
    case panel
    case archive
    case search
}

enum ActivationIntent: String, Codable, Hashable, Sendable {
    case automatic
    case primary
    case secondary
}

struct MenuExtraCanonicalID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func generated() -> MenuExtraCanonicalID {
        MenuExtraCanonicalID(rawValue: UUID().uuidString.lowercased())
    }

    static func deterministic(fromStableSeed seed: String) -> MenuExtraCanonicalID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest)
        let uuidBytes = (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            UInt8((bytes[6] & 0x0F) | 0x50),
            bytes[7],
            UInt8((bytes[8] & 0x3F) | 0x80),
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15]
        )

        return MenuExtraCanonicalID(
            rawValue: UUID(uuid: uuidBytes).uuidString.lowercased()
        )
    }

    var description: String {
        rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var isOpaquePersistentIdentifier: Bool {
        UUID(uuidString: rawValue) != nil
    }

    static func isOpaquePersistentIdentifier(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

struct ActivationCommand: Hashable, Sendable {
    let canonicalID: MenuExtraCanonicalID
    let surface: ActivationSurface
    let intent: ActivationIntent

    var followUpInvalidation: DiscoveryInvalidation {
        .activationFollowUp(
            canonicalID: canonicalID,
            surface: surface,
            intent: intent
        )
    }
}

enum ActivationOutcome: Hashable, Sendable {
    case openedUI
    case openedApp
    case unsupported
    case timeout
    case permissionMissing
    case failedRecoverable
    case failedTerminal

    var shouldTriggerFollowUp: Bool {
        self == .openedUI || self == .openedApp
    }

    var panelDisposition: PanelInteractionDisposition {
        switch self {
        case .openedUI, .openedApp:
            .dismiss
        case .unsupported, .timeout, .permissionMissing, .failedRecoverable, .failedTerminal:
            .keepPresented
        }
    }
}

typealias ActivationResult = ActivationOutcome

extension VirtualGroup {
    var activationSurface: ActivationSurface {
        switch self {
        case .pinned: .quickAccess
        case .hidden: .panel
        case .archive: .archive
        }
    }
}

struct MenuExtraIdentity: Codable, Hashable, Identifiable, Sendable {
    let bundleID: String
    let stableKey: String
    let normalizedTitle: String
    let role: String

    var id: String {
        [bundleID, stableKey, role].joined(separator: "::")
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID
        case stableKey = "axPathHash"
        case normalizedTitle
        case role
    }
}

struct MenuExtraDescriptor: Hashable, Identifiable, Sendable {
    let canonicalID: MenuExtraCanonicalID
    let identity: MenuExtraIdentity
    let ownerPID: pid_t
    let bundleIdentifier: String
    let bundleURL: URL?
    let applicationName: String
    let title: String
    let rawRole: String
    let frame: CGRect?
    let displayID: CGDirectDisplayID?
    let displayUUID: String?
    let capability: MenuExtraCapability
    var group: VirtualGroup
    var customName: String?

    var id: String { identity.id }

    var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return title
    }

    var activationLabel: LocalizedStringKey {
        switch capability {
        case .axPress: "Activate"
        case .openApp: "Open App"
        case .unsupported: "Unsupported"
        }
    }

    var isInteractive: Bool {
        capability != .unsupported
    }
}

struct DiscoveredMenuExtraCandidate: Hashable, Sendable {
    let ownerPID: pid_t
    let bundleIdentifier: String
    let bundleURL: URL?
    let applicationName: String
    let title: String
    let normalizedTitle: String
    let rawRole: String
    let axIdentifier: String?
    let slotIndex: Int
    let slotSignature: String
    let frame: CGRect?
    let displayID: CGDirectDisplayID?
    let displayUUID: String?
    let capability: MenuExtraCapability
}

struct DiscoverySnapshot: Hashable, Sendable {
    let descriptors: [MenuExtraDescriptor]
    let generatedAt: Date

    static let empty = DiscoverySnapshot(descriptors: [], generatedAt: .distantPast)
}

extension MenuExtraIdentity {
    static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func make(
        bundleID: String,
        title: String,
        role: String,
        stableKeyBasis: String
    ) -> MenuExtraIdentity {
        let hash = SHA256.hash(data: Data(stableKeyBasis.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return MenuExtraIdentity(
            bundleID: bundleID,
            stableKey: hash,
            normalizedTitle: normalizedTitle(title),
            role: role
        )
    }

    static func make(
        bundleID: String,
        title: String,
        role: String,
        stableKey: String
    ) -> MenuExtraIdentity {
        MenuExtraIdentity(
            bundleID: bundleID,
            stableKey: stableKey,
            normalizedTitle: normalizedTitle(title),
            role: role
        )
    }
}
