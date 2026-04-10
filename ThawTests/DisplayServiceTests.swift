//
//  DisplayServiceTests.swift
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
final class DisplayServiceTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    func testDisplayConfigurationPublisherForwardsWorkspaceEventSourceEvents() async {
        let workspaceCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let workspaceEventSource = WorkspaceEventSource(
            environment: .init(
                workspaceNotificationCenter: workspaceCenter,
                applicationNotificationCenter: applicationCenter,
                initialFrontmostApplication: { nil },
                frontmostApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher(),
                menuBarOwningApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher()
            )
        )
        let displayService = DisplayService(workspaceEventSource: workspaceEventSource)

        var eventCount = 0
        let expectation = expectation(description: "display event forwarded once")

        displayService.displayConfigurationDidChangePublisher
            .sink {
                eventCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        workspaceEventSource.performSetup()
        displayService.performSetup()

        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(eventCount, 1)
    }

    func testPerformSetupIsIdempotentForForwardedDisplayEvents() async {
        let workspaceCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let workspaceEventSource = WorkspaceEventSource(
            environment: .init(
                workspaceNotificationCenter: workspaceCenter,
                applicationNotificationCenter: applicationCenter,
                initialFrontmostApplication: { nil },
                frontmostApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher(),
                menuBarOwningApplicationPublisher: Empty<WorkspaceApplicationInfo?, Never>().eraseToAnyPublisher()
            )
        )
        let displayService = DisplayService(workspaceEventSource: workspaceEventSource)

        var eventCount = 0
        let expectation = expectation(description: "single forwarded event after repeated setup")

        displayService.displayConfigurationDidChangePublisher
            .sink {
                eventCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        workspaceEventSource.performSetup()
        displayService.performSetup()
        displayService.performSetup()

        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(eventCount, 1)
    }

    func testDisplayUUIDResolvesForKnownDisplay() {
        guard let displayID = NSScreen.main?.displayID else {
            XCTFail("Expected a main display during test execution")
            return
        }

        let displayService = DisplayService(workspaceEventSource: WorkspaceEventSource())
        XCTAssertEqual(displayService.displayUUID(for: displayID), DisplayUUID.string(for: displayID))
    }
}
