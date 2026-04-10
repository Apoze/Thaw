//
//  MenuBarAverageColorInfo.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Lightweight appearance snapshot for Thaw-owned menu bar surfaces.
struct MenuBarAverageColorInfo {
    let color: CGColor

    var isBright: Bool {
        (color.brightness ?? 0) > 0.67
    }
}
