//
//  DisplayService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

struct DisplayObservation: Hashable, Sendable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let uuid: String?
}

struct DisplayObservationSnapshot: Hashable, Sendable {
    let activeDisplayID: CGDirectDisplayID?
    let displays: [DisplayObservation]

    func displayID(for point: CGPoint?) -> CGDirectDisplayID? {
        guard let point else {
            return activeDisplayID
        }

        return displays.first(where: { $0.frame.contains(point) })?.displayID
    }

    func displayUUID(for displayID: CGDirectDisplayID?) -> String? {
        guard let displayID else {
            return nil
        }

        return displays.first(where: { $0.displayID == displayID })?.uuid
    }
}

@MainActor
final class DisplayService: ObservableObject {
    @Published private(set) var activeScreen: NSScreen?
    @Published private(set) var connectedScreens = [NSScreen]()

    private let diagLog = DiagLog(category: "DisplayService")
    private let workspaceEventSource: WorkspaceEventSource
    private var cancellables = Set<AnyCancellable>()
    private var hasPerformedSetup = false
    private var lastKnownScreenCount = 0

    init(workspaceEventSource: WorkspaceEventSource) {
        self.workspaceEventSource = workspaceEventSource
    }

    var activeDisplayUUID: String? {
        guard let displayID = activeDisplayID else {
            return nil
        }
        return DisplayUUID.string(for: displayID)
    }

    var activeDisplayID: CGDirectDisplayID? {
        activeScreen?.displayID ?? NSScreen.main?.displayID
    }

    var activeMenuBarDisplayID: CGDirectDisplayID? {
        NSScreen.screenWithActiveMenuBar?.displayID ?? activeDisplayID
    }

    var displayConfigurationDidChangePublisher: AnyPublisher<Void, Never> {
        workspaceEventSource.displayConfigurationDidChangePublisher
    }

    var activeSpaceDidChangePublisher: AnyPublisher<Void, Never> {
        workspaceEventSource.activeSpaceDidChangePublisher
    }

    func performSetup() {
        updateScreens()
        updateActiveScreen()

        guard !hasPerformedSetup else {
            return
        }

        hasPerformedSetup = true

        workspaceEventSource.displayConfigurationDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleDisplayConfigurationDidChange()
            }
            .store(in: &cancellables)

        workspaceEventSource.activeSpaceDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateActiveScreen()
            }
            .store(in: &cancellables)
    }

    func updateActiveScreen() {
        activeScreen = NSScreen.screenWithMouse ?? NSApp.keyWindow?.screen ?? NSScreen.main
    }

    func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        if let displayID {
            return connectedScreens.first { $0.displayID == displayID }
        }
        return activeScreen ?? NSScreen.main
    }

    func displayUUID(for displayID: CGDirectDisplayID?) -> String? {
        guard let displayID else {
            return nil
        }
        return DisplayUUID.string(for: displayID)
    }

    func displayID(for point: CGPoint?) -> CGDirectDisplayID? {
        guard let point else {
            return activeDisplayID
        }
        return connectedScreens.first(where: { $0.frame.contains(point) })?.displayID
    }

    func preferredPresentationScreen() -> NSScreen? {
        NSScreen.screenWithMouse ?? activeScreen ?? NSScreen.main
    }

    func observationSnapshot() -> DisplayObservationSnapshot {
        DisplayObservationSnapshot(
            activeDisplayID: activeScreen?.displayID ?? NSScreen.main?.displayID,
            displays: connectedScreens.map { screen in
                DisplayObservation(
                    displayID: screen.displayID,
                    frame: screen.frame,
                    uuid: DisplayUUID.string(for: screen.displayID)
                )
            }
        )
    }

    private func handleDisplayConfigurationDidChange() {
        let previousCount = lastKnownScreenCount
        updateScreens()
        updateActiveScreen()

        if connectedScreens.count < previousCount {
            diagLog.info("Detected display disconnect; state will be refreshed automatically")
        } else if connectedScreens.count > previousCount {
            diagLog.info("Detected display connect; state will be refreshed automatically")
        }

        lastKnownScreenCount = connectedScreens.count
    }

    private func updateScreens() {
        connectedScreens = NSScreen.screens
    }
}
