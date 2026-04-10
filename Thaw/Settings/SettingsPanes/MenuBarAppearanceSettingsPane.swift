//
//  MenuBarAppearanceSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarAppearanceSettingsPane: View {
    @ObservedObject var appearanceManager: MenuBarAppearanceManager
    @ObservedObject var adapter: MenuBarAppearanceEditorAdapter

    var body: some View {
        MenuBarAppearanceEditor(
            adapter: adapter,
            appearanceManager: appearanceManager,
            location: .settings,
            onDone: nil
        )
    }
}
