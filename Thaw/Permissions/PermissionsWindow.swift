//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct PermissionsWindow: Scene {
    let adapter: PermissionsWindowAdapter

    var body: some Scene {
        IceWindow(
            id: .permissions,
            installWindowCommands: { openWindow, dismissWindow in
                adapter.performSetup(windowCommands: .init(
                    openWindow: { openWindow($0) },
                    dismissWindow: { dismissWindow($0) }
                ))
            },
            content: {
                PermissionsView(
                    manager: adapter.manager,
                    adapter: adapter.flowAdapter
                )
                    .onWindowChange { window in
                        adapter.bindWindow(window)
                        guard let window else {
                            return
                        }
                        window.standardWindowButton(.closeButton)?.isHidden = true
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                        window.standardWindowButton(.zoomButton)?.isHidden = true
                        if let contentView = window.contentView {
                            withMutableCopy(of: contentView.safeAreaInsets) { insets in
                                insets.bottom = -insets.bottom
                                insets.left = -insets.left
                                insets.right = -insets.right
                                insets.top = -insets.top
                                contentView.additionalSafeAreaInsets = insets
                            }
                        }
                    }
            }
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
