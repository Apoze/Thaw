//
//  HotkeysSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct HotkeysSettingsPane: View {
    @ObservedObject var settings: HotkeysSettings
    @ObservedObject var profileManager: ProfileManager

    var body: some View {
        IceForm {
            IceSection("Thaw Surfaces") {
                hotkeyRecorder(forAction: .togglePanel)
                hotkeyRecorder(forAction: .toggleArchive)
            }
            IceSection("Launcher") {
                hotkeyRecorder(forAction: .searchLauncher)
            }
            if !profileManager.profiles.isEmpty {
                IceSection("Profiles") {
                    ForEach(profileManager.profiles) { meta in
                        profileHotkeyRecorder(for: meta)
                    }
                }
            }
            IceSection("Other") {
                hotkeyRecorder(forAction: .togglePrimarySurface)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .togglePanel:
                    Text("Toggle the Panel surface")
                case .toggleArchive:
                    Text("Toggle the Archive surface")
                case .searchLauncher:
                    Text("Search menu extras")
                case .togglePrimarySurface:
                    Text("Toggle the primary \(Constants.displayName) surface")
                case .profileApply:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func profileHotkeyRecorder(for meta: ProfileMetadata) -> some View {
        if let hotkey = profileManager.profileHotkeys[meta.id] {
            HotkeyRecorder(hotkey: hotkey) {
                Text(meta.name)
            }
        }
    }
}
