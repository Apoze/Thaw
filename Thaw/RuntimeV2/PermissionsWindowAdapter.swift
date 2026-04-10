//
//  PermissionsWindowAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation

@MainActor
final class PermissionsWindowAdapter {
    let manager: PermissionService
    let flowAdapter: PermissionsFlowAdapter
    private let sessionModel: AppSessionModel

    init(manager: PermissionService, flowAdapter: PermissionsFlowAdapter, sessionModel: AppSessionModel) {
        self.manager = manager
        self.flowAdapter = flowAdapter
        self.sessionModel = sessionModel
    }

    func performSetup(windowCommands: AppSessionModel.WindowCommands) {
        sessionModel.performSetup(windowCommands: windowCommands)
    }

    func bindWindow(_ window: NSWindow?) {
        sessionModel.bindWindow(.permissions, to: window)
    }
}
