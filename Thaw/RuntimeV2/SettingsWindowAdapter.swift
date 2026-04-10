//
//  SettingsWindowAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation

@MainActor
final class SettingsWindowAdapter: ObservableObject {
    @Published var isUpdateConsentPresented: Bool

    let navigationState: AppNavigationState
    let session: SettingsSessionAdapter

    private let sessionModel: AppSessionModel
    private let updatesManager: UpdatesManager
    private var cancellables = Set<AnyCancellable>()

    init(
        sessionModel: AppSessionModel,
        navigationState: AppNavigationState,
        session: SettingsSessionAdapter,
        updatesManager: UpdatesManager
    ) {
        self.sessionModel = sessionModel
        self.navigationState = navigationState
        self.session = session
        self.updatesManager = updatesManager
        isUpdateConsentPresented = sessionModel.isUpdateConsentPresented

        sessionModel.$isUpdateConsentPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                self?.isUpdateConsentPresented = isPresented
            }
            .store(in: &cancellables)
    }

    func enableAutomaticUpdates(autoDownload: Bool) {
        setUpdateConsentPresented(false)
        Defaults.set(true, forKey: .hasSeenUpdateConsent)
        updatesManager.automaticallyChecksForUpdates = true
        updatesManager.automaticallyDownloadsUpdates = autoDownload
        updatesManager.startUpdaterIfNeeded()
    }

    func disableAutomaticUpdates() {
        setUpdateConsentPresented(false)
        Defaults.set(true, forKey: .hasSeenUpdateConsent)
        updatesManager.automaticallyChecksForUpdates = false
    }

    func performSetup(windowCommands: AppSessionModel.WindowCommands) {
        sessionModel.performSetup(windowCommands: windowCommands)
    }

    func bindWindow(_ window: NSWindow?) {
        sessionModel.bindWindow(.settings, to: window)
    }

    private func setUpdateConsentPresented(_ isPresented: Bool) {
        isUpdateConsentPresented = isPresented
        sessionModel.isUpdateConsentPresented = isPresented
    }
}
