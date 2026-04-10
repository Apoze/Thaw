//
//  AppDelegate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()

        // Register thaw:// URL events early so external tools (e.g. Raycast)
        // can trigger actions even when Thaw is not currently in the foreground;
        // depending on the action, the app may still be activated as needed.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        appState.appGraph.applicationDidFinishLaunching()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        appState.appGraph.applicationShouldHandleReopen()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        appState.appGraph.applicationShouldTerminateAfterLastWindowClosed(sender)
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_: Notification) {
        appState.appGraph.applicationWillTerminate()
    }

    // MARK: Other Methods

    /// Handles `kAEGetURL` Apple Events and forwards `thaw://` URLs to `handleURL(_:)`.
    @objc private func handleURLAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "thaw"
        else { return }
        handleURL(url)
    }

    /// Dispatches an incoming `thaw://` URL to the appropriate action.
    ///
    /// Supported URLs:
    /// - `thaw://panel` — toggle the Thaw panel
    /// - `thaw://archive` — toggle the Thaw archive surface
    /// - `thaw://search` — open the menu bar item search panel
    /// - `thaw://surface` — toggle the primary Thaw surface on the active display
    /// - `thaw://settings` — open the Thaw settings window
    private func handleURL(_ url: URL) {
        appState.appGraph.handleIncomingURL(url)
    }
}
