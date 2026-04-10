//
//  PermissionServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class PermissionServiceTests: XCTestCase {
    func testRefreshPermissionsReturnsMissingHasRequiredAndHasAll() {
        let requiredPermission = MutablePermission(isRequired: true, initialGrant: false)
        let optionalPermission = MutablePermission(isRequired: false, initialGrant: false)
        let service = PermissionService(
            accessibility: requiredPermission,
            additionalPermissions: [optionalPermission]
        )

        XCTAssertEqual(service.permissionsState, .missing)
        XCTAssertEqual(service.refreshPermissions(), .missing)

        requiredPermission.setGranted(true)
        XCTAssertEqual(service.refreshPermissions(), .hasRequired)

        optionalPermission.setGranted(true)
        XCTAssertEqual(service.refreshPermissions(), .hasAll)
    }

    func testRequestAccessibilityPermissionPerformsRequestAndRefreshesState() {
        let permission = MutablePermission(isRequired: true, initialGrant: false)
        let service = PermissionService(accessibility: permission)

        service.requestAccessibilityPermission()

        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(service.permissionsState, .hasAll)
    }
}

@MainActor
private final class MutablePermission: Permission {
    private let storage: MutablePermissionStorage

    init(isRequired: Bool, initialGrant: Bool) {
        storage = MutablePermissionStorage(isGranted: initialGrant)
        super.init(
            title: "Mutable Permission",
            details: [],
            isRequired: isRequired,
            settingsURL: nil,
            check: { [storage] in
                storage.isGranted
            },
            request: { [storage] in
                storage.requestCount += 1
                storage.isGranted = true
            }
        )
    }

    var requestCount: Int {
        storage.requestCount
    }

    func setGranted(_ newValue: Bool) {
        storage.isGranted = newValue
    }
}

private final class MutablePermissionStorage {
    var isGranted: Bool
    var requestCount = 0

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }
}
