//
//  MenuBarItemDisplayLaneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Menu bar display lanes")
struct MenuBarItemDisplayLaneTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("Automatically hidden menu icons remain on their display")
    func autoHidden() {
        let bounds = CGRect(x: -4210, y: -28.5, width: 34, height: 24)
        #expect(MenuBarItem.belongsToDisplay(itemBounds: bounds, displayBounds: display))
    }

    @Test("Horizontal hiding does not discard an icon")
    func horizontallyHidden() {
        #expect(MenuBarItem.belongsToDisplay(itemBounds: CGRect(x: -8000, y: 0, width: 34, height: 24), displayBounds: display))
        #expect(MenuBarItem.belongsToDisplay(itemBounds: CGRect(x: 100, y: 0, width: 34, height: 24), displayBounds: display))
    }

    @Test("An unrelated vertical display lane is rejected")
    func otherDisplay() {
        #expect(!MenuBarItem.belongsToDisplay(itemBounds: CGRect(x: 100, y: -500, width: 34, height: 24), displayBounds: display))
        #expect(!MenuBarItem.belongsToDisplay(itemBounds: CGRect(x: 100, y: 1000, width: 34, height: 24), displayBounds: display))
    }

    @Test("A display above the main display uses its own origin")
    func negativeOrigin() {
        let upper = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(MenuBarItem.belongsToDisplay(itemBounds: CGRect(x: -4000, y: -1108.5, width: 34, height: 24), displayBounds: upper))
    }

    @Test("Reveal only a menu bar parked above the selected display")
    func revealHiddenBar() {
        #expect(MenuBarMoveVisibility.needsReveal(bounds: CGRect(x: 100, y: -28.5, width: 34, height: 24), displayBounds: display))
        #expect(!MenuBarMoveVisibility.needsReveal(bounds: CGRect(x: 100, y: 0, width: 34, height: 24), displayBounds: display))
        #expect(!MenuBarMoveVisibility.needsReveal(bounds: CGRect(x: 100, y: -500, width: 34, height: 24), displayBounds: display))
        #expect(!MenuBarMoveVisibility.needsReveal(bounds: .null, displayBounds: display))
    }

    @Test("Layout preview centers captured glyphs without stretching them")
    func centeredPreview() {
        let bounds = CGRect(x: 0, y: 0, width: 34, height: 33)
        #expect(LayoutBarItemView.centeredImageRect(size: CGSize(width: 34, height: 16), bounds: bounds) == CGRect(x: 0, y: 8.5, width: 34, height: 16))
        #expect(LayoutBarItemView.centeredImageRect(size: CGSize(width: 68, height: 32), bounds: bounds) == CGRect(x: 0, y: 8.5, width: 34, height: 16))
        #expect(LayoutBarItemView.centeredImageRect(size: .zero, bounds: bounds) == .zero)
    }

    @Test("Truncated captures never replace full-height menu icons")
    func clippedCapture() {
        let bounds = CGRect(x: 100, y: -33, width: 34, height: 33)
        #expect(Bridging.captureHasFullHeight(pixelHeight: 66, bounds: bounds, scale: 2))
        #expect(!Bridging.captureHasFullHeight(pixelHeight: 32, bounds: bounds, scale: 2))
        #expect(!Bridging.captureHasFullHeight(pixelHeight: 66, bounds: .null, scale: 2))
    }

    @Test("Invalid geometry is not accepted")
    func invalidBounds() {
        #expect(!MenuBarItem.belongsToDisplay(itemBounds: .null, displayBounds: display))
        #expect(!MenuBarItem.belongsToDisplay(itemBounds: .infinite, displayBounds: display))
        #expect(!MenuBarItem.belongsToDisplay(itemBounds: .zero, displayBounds: display))
        #expect(!MenuBarItem.belongsToDisplay(itemBounds: CGRect(x: 0, y: 0, width: 34, height: 24), displayBounds: .null))
    }
    @Test("Display-bounded capture rejects concealed and partially retracted icons")
    func captureRequiresTheCompleteWindowOnTheSelectedDisplay() {
        #expect(MenuBarItemImageCache.canCaptureOnDisplay(bounds: CGRect(x: 999, y: 0, width: 34, height: 33), displayBounds: display))
        #expect(!MenuBarItemImageCache.canCaptureOnDisplay(bounds: CGRect(x: 999, y: -8, width: 34, height: 33), displayBounds: display))
        #expect(!MenuBarItemImageCache.canCaptureOnDisplay(bounds: CGRect(x: -4200, y: 0, width: 34, height: 33), displayBounds: display))
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        #expect(MenuBarItemImageCache.canCaptureOnDisplay(bounds: CGRect(x: 2883, y: 0, width: 34, height: 30), displayBounds: second))
        #expect(!MenuBarItemImageCache.canCaptureOnDisplay(bounds: CGRect(x: 999, y: 0, width: 34, height: 33), displayBounds: second))
        #expect(!MenuBarItemImageCache.canCaptureOnDisplay(bounds: .null, displayBounds: display))
    }
}
