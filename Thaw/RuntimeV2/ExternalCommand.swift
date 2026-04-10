//
//  ExternalCommand.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

enum AppCommand: Hashable {
    case toggleGroup(VirtualGroup)
    case toggleThawBar
    case openSearch
    case openSettings
    case checkForUpdates
    case applyProfile(UUID)
}
