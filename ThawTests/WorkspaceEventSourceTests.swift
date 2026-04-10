//
//  WorkspaceEventSourceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import AppKit
import Foundation
import XCTest
@testable import Thaw

@MainActor
final class WorkspaceEventSourceTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    func testPublishesTypedInvalidationsFromWorkspaceAndScreenNotifications() async {
        let workspaceCenter = NotificationCenter()
        let screenCenter = NotificationCenter()
        let source = WorkspaceEventSource(
            environment: makeEnvironment(
                workspaceNotificationCenter: workspaceCenter,
                applicationNotificationCenter: screenCenter
            )
        )
        let currentApp = NSRunningApplication.current

        var observed = [DiscoveryInvalidation]()
        let expectation = expectation(description: "all invalidations published")
        expectation.expectedFulfillmentCount = 4

        source.invalidationPublisher
            .sink { invalidation in
                observed.append(invalidation)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        source.performSetup()

        let userInfo = [NSWorkspace.applicationUserInfoKey: currentApp]
        workspaceCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil, userInfo: userInfo)
        workspaceCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: userInfo)
        workspaceCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: userInfo)
        screenCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(
            observed,
            [
                .appLaunched(
                    bundleID: currentApp.bundleIdentifier,
                    processIdentifier: currentApp.processIdentifier
                ),
                .appTerminated(
                    bundleID: currentApp.bundleIdentifier,
                    processIdentifier: currentApp.processIdentifier
                ),
                .appActivated(
                    bundleID: currentApp.bundleIdentifier,
                    processIdentifier: currentApp.processIdentifier
                ),
                .displayConfigurationChanged,
            ]
        )
    }

    func testSetupIsIdempotentAndDoesNotDuplicateEvents() async {
        let workspaceCenter = NotificationCenter()
        let source = WorkspaceEventSource(
            environment: makeEnvironment(workspaceNotificationCenter: workspaceCenter)
        )
        let currentApp = NSRunningApplication.current

        var observed = [DiscoveryInvalidation]()
        let expectation = expectation(description: "single invalidation published")

        source.invalidationPublisher
            .sink { invalidation in
                observed.append(invalidation)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        source.performSetup()
        source.performSetup()

        workspaceCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: currentApp]
        )

        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(
            observed,
            [
                .appLaunched(
                    bundleID: currentApp.bundleIdentifier,
                    processIdentifier: currentApp.processIdentifier
                ),
            ]
        )
    }

    func testScreenParameterNotificationsBypassWorkspaceMapper() async {
        let workspaceCenter = NotificationCenter()
        let screenCenter = NotificationCenter()
        let source = WorkspaceEventSource(
            environment: makeEnvironment(
                workspaceNotificationCenter: workspaceCenter,
                applicationNotificationCenter: screenCenter
            )
        )

        var observed = [DiscoveryInvalidation]()
        let expectation = expectation(description: "screen invalidation published")

        source.invalidationPublisher
            .sink { invalidation in
                observed.append(invalidation)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        source.performSetup()

        workspaceCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        screenCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(observed, [.displayConfigurationChanged])
    }

    private func makeEnvironment(
        workspaceNotificationCenter: NotificationCenter,
        applicationNotificationCenter: NotificationCenter = NotificationCenter()
    ) -> WorkspaceEventSource.Environment {
        WorkspaceEventSource.Environment(
            workspaceNotificationCenter: workspaceNotificationCenter,
            applicationNotificationCenter: applicationNotificationCenter,
            initialFrontmostApplication: { nil },
            frontmostApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher(),
            menuBarOwningApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher()
        )
    }
}
