//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// The runtime authority for the app's permission state.
@MainActor
final class PermissionService: ObservableObject {
    /// The state of the app's granted permissions.
    enum PermissionsState {
        case missing
        case hasAll
        case hasRequired
    }

    /// The manager's logger.
    let diagLog = DiagLog(category: .permission)

    /// The permission for Accessibility features.
    let accessibility: Permission

    /// The permissions required for full app functionality.
    let allPermissions: [Permission]

    /// The state of the app's granted permissions.
    @Published private(set) var permissionsState: PermissionsState = .missing

    /// Storage for internal observers.
    private var cancellable: AnyCancellable?

    /// The permissions required for basic app functionality.
    var requiredPermissions: [Permission] {
        allPermissions.filter { $0.isRequired }
    }

    /// Creates a new permissions manager.
    init(
        accessibility: Permission? = nil,
        additionalPermissions: [Permission] = []
    ) {
        let accessibility = accessibility ?? AccessibilityPermission()
        self.accessibility = accessibility
        allPermissions = [accessibility] + additionalPermissions
        self.updatePermissionsState()
        self.cancellable = Publishers.MergeMany(allPermissions.map { $0.$hasPermission })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePermissionsState()
            }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        if allPermissions.allSatisfy({ $0.hasPermission }) {
            permissionsState = .hasAll
        } else if requiredPermissions.allSatisfy({ $0.hasPermission }) {
            permissionsState = .hasRequired
        } else {
            permissionsState = .missing
        }
    }

    /// Forces an immediate refresh of all permissions and returns the result.
    @discardableResult
    func refreshPermissions() -> PermissionsState {
        for permission in allPermissions {
            permission.refreshStatus()
        }

        updatePermissionsState()
        return permissionsState
    }

    func refresh() {
        _ = refreshPermissions()
    }

    func requestAccessibilityPermission() {
        accessibility.performRequest()
        refresh()
    }

    @discardableResult
    func refreshPermission(_ permission: Permission) -> Bool {
        let granted = permission.refreshStatus()
        updatePermissionsState()
        return granted
    }

    func requestPermission(_ permission: Permission) {
        permission.performRequest()
    }

    func waitForPermission(_ permission: Permission) async {
        await permission.waitForPermission()
        refresh()
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        diagLog.info("Stopping all permissions checks")
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}

typealias AppPermissions = PermissionService
