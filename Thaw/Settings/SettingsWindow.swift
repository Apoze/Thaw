//
//  SettingsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    @ObservedObject var adapter: SettingsWindowAdapter
    @StateObject private var model = SettingsWindowModel()

    var body: some Scene {
        IceWindow(
            id: .settings,
            installWindowCommands: { openWindow, dismissWindow in
                adapter.performSetup(windowCommands: .init(
                    openWindow: { openWindow($0) },
                    dismissWindow: { dismissWindow($0) }
                ))
            },
            content: {
                SettingsView(
                    navigationState: adapter.navigationState,
                    session: adapter.session
                )
                    .onWindowChange { window in
                        adapter.bindWindow(window)
                        model.observeWindowToolbar(window)
                    }
                    .sheet(isPresented: $adapter.isUpdateConsentPresented) {
                        UpdateConsentSheet { autoDownload in
                            adapter.enableAutomaticUpdates(autoDownload: autoDownload)
                        } onDisable: {
                            adapter.disableAutomaticUpdates()
                        }
                    }
                    .frame(minWidth: 850, maxWidth: 1150, minHeight: 550, maxHeight: 750)
            }
        )
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 850, height: 550)
    }
}

// MARK: - SettingsWindowModel

@MainActor
private final class SettingsWindowModel: ObservableObject {
    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Configures observers for the window's toolbar.
    func observeWindowToolbar(_ window: NSWindow?) {
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()

        guard let window else {
            return
        }

        if #available(macOS 15.0, *) {
            // TODO: Switch to the SwiftUI equivalent once we're targeting macOS 15.
            //
            // Performing availability checks in @SceneBuilder is annoyingly difficult,
            // so we're cheating for now and doing it here.
            //
            // SwiftUI seems to create a new toolbar each time the window is opened, so
            // we're using KVO to make sure the values stay set.
            //
            // - FOR FUTURE REFERENCE: Add `.windowToolbarLabelStyle(fixed: .iconOnly)`
            //   to the body of `SettingsWindow` and remove this publisher.
            Publishers.CombineLatest3(
                window.publisher(for: \.toolbar),
                window.publisher(for: \.toolbar?.displayMode),
                window.publisher(for: \.toolbar?.allowsDisplayModeCustomization)
            )
            .sink { toolbar, _, _ in
                toolbar?.displayMode = .iconOnly
                toolbar?.allowsDisplayModeCustomization = false
            }
            .store(in: &cancellables)
        }
    }
}
