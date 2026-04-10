//
//  PermissionsFlowAdapter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
final class PermissionsFlowAdapter {
    private let sessionModel: AppSessionModel
    private let completePermissionsFlowHandler: @MainActor () -> Void

    init(
        sessionModel: AppSessionModel,
        completePermissionsFlowHandler: @escaping @MainActor () -> Void
    ) {
        self.sessionModel = sessionModel
        self.completePermissionsFlowHandler = completePermissionsFlowHandler
    }

    func relaunch() {
        sessionModel.relaunch()
    }

    func reopenPermissionsWindow() {
        sessionModel.activate(withPolicy: .regular)
        sessionModel.openWindow(.permissions)
    }

    func completePermissionsFlow() {
        completePermissionsFlowHandler()
    }
}
