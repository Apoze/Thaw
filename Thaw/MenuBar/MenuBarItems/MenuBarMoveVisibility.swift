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
    private var savedPointer: CGPoint?
    private var pointerOwnershipStarted: ContinuousClock.Instant?

    func revealByHovering(targetBounds: CGRect, displayBounds: CGRect) {
        guard savedPointer == nil, let location = MouseHelpers.locationCoreGraphics else { return }
        savedPointer = location
        pointerOwnershipStarted = .now
        let point = Self.revealPoint(targetBounds: targetBounds, displayBounds: displayBounds)
        MouseHelpers.warpCursor(to: point)
        // A warp alone does not always trigger the system's auto-hide reveal.
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    func restore() {
        if let savedPointer, let pointerOwnershipStarted, !MouseHelpers.physicalPointerInputOccurred(since: pointerOwnershipStarted) {
            MouseHelpers.restoreCursorPosition(to: savedPointer)
        }
    }

    static nonisolated func revealPoint(targetBounds: CGRect, displayBounds: CGRect) -> CGPoint {
        // Stay in the right-hand status area, away from the notch and Hot Corners.
        let x = min(max(targetBounds.midX, displayBounds.maxX - 100), displayBounds.maxX - 32)
        return CGPoint(x: x, y: displayBounds.minY + 1)
    }

    static nonisolated func needsReveal(bounds: CGRect, displayBounds: CGRect) -> Bool {
        MenuBarItem.belongsToDisplay(itemBounds: bounds, displayBounds: displayBounds)
            && bounds.midY < displayBounds.minY
    }
}
