//
//  ThawBarMenuBridge.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import Cocoa

nonisolated struct ThawBarMenuEntry: Equatable {
    struct Step: Equatable {
        let index: Int
        let title: String
    }

    let title: String
    let enabled: Bool
    let checked: Bool
    let path: [Step]
    let children: [ThawBarMenuEntry]

    var isSeparator: Bool {
        title.isEmpty && children.isEmpty
    }

    static func matchingIndex(step: Step, titles: [String]) -> Int? {
        let matches = titles.indices.filter { titles[$0] == step.title }
        return matches.count == 1 ? matches.first : nil
    }
}

/// Presents AppKit menu rows locally while their commands stay in the owner.
@MainActor
final class ThawBarMenuBridge: NSObject {
    private(set) var selection: [ThawBarMenuEntry.Step]?
    private let menu: NSMenu

    init(entries: [ThawBarMenuEntry]) {
        menu = NSMenu()
        super.init()
        populate(menu, entries: entries)
    }

    func popUp(at point: CGPoint, in view: NSView?) -> [ThawBarMenuEntry.Step]? {
        menu.popUp(positioning: nil, at: point, in: view)
        return selection
    }

    func cancel() {
        menu.cancelTracking()
    }

    private func populate(_ menu: NSMenu, entries: [ThawBarMenuEntry]) {
        menu.autoenablesItems = false
        for entry in entries {
            if entry.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let row = NSMenuItem(title: entry.title, action: #selector(selectCommand(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = Command(path: entry.path)
            row.isEnabled = entry.enabled
            row.state = entry.checked ? .on : .off
            if !entry.children.isEmpty {
                let submenu = NSMenu(title: entry.title)
                populate(submenu, entries: entry.children)
                row.submenu = submenu
            }
            menu.addItem(row)
        }
    }

    @objc private func selectCommand(_ sender: NSMenuItem) {
        selection = (sender.representedObject as? Command)?.path
    }

    private final class Command {
        let path: [ThawBarMenuEntry.Step]

        init(path: [ThawBarMenuEntry.Step]) {
            self.path = path
        }
    }
}

@MainActor
extension ThawBarAX {
    static func menuEntries(_ menu: AXUIElement) -> [ThawBarMenuEntry] {
        var remaining = 250
        let deadline = ContinuousClock.now + .seconds(1)
        return readEntries(menu, path: [], remaining: &remaining, deadline: deadline)
    }

    private static func readEntries(
        _ menu: AXUIElement,
        path: [ThawBarMenuEntry.Step],
        remaining: inout Int,
        deadline: ContinuousClock.Instant
    ) -> [ThawBarMenuEntry] {
        guard path.count < 8, remaining > 0, ContinuousClock.now < deadline else { return [] }
        let children: [AXUIElement] = attribute(menu, kAXChildrenAttribute) ?? []
        var entries = [ThawBarMenuEntry]()
        for (index, child) in children.enumerated() {
            guard remaining > 0, ContinuousClock.now < deadline else { break }
            remaining -= 1
            AXUIElementSetMessagingTimeout(child, 0.1)
            let role: String? = attribute(child, kAXRoleAttribute)
            guard role == kAXMenuItemRole else { continue }
            let title: String = attribute(child, kAXTitleAttribute) ?? ""
            let enabled: Bool = attribute(child, kAXEnabledAttribute) ?? false
            let mark: String = attribute(child, kAXMenuItemMarkCharAttribute) ?? ""
            let childPath = path + [.init(index: index, title: title)]
            let descendants: [AXUIElement] = attribute(child, kAXChildrenAttribute) ?? []
            let submenu = descendants.first { (attribute($0, kAXRoleAttribute) as String?) == kAXMenuRole }
            let nested = submenu.map { readEntries($0, path: childPath, remaining: &remaining, deadline: deadline) } ?? []
            entries.append(ThawBarMenuEntry(
                title: title,
                enabled: enabled && (submenu == nil || !nested.isEmpty),
                checked: !mark.isEmpty,
                path: childPath,
                children: nested
            ))
        }
        return entries
    }

    /// Revalidate each row against the freshly opened menu before sending a command.
    static func commandElement(in menu: AXUIElement, path: [ThawBarMenuEntry.Step]) -> AXUIElement? {
        guard !path.isEmpty, path.count <= 8 else { return nil }
        let deadline = ContinuousClock.now + .milliseconds(700)
        var currentMenu = menu
        for (depth, step) in path.enumerated() {
            let children: [AXUIElement] = attribute(currentMenu, kAXChildrenAttribute) ?? []
            guard children.count <= 250 else { return nil }
            var titles = [String]()
            for child in children {
                guard ContinuousClock.now < deadline else { return nil }
                AXUIElementSetMessagingTimeout(child, 0.1)
                titles.append(attribute(child, kAXTitleAttribute) ?? "")
            }
            guard let index = ThawBarMenuEntry.matchingIndex(step: step, titles: titles) else { return nil }
            let row = children[index]
            guard (attribute(row, kAXEnabledAttribute) as Bool?) == true else { return nil }
            if depth == path.count - 1 {
                return row
            }
            let descendants: [AXUIElement] = attribute(row, kAXChildrenAttribute) ?? []
            guard let submenu = descendants.first(where: { (attribute($0, kAXRoleAttribute) as String?) == kAXMenuRole }) else { return nil }
            currentMenu = submenu
        }
        return nil
    }
}
