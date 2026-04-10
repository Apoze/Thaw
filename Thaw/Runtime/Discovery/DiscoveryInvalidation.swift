//
//  DiscoveryInvalidation.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

enum DiscoveryConsistencyFollowUpTrigger: String, Codable, Hashable, Sendable, CustomStringConvertible {
    case workspaceDidLaunch
    case workspaceDidTerminate
    case icebarActivateLeft
    case icebarActivateRight

    var description: String {
        rawValue
    }
}

enum DiscoveryInvalidation: Hashable, Sendable, CustomStringConvertible {
    case startup
    case appLaunched(bundleID: String?, processIdentifier: pid_t)
    case appTerminated(bundleID: String?, processIdentifier: pid_t)
    case appActivated(bundleID: String?, processIdentifier: pid_t)
    case workspaceActivationSettled
    case axStructureChanged(bundleID: String?, processIdentifier: pid_t)
    case observationRecoveryRequired
    case permissionChanged
    case layoutEditorPresented
    case layoutReset
    case panelPreparation
    case panelPresented(displayUUID: String?)
    case profileApplied
    case activationFollowUp(
        canonicalID: MenuExtraCanonicalID,
        surface: ActivationSurface,
        intent: ActivationIntent
    )
    case displayConfigurationChanged
    case consistencyFollowUp(trigger: DiscoveryConsistencyFollowUpTrigger)

    var description: String {
        switch self {
        case .startup:
            "startup"
        case .appLaunched(let bundleID, let processIdentifier):
            "appLaunched[\(bundleID ?? "unknown")#\(processIdentifier)]"
        case .appTerminated(let bundleID, let processIdentifier):
            "appTerminated[\(bundleID ?? "unknown")#\(processIdentifier)]"
        case .appActivated(let bundleID, let processIdentifier):
            "appActivated[\(bundleID ?? "unknown")#\(processIdentifier)]"
        case .workspaceActivationSettled:
            "workspaceActivationSettled"
        case .axStructureChanged(let bundleID, let processIdentifier):
            "axStructureChanged[\(bundleID ?? "unknown")#\(processIdentifier)]"
        case .observationRecoveryRequired:
            "observationRecoveryRequired"
        case .permissionChanged:
            "permissionChanged"
        case .layoutEditorPresented:
            "layoutEditorPresented"
        case .layoutReset:
            "layoutReset"
        case .panelPreparation:
            "panelPreparation"
        case .panelPresented(let displayUUID):
            "panelPresented[\(displayUUID ?? "unknown-display")]"
        case .profileApplied:
            "profileApplied"
        case .activationFollowUp(let canonicalID, let surface, let intent):
            "activationFollowUp[\(surface.rawValue):\(intent.rawValue):\(canonicalID)]"
        case .displayConfigurationChanged:
            "displayConfigurationChanged"
        case .consistencyFollowUp(let trigger):
            "consistencyFollowUp[\(trigger)]"
        }
    }

    var consistencyFollowUpTrigger: DiscoveryConsistencyFollowUpTrigger? {
        switch self {
        case .appLaunched:
            .workspaceDidLaunch
        case .appTerminated:
            .workspaceDidTerminate
        case .activationFollowUp(_, let surface, let intent):
            switch (surface, intent) {
            case (.quickAccess, .primary):
                .icebarActivateLeft
            case (.quickAccess, .secondary):
                .icebarActivateRight
            default:
                nil
            }
        case .consistencyFollowUp(let trigger):
            trigger
        default:
            nil
        }
    }

    var workspaceActivationSignature: String? {
        switch self {
        case .appActivated(let bundleID, let processIdentifier):
            let bundleID = bundleID ?? "unknown-bundle"
            return "\(bundleID)#\(processIdentifier)"
        default:
            return nil
        }
    }
}
