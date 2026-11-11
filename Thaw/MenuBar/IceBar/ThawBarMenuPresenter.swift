//
//  ThawBarMenuPresenter.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import Cocoa

/// Opens the owning application's interface without moving its status item.
@MainActor
final class ThawBarMenuPresenter {
    private let log = DiagLog(category: "ThawBarMenuPresenter")
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var activeMenu: AXUIElement?
    private var bridge: ThawBarMenuBridge?
    private(set) var isInteracting = false

    func open(item: MenuBarItem, button: CGMouseButton, anchor: CGRect, in panel: NSPanel) {
        // A second press while AX is opening a modal menu can toggle it closed.
        guard !isInteracting else { return }
        guard AXIsProcessTrusted() else {
            showMessage("Autorisation Accessibilité requise pour ouvrir ce menu.", anchor: anchor, in: panel)
            return
        }
        log.debug("Opening requested: appActive=\(NSApp.isActive), panelKey=\(panel.isKeyWindow)")
        let openingStart = ContinuousClock.now
        isInteracting = true
        let token = UUID()
        generation = token
        task = Task { [weak self, weak panel] in
            guard let self, let panel else { return }
            defer {
                if generation == token {
                    isInteracting = false
                    activeMenu = nil
                    task = nil
                }
            }
            guard let element = ThawBarAX.resolve(item) else {
                log.warning("No unambiguous AX item for \(item.logString)")
                showMessage("Cette application ne rend pas cette icône accessible.", anchor: anchor, in: panel)
                return
            }
            let action = button == .right ? kAXShowMenuAction : kAXPressAction
            let actions: [String] = ThawBarAX.actions(element)
            guard actions.contains(action) else {
                showMessage("Cette icône ne propose pas cette action via l’accessibilité.", anchor: anchor, in: panel)
                return
            }
            let before = ClickReactionVerifier.snapshot(for: item)
            let result = AXUIElementPerformAction(element, action as CFString)
            // cannotComplete is also returned by a successfully opened modal menu.
            // Never send a second press merely because the first one timed out.
            log.debug("Direct action on \(item.logString): \(result.rawValue)")
            var menu: AXUIElement?
            for _ in 0 ..< 12 {
                guard !Task.isCancelled, panel.isVisible, generation == token else { return }
                menu = ThawBarAX.shownMenu(element)
                if menu != nil {
                    break
                }
                if ClickReactionVerifier.reactionSoFar(against: before)?.didReact == true {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled, panel.isVisible else { return }
            if let menu {
                activeMenu = menu
                let entries = ThawBarAX.menuEntries(menu)
                // AppKit status menus generally expose a read-only position. Present
                // their commands below the clicked icon instead of moving the icon.
                AXUIElementPerformAction(menu, kAXCancelAction as CFString)
                activeMenu = nil
                guard !entries.isEmpty else {
                    showMessage("Cette application ne fournit pas les commandes de son menu.", anchor: anchor, in: panel)
                    return
                }
                // The remote menu owns AppKit's tracking session until cancellation
                // is processed. Yield before starting our own tracking session.
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, generation == token, panel.isVisible else { return }
                let needsActivation = !NSApp.isActive
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                // isActive can change before AppKit finishes delivering activation
                // events. Starting menu tracking during that transition dismisses
                // the first menu immediately. Only newly activated panels wait.
                if needsActivation {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                for _ in 0 ..< 5 where !NSApp.isActive {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                guard !Task.isCancelled, generation == token, panel.isVisible else { return }
                let presenter = ThawBarMenuBridge(entries: entries)
                bridge = presenter
                log.info("Presenting \(entries.count) menu rows for \(item.logString) in the Thaw Bar; opening=\(openingStart.duration(to: .now))")
                let screenAnchor = panel.convertToScreen(anchor)
                let trackingStart = ContinuousClock.now
                let selection = presenter.popUp(at: CGPoint(x: screenAnchor.minX, y: screenAnchor.minY - 4), in: nil)
                log.info("Local menu closed after \(trackingStart.duration(to: .now)); selected=\(selection != nil), panelVisible=\(panel.isVisible)")
                bridge = nil
                guard let selection, !Task.isCancelled, generation == token, panel.isVisible else { return }
                // The owner may have rebuilt a dynamic menu while the user read it.
                // Resolve again; never execute a cached row from a previous menu.
                guard let freshElement = ThawBarAX.resolve(item) else { return }
                AXUIElementPerformAction(freshElement, action as CFString)
                var freshMenu: AXUIElement?
                for _ in 0 ..< 10 {
                    guard !Task.isCancelled, generation == token else { return }
                    freshMenu = ThawBarAX.shownMenu(freshElement)
                    if freshMenu != nil {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard let freshMenu else { return }
                activeMenu = freshMenu
                guard let command = ThawBarAX.commandElement(in: freshMenu, path: selection) else {
                    AXUIElementPerformAction(freshMenu, kAXCancelAction as CFString)
                    activeMenu = nil
                    showMessage("Le menu a changé. Ouvrez-le à nouveau pour choisir la commande.", anchor: anchor, in: panel)
                    return
                }
                let commandResult = AXUIElementPerformAction(command, kAXPressAction as CFString)
                log.info("Menu command delivered for \(item.logString): \(commandResult.rawValue)")
                AXUIElementPerformAction(freshMenu, kAXCancelAction as CFString)
                activeMenu = nil
            } else if ClickReactionVerifier.reactionSoFar(against: before)?.didReact == true {
                log.info("Application opened a custom interface for \(item.logString)")
            } else {
                log.warning("No interface observed for \(item.logString), AX result \(result.rawValue)")
                showMessage("L’application n’a pas ouvert de menu accessible. Son icône est restée à sa place.", anchor: anchor, in: panel)
            }
        }
    }

    func cancel() {
        generation = UUID()
        bridge?.cancel()
        bridge = nil
        task?.cancel()
        task = nil
        if let activeMenu {
            AXUIElementPerformAction(activeMenu, kAXCancelAction as CFString)
        }
        activeMenu = nil
        isInteracting = false
    }

    private func showMessage(_ message: String, anchor: CGRect, in panel: NSPanel) {
        let menu = NSMenu()
        menu.addItem(withTitle: message, action: nil, keyEquivalent: "")
        let screenAnchor = panel.convertToScreen(anchor)
        menu.popUp(positioning: nil, at: CGPoint(x: screenAnchor.minX, y: screenAnchor.minY - 4), in: nil)
    }
}
