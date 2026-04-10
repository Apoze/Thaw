//
//  AppState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation

/// Thin application container holding long-lived models and services.
@MainActor
final class AppState {
    let sessionModel = AppSessionModel()

    /// Model for the app's settings.
    let settings = AppSettings()

    /// Single application graph.
    let appGraph: AppGraph

    /// Manager for the menu bar's appearance.
    let appearanceManager = MenuBarAppearanceManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    init(appGraph: AppGraph? = nil) {
        let appGraph = appGraph ?? AppGraph()
        self.appGraph = appGraph
        appGraph.attach(appState: self)
    }

    var activeSpace: SpaceInfo {
        sessionModel.activeSpace
    }

    var isUpdateConsentPresented: Bool {
        get { sessionModel.isUpdateConsentPresented }
        set { sessionModel.isUpdateConsentPresented = newValue }
    }

    var navigationState: AppNavigationState {
        sessionModel.navigationState
    }

    func startUpdaterIfNeeded() {
        updatesManager.startUpdaterIfNeeded()
    }

    func completeRuntimeSetupIfNeeded() {
        sessionModel.completeRuntimeSetupIfNeeded(workspaceEventSource: appGraph.workspaceEventSource)
    }

    func performSetup(windowCommands: AppSessionModel.WindowCommands) {
        sessionModel.performSetup(windowCommands: windowCommands)
    }

    func publisherForWindowVisibility(_ id: IceWindowIdentifier) -> AnyPublisher<Bool, Never> {
        sessionModel.publisherForWindowVisibility(id)
    }

    func bindWindow(_ id: IceWindowIdentifier, to window: NSWindow?) {
        sessionModel.bindWindow(id, to: window)
    }

    func openWindow(_ id: IceWindowIdentifier) {
        sessionModel.openWindow(id)
    }

    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        sessionModel.activate(withPolicy: policy)
    }

    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        sessionModel.deactivate(withPolicy: policy)
    }

    func dismissWindow(_ id: IceWindowIdentifier) {
        sessionModel.dismissWindow(id)
    }

    func relaunch() {
        sessionModel.relaunch()
    }

    var displayService: DisplayService {
        appGraph.displayService
    }

    var workspaceEventSource: WorkspaceEventSource {
        appGraph.workspaceEventSource
    }

    var discoverySession: DiscoverySession {
        appGraph.discoverySession
    }

    var hotkeySessionAdapter: HotkeySessionAdapter {
        appGraph.hotkeySessionAdapter
    }

    var settingsWindowAdapter: SettingsWindowAdapter {
        appGraph.settingsWindowAdapter
    }

    var permissionsWindowAdapter: PermissionsWindowAdapter {
        appGraph.permissionsWindowAdapter
    }
}
