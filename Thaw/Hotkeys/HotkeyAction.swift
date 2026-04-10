//
//  HotkeyAction.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

enum HotkeyAction: String, Codable, CaseIterable {
    case togglePanel = "TogglePanel"
    case toggleArchive = "ToggleArchive"
    case searchLauncher = "SearchLauncher"
    case togglePrimarySurface = "TogglePrimarySurface"

    /// Used by profile hotkeys — action is handled externally.
    case profileApply = "ProfileApply"

    /// Actions that should appear in the Hotkeys settings pane.
    static var settingsActions: [HotkeyAction] {
        allCases.filter { $0 != .profileApply }
    }
}
