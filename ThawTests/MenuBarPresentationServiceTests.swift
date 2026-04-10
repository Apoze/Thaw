//
//  MenuBarPresentationServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import XCTest
@testable import Thaw

@MainActor
final class MenuBarPresentationServiceTests: XCTestCase {
    func testSetupUsesExplicitDependenciesToRefreshMenuBarHiddenState() async {
        let service = MenuBarPresentationService()
        let activeSpaceSubject = PassthroughSubject<Void, Never>()
        let displayConfigurationSubject = PassthroughSubject<Void, Never>()
        let savedGlobalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)

        defer {
            if let savedGlobalDomain {
                UserDefaults.standard.setPersistentDomain(savedGlobalDomain, forName: UserDefaults.globalDomain)
            } else {
                UserDefaults.standard.removePersistentDomain(forName: UserDefaults.globalDomain)
            }
        }

        UserDefaults.standard.setPersistentDomain(
            ["_HIHideMenuBar": false],
            forName: UserDefaults.globalDomain
        )
        UserDefaults.standard.synchronize()

        service.performSetup(with: .init(
            systemPresentationOptionsPublisher: Just([]).eraseToAnyPublisher(),
            activeSpaceDidChangePublisher: activeSpaceSubject.eraseToAnyPublisher(),
            displayConfigurationDidChangePublisher: displayConfigurationSubject.eraseToAnyPublisher(),
            settingsWindowVisibilityPublisher: Empty<Bool, Never>().eraseToAnyPublisher()
        ))

        XCTAssertFalse(service.isMenuBarHiddenBySystemUserDefaults)

        UserDefaults.standard.setPersistentDomain(
            ["_HIHideMenuBar": true],
            forName: UserDefaults.globalDomain
        )
        UserDefaults.standard.synchronize()
        displayConfigurationSubject.send(())

        let deadline = ContinuousClock.now + .seconds(1)
        while !service.isMenuBarHiddenBySystemUserDefaults, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(service.isMenuBarHiddenBySystemUserDefaults)
    }
}
