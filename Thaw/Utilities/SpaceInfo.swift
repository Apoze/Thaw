//
//  SpaceInfo.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Information for a desktop space.
struct SpaceInfo: Hashable {
    /// The space's identifier.
    let spaceID: Int

    /// A Boolean value that indicates whether the space is fullscreen.
    let isFullscreen: Bool

    /// Creates a space with the given identifier.
    ///
    /// - Parameter spaceID: An identifier for a space.
    init(spaceID: Int = 0, isFullscreen: Bool) {
        self.spaceID = spaceID
        self.isFullscreen = isFullscreen
    }

    /// Returns the active space.
    static func activeSpace() -> SpaceInfo {
        guard NSApp != nil else {
            return SpaceInfo(isFullscreen: false)
        }

        return SpaceInfo(isFullscreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen))
    }

    /// Returns the current space on the given display.
    ///
    /// - Parameter displayID: An identifier for a display.
    static func currentSpace(for displayID: CGDirectDisplayID) -> SpaceInfo? {
        _ = displayID
        return activeSpace()
    }
}
