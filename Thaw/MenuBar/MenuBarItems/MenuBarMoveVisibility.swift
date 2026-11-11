//
//  MenuBarMoveVisibility.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Owns temporary visibility overrides for complete move transactions.
@MainActor
final class MenuBarMoveVisibility {
    static let shared = MenuBarMoveVisibility()

    private let setOverride: (CGDirectDisplayID, Bool) -> Bool
    private var holders: [CGDirectDisplayID: Int] = [:]

    init(setOverride: @escaping (CGDirectDisplayID, Bool) -> Bool = {
        Bridging.setMenuBarVisibilityOverride(on: $0, enabled: $1)
    }) {
        self.setOverride = setOverride
    }

    /// The returned release is idempotent; nested moves retain the outer hold.
    func acquire(on displayID: CGDirectDisplayID) -> (() -> Void)? {
        if holders[displayID] == nil, !setOverride(displayID, true) { return nil }
        holders[displayID, default: 0] += 1
        var released = false
        return { [self] in
            guard !released else { return }
            released = true
            let remaining = (holders[displayID] ?? 1) - 1
            if remaining == 0 {
                holders.removeValue(forKey: displayID)
                _ = setOverride(displayID, false)
            } else {
                holders[displayID] = remaining
            }
        }
    }

    nonisolated struct Settling {
        private var previous: [CGRect] = []
        private var stableSamples = 0

        mutating func observe(source: CGRect, target: CGRect, displayBounds: CGRect) -> Bool {
            let frames = [source, target]
            let revealed = frames.allSatisfy {
                !$0.isEmpty && !$0.isInfinite && abs($0.minY - displayBounds.minY) <= 0.5
            }
            stableSamples = revealed && frames == previous ? stableSamples + 1 : 0
            previous = frames
            return stableSamples >= 4
        }
    }

    static nonisolated func needsReveal(bounds: CGRect, displayBounds: CGRect) -> Bool {
        MenuBarItem.belongsToDisplay(itemBounds: bounds, displayBounds: displayBounds)
            && bounds.minY < displayBounds.minY
    }
}
