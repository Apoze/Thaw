//
//  CommandRouter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class CommandRouter {
    struct Dependencies {
        let toggleGroup: (VirtualGroup, Bool) -> Void
        let togglePrimarySurface: (Bool) -> Void
        let openSearch: () -> Void
        let openSettings: () -> Void
        let checkForUpdates: () -> Void
        let applyProfile: (UUID) -> Void
    }

    private let diagLog = DiagLog(category: "CommandRouter")
    private var dependencies: Dependencies?

    func performSetup(with dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func route(url: URL) {
        guard let command = command(for: url) else {
            diagLog.warning("Received unrecognized thaw:// URL: \(url.absoluteString)")
            return
        }
        route(command, source: "url:\(url.host?.lowercased() ?? "unknown")")
    }

    func route(hotkeyAction: HotkeyAction) {
        guard let command = command(for: hotkeyAction) else {
            return
        }
        route(command, source: "hotkey:\(hotkeyAction.rawValue)")
    }

    func route(_ command: AppCommand, source: String) {
        guard let dependencies else {
            return
        }

        switch command {
        case let .toggleGroup(group):
            dependencies.toggleGroup(group, source.hasPrefix("hotkey:"))
        case .toggleThawBar:
            dependencies.togglePrimarySurface(source.hasPrefix("hotkey:"))
        case .openSearch:
            dependencies.openSearch()
        case .openSettings:
            dependencies.openSettings()
        case .checkForUpdates:
            dependencies.checkForUpdates()
        case let .applyProfile(profileID):
            dependencies.applyProfile(profileID)
        }
    }

    func command(for url: URL) -> AppCommand? {
        guard url.scheme?.lowercased() == "thaw" else {
            return nil
        }

        switch url.host?.lowercased() ?? "" {
        case "panel":
            return .toggleGroup(.hidden)
        case "toggle-hidden":
            return .toggleGroup(.hidden)
        case "archive":
            return .toggleGroup(.archive)
        case "toggle-always-hidden":
            return .toggleGroup(.archive)
        case "surface":
            return .toggleThawBar
        case "search":
            return .openSearch
        case "settings":
            return .openSettings
        default:
            return nil
        }
    }

    func command(for action: HotkeyAction) -> AppCommand? {
        switch action {
        case .togglePanel:
            return .toggleGroup(.hidden)
        case .toggleArchive:
            return .toggleGroup(.archive)
        case .searchLauncher:
            return .openSearch
        case .togglePrimarySurface:
            return .toggleThawBar
        case .profileApply:
            return nil
        }
    }
}
