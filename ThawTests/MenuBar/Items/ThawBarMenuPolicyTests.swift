//
//  ThawBarMenuPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Anchored Thaw Bar menus")
struct ThawBarMenuPolicyTests {
    private let target = CGRect(x: -800, y: 0, width: 24, height: 24)

    @Test("Hidden off-screen icons are matched without moving them")
    func hiddenFrame() {
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [nil, target], target: target, allowSingle: false) == 1)
    }

    @Test("Ambiguous and missing candidates are never guessed")
    func ambiguous() {
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [target, target], target: target, allowSingle: false) == nil)
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [nil], target: target, allowSingle: false) == nil)
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [], target: target, allowSingle: true) == nil)
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [target], target: .null, allowSingle: false) == nil)
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [.zero], target: target, allowSingle: false) == nil)
    }

    @Test("Only a known single-item owner may bypass frame matching")
    func singleOwner() {
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [nil], target: target, allowSingle: true) == 0)
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [nil, nil], target: target, allowSingle: true) == nil)
    }

    @Test("A neighbouring icon is not selected after an identity change")
    func differentIcon() {
        #expect(ThawBarMenuPolicy.candidateIndex(frames: [target.offsetBy(dx: 24, dy: 0)], target: target, allowSingle: false) == nil)
    }

    @Test("Commands are matched after unrelated rows are inserted")
    func shiftedCommand() {
        let step = ThawBarMenuEntry.Step(index: 1, title: "Settings")
        #expect(ThawBarMenuEntry.matchingIndex(step: step, titles: ["New", "Status", "Settings"]) == 2)
        #expect(ThawBarMenuEntry.matchingIndex(step: step, titles: ["Status", "Settings"]) == 1)
    }

    @Test("A removed or ambiguous command is never executed")
    func staleCommand() {
        let step = ThawBarMenuEntry.Step(index: 1, title: "Settings")
        #expect(ThawBarMenuEntry.matchingIndex(step: step, titles: ["Status", "Quit"]) == nil)
        #expect(ThawBarMenuEntry.matchingIndex(step: step, titles: ["Settings", "Settings"]) == nil)
        #expect(ThawBarMenuEntry.matchingIndex(step: step, titles: []) == nil)
    }

    @Test("Separator detection does not discard untitled submenus")
    func separators() {
        let separator = ThawBarMenuEntry(title: "", enabled: false, checked: false, path: [], children: [])
        let submenu = ThawBarMenuEntry(title: "", enabled: true, checked: false, path: [], children: [separator])
        let row = ThawBarMenuEntry(title: "Enabled", enabled: true, checked: true, path: [], children: [])
        #expect(separator.isSeparator)
        #expect(!submenu.isSeparator)
        #expect(!row.isSeparator)
        #expect(row.checked && row.enabled)
    }
}
