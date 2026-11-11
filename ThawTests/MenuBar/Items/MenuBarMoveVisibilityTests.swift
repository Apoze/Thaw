//
//  MenuBarMoveVisibilityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Move visibility lifetime")
struct MenuBarMoveVisibilityTests {
    @Test @MainActor
    func nestedMovesRetainTheOverrideUntilTheLastRelease() throws {
        var calls: [String] = []
        let visibility = MenuBarMoveVisibility { display, enabled in
            calls.append("\(display):\(enabled)")
            return true
        }
        let first = try #require(visibility.acquire(on: 1))
        let second = try #require(visibility.acquire(on: 1))
        #expect(calls == ["1:true"])
        first()
        first()
        #expect(calls == ["1:true"])
        second()
        #expect(calls == ["1:true", "1:false"])
    }

    @Test @MainActor
    func failureReleasesOnlyTheSelectedDisplay() throws {
        enum Failure: Error { case interrupted }
        var calls: [String] = []
        let visibility = MenuBarMoveVisibility { display, enabled in
            calls.append("\(display):\(enabled)")
            return true
        }
        let other = try #require(visibility.acquire(on: 5))
        do {
            let release = try #require(visibility.acquire(on: 1))
            defer { release() }
            throw Failure.interrupted
        } catch Failure.interrupted {}
        #expect(calls == ["5:true", "1:true", "1:false"])
        other()
        #expect(calls.last == "5:false")
    }

    @Test @MainActor
    func missingAPILeavesNoHold() {
        var calls = 0
        let visibility = MenuBarMoveVisibility { _, _ in
            calls += 1
            return false
        }
        #expect(visibility.acquire(on: 1) == nil)
        #expect(visibility.acquire(on: 1) == nil)
        #expect(calls == 2)
    }

    @Test(arguments: [CGFloat(0), CGFloat(-1080)])
    func refusesConcealedAndAnimatingFrames(top: CGFloat) {
        let display = CGRect(x: 0, y: top, width: 1512, height: 982)
        var settling = MenuBarMoveVisibility.Settling()
        func frame(_ x: CGFloat, _ offset: CGFloat) -> CGRect {
            CGRect(x: x, y: top + offset, width: 34, height: 33)
        }
        for offset in [-33.0, -16, -8, -1, -1, -1, -1, -1] {
            let ready = settling.observe(source: frame(-4200, offset), target: frame(999, offset), displayBounds: display)
            #expect(!ready)
        }
        for _ in 0 ..< 4 {
            let ready = settling.observe(source: frame(-4200, 0), target: frame(999, 0), displayBounds: display)
            #expect(!ready)
        }
        let ready = settling.observe(source: frame(-4200, 0), target: frame(999, 0), displayBounds: display)
        #expect(ready)
        let moved = settling.observe(source: frame(-4166, 0), target: frame(999, 0), displayBounds: display)
        #expect(!moved)
        let missing = settling.observe(source: .null, target: frame(999, 0), displayBounds: display)
        #expect(!missing)
    }

    @Test("Vertical auto-hide animation must not acknowledge a drag")
    func ignoresVerticalOnlyResponses() {
        let start = CGPoint(x: 965, y: 0)
        #expect(!MenuBarItemManager.isHorizontalMoveResponse(origin: CGPoint(x: 965, y: -13), initialOrigin: start))
        #expect(!MenuBarItemManager.isHorizontalMoveResponse(origin: start, initialOrigin: start))
        #expect(MenuBarItemManager.isHorizontalMoveResponse(origin: CGPoint(x: -4211, y: 0), initialOrigin: start))
        #expect(!MenuBarItemManager.isHorizontalMoveResponse(origin: CGPoint(x: CGFloat.infinity, y: 0), initialOrigin: start))
    }
}
