//
//  MenuBarMoveVisibility.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Keeps automatically hidden menu bar geometry reachable during a move.
@MainActor
final class MenuBarMoveVisibility {
    private let wasVisible: Bool

    init() {
        wasVisible = NSMenu.menuBarVisible()
        NSMenu.setMenuBarVisible(true)
    }

    func restore() {
        NSMenu.setMenuBarVisible(wasVisible)
    }

    static nonisolated func needsReveal(bounds: CGRect, displayBounds: CGRect) -> Bool {
        MenuBarItem.belongsToDisplay(itemBounds: bounds, displayBounds: displayBounds)
            && bounds.midY < displayBounds.minY
    }
}
