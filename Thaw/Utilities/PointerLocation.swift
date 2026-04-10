//
//  PointerLocation.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

enum PointerLocation {
    /// Returns the pointer location in AppKit's global coordinate space.
    static var appKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }
}
