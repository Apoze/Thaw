//
//  FocusFilterServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import XCTest
@testable import Thaw

@MainActor
final class FocusFilterServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "FocusFilterServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        cancellables = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        cancellables = nil
        defaultsSuiteName = nil
        defaults = nil
        super.tearDown()
    }

    func testBootstrapWithoutMirrorPublishesNotConfiguredWithoutQuery() {
        let provider = MockFocusFilterCurrentProvider()
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        var observedStates = [FocusFilterState]()

        service.statePublisher
            .sink { observedStates.append($0) }
            .store(in: &cancellables)

        service.performSetup { _ in false }

        XCTAssertEqual(service.state, .notConfigured)
        XCTAssertEqual(observedStates, [.notConfigured])
        XCTAssertEqual(provider.currentActionCallCount, 0)
    }

    func testBootstrapWithValidMirrorPublishesActiveWithoutQuery() {
        let provider = MockFocusFilterCurrentProvider()
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        let profileID = UUID()
        var observedStates = [FocusFilterState]()

        defaults.set(profileID.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)

        service.statePublisher
            .sink { observedStates.append($0) }
            .store(in: &cancellables)

        service.performSetup { $0 == profileID }

        XCTAssertEqual(service.state, .active(profileID))
        XCTAssertEqual(observedStates, [.active(profileID)])
        XCTAssertEqual(provider.currentActionCallCount, 0)
        XCTAssertTrue(defaults.bool(forKey: FocusFilterConstants.hasKnownConfigurationKey))
    }

    func testResyncMapsNoCurrentActionToNotConfiguredAndClearsKnownConfiguration() async {
        let provider = MockFocusFilterCurrentProvider()
        provider.currentActionError = NSError(
            domain: "DNDErrorDomain",
            code: 1007,
            userInfo: nil
        )
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        let notConfiguredExpectation = expectation(description: "Focus resolved to notConfigured")

        defaults.set(true, forKey: FocusFilterConstants.hasKnownConfigurationKey)

        service.statePublisher
            .sink { state in
                if state == .notConfigured {
                    notConfiguredExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        service.performSetup { _ in false }

        await fulfillment(of: [notConfiguredExpectation], timeout: 1)

        XCTAssertEqual(service.state, .notConfigured)
        XCTAssertEqual(provider.currentActionCallCount, 1)
        XCTAssertFalse(defaults.bool(forKey: FocusFilterConstants.hasKnownConfigurationKey))
    }

    func testActivationNotificationPublishesOnceForRepeatedEvents() {
        let provider = MockFocusFilterCurrentProvider()
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        let profileID = UUID()
        var observedStates = [FocusFilterState]()

        service.statePublisher
            .sink { observedStates.append($0) }
            .store(in: &cancellables)

        service.performSetup { $0 == profileID }
        defaults.set(profileID.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)

        let notification = Notification(
            name: FocusFilterConstants.activationNotification,
            object: nil,
            userInfo: ["profileID": profileID.uuidString]
        )
        service.handleActivationNotification(notification)
        service.handleActivationNotification(notification)

        XCTAssertEqual(service.state, .active(profileID))
        XCTAssertEqual(observedStates, [.notConfigured, .active(profileID)])
    }

    func testDeactivationClearsMirrorAndPublishesInactive() {
        let provider = MockFocusFilterCurrentProvider()
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        let profileID = UUID()

        defaults.set(profileID.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)
        service.performSetup { $0 == profileID }
        service.handleDeactivationNotification()

        XCTAssertEqual(service.state, .inactive)
        XCTAssertNil(defaults.string(forKey: FocusFilterConstants.requestedProfileIDKey))
    }
}

private final class MockFocusFilterCurrentProvider: FocusFilterCurrentProviding {
    var currentActionCallCount = 0
    var currentActionError: Error?
    var action = MockFocusFilterCurrentAction()

    func currentAction() async throws -> any FocusFilterCurrentAction {
        currentActionCallCount += 1
        if let currentActionError {
            throw currentActionError
        }
        return action
    }
}

private struct MockFocusFilterCurrentAction: FocusFilterCurrentAction {
    var requestedProfileID: UUID?

    func perform() async throws {}
}
