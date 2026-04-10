//
//  ProfileManagerFocusRuntimeTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import XCTest
@testable import Thaw

@MainActor
final class ProfileManagerFocusRuntimeTests: XCTestCase {
    private var tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProfileManagerFocusRuntimeTests.placeholder", isDirectory: true)
    private var paths = ThawPersistencePaths(rootDirectory: FileManager.default.temporaryDirectory)
    private var defaults = UserDefaults.standard
    private var defaultsSuiteName = ""
    private var encoder = JSONEncoder()

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileManagerFocusRuntimeTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)

        defaultsSuiteName = "ProfileManagerFocusRuntimeTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    override func tearDown() {
        if !defaultsSuiteName.isEmpty {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaultsSuiteName = ""
        defaults = .standard
        encoder = JSONEncoder()
        paths = ThawPersistencePaths(rootDirectory: FileManager.default.temporaryDirectory)
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileManagerFocusRuntimeTests.placeholder", isDirectory: true)
        super.tearDown()
    }

    func testBootstrapWithoutMirrorFallsBackToDisplayProfile() async throws {
        let displayProfile = makeProfile(name: "Display", associatedDisplayUUID: "display-a")
        try seedProfiles([displayProfile])

        let manager = ProfileManager(paths: paths)
        let provider = MockFocusFilterCurrentProvider()
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        let context = makeRuntimeContext(currentDisplayUUID: "display-a")

        manager.performSetup(runtimeContext: context, focusFilterService: service)
        service.performSetup { manager.hasProfile(id: $0) }
        await settle(manager)

        XCTAssertEqual(manager.activeProfileID, displayProfile.id)
        XCTAssertEqual(provider.currentActionCallCount, 0)
    }

    func testBootstrapWithValidMirrorAppliesFocusProfile() async throws {
        let displayProfile = makeProfile(name: "Display", associatedDisplayUUID: "display-a")
        let focusProfile = makeProfile(name: "Focus")
        try seedProfiles([displayProfile, focusProfile])

        defaults.set(focusProfile.id.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)

        let manager = ProfileManager(paths: paths)
        let provider = MockFocusFilterCurrentProvider()
        let service = FocusFilterService(defaults: defaults, currentProvider: provider)
        let context = makeRuntimeContext(currentDisplayUUID: "display-a")

        manager.performSetup(runtimeContext: context, focusFilterService: service)
        service.performSetup { manager.hasProfile(id: $0) }
        await settle(manager)

        XCTAssertEqual(manager.activeProfileID, focusProfile.id)
        XCTAssertEqual(provider.currentActionCallCount, 0)
    }

    func testFocusDeactivationRestoresDisplayProfile() async throws {
        let displayProfile = makeProfile(name: "Display", associatedDisplayUUID: "display-a")
        let focusProfile = makeProfile(name: "Focus")
        try seedProfiles([displayProfile, focusProfile])

        defaults.set(focusProfile.id.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)

        let manager = ProfileManager(paths: paths)
        let service = FocusFilterService(defaults: defaults, currentProvider: MockFocusFilterCurrentProvider())
        let context = makeRuntimeContext(currentDisplayUUID: "display-a")

        manager.performSetup(runtimeContext: context, focusFilterService: service)
        service.performSetup { manager.hasProfile(id: $0) }
        await settle(manager)

        service.handleDeactivationNotification()
        await settle(manager)

        XCTAssertEqual(manager.activeProfileID, displayProfile.id)
    }

    func testDeletingRequestedFocusProfileClearsMirrorAndFallsBack() async throws {
        let displayProfile = makeProfile(name: "Display", associatedDisplayUUID: "display-a")
        let focusProfile = makeProfile(name: "Focus")
        try seedProfiles([displayProfile, focusProfile])

        defaults.set(focusProfile.id.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)

        let manager = ProfileManager(paths: paths)
        let service = FocusFilterService(defaults: defaults, currentProvider: MockFocusFilterCurrentProvider())
        let context = makeRuntimeContext(currentDisplayUUID: "display-a")

        manager.performSetup(runtimeContext: context, focusFilterService: service)
        service.performSetup { manager.hasProfile(id: $0) }
        await settle(manager)

        try manager.deleteProfile(id: focusProfile.id)
        await settle(manager)

        XCTAssertNil(defaults.string(forKey: FocusFilterConstants.requestedProfileIDKey))
        XCTAssertEqual(manager.activeProfileID, displayProfile.id)
    }

    func testDisplayAutoSwitchSkipsWhileFocusIsActiveAndRestoresOnDeactivation() async throws {
        let displayA = makeProfile(name: "Display A", associatedDisplayUUID: "display-a")
        let displayB = makeProfile(name: "Display B", associatedDisplayUUID: "display-b")
        let focusProfile = makeProfile(name: "Focus")
        try seedProfiles([displayA, displayB, focusProfile])

        var currentDisplayUUID = "display-a"
        let manager = ProfileManager(paths: paths)
        let service = FocusFilterService(defaults: defaults, currentProvider: MockFocusFilterCurrentProvider())
        let context = makeRuntimeContext(currentDisplayUUID: { currentDisplayUUID })

        manager.performSetup(runtimeContext: context, focusFilterService: service)
        service.performSetup { manager.hasProfile(id: $0) }
        await settle(manager)
        XCTAssertEqual(manager.activeProfileID, displayA.id)

        currentDisplayUUID = "display-b"
        await manager.handlePotentialDisplaySwitch(to: currentDisplayUUID)
        await settle(manager)
        XCTAssertEqual(manager.activeProfileID, displayB.id)

        defaults.set(focusProfile.id.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)
        service.handleActivationNotification(
            Notification(
                name: FocusFilterConstants.activationNotification,
                object: nil,
                userInfo: ["profileID": focusProfile.id.uuidString]
            )
        )
        await settle(manager)
        XCTAssertEqual(manager.activeProfileID, focusProfile.id)

        currentDisplayUUID = "display-a"
        await manager.handlePotentialDisplaySwitch(to: currentDisplayUUID)
        await settle(manager)
        XCTAssertEqual(manager.activeProfileID, focusProfile.id)

        service.handleDeactivationNotification()
        await settle(manager)
        XCTAssertEqual(manager.activeProfileID, displayA.id)
    }

    func testManualApplyAndHotkeyMappingsRemainAvailableWhileFocusIsActive() async throws {
        let displayProfile = makeProfile(name: "Display", associatedDisplayUUID: "display-a")
        let focusProfile = makeProfile(name: "Focus")
        let manualProfile = makeProfile(name: "Manual")
        try seedProfiles([displayProfile, focusProfile, manualProfile])

        defaults.set(focusProfile.id.uuidString, forKey: FocusFilterConstants.requestedProfileIDKey)

        let manager = ProfileManager(paths: paths)
        let discoverySession = MockProfileDiscoverySession()
        let service = FocusFilterService(defaults: defaults, currentProvider: MockFocusFilterCurrentProvider())
        let context = makeRuntimeContext(
            currentDisplayUUID: "display-a",
            discoverySession: discoverySession
        )

        manager.performSetup(runtimeContext: context, focusFilterService: service)
        service.performSetup { manager.hasProfile(id: $0) }
        await settle(manager)
        discoverySession.resetRefreshInvalidations()

        XCTAssertNotNil(manager.profileHotkeys[manualProfile.id])
        XCTAssertTrue(manager.hotkeyProfileMap.values.contains(manualProfile.id))

        try await manager.applyProfile(id: manualProfile.id)
        await settle(manager)

        XCTAssertEqual(manager.activeProfileID, manualProfile.id)
        XCTAssertEqual(service.state, .active(focusProfile.id))
        XCTAssertEqual(discoverySession.refreshInvalidations.last, .profileApplied)

        service.handleDeactivationNotification()
        await settle(manager)

        XCTAssertEqual(manager.activeProfileID, displayProfile.id)
    }

    private func seedProfiles(_ entries: [SeededProfile]) throws {
        try FileManager.default.createDirectory(
            at: paths.profilesDirectory,
            withIntermediateDirectories: true
        )

        let metadata = entries.map(\.metadata)
        let manifestEnvelope = PersistentEnvelope(schemaVersion: 3, payload: metadata)
        let manifestData = try encoder.encode(manifestEnvelope)
        try manifestData.write(to: paths.profilesManifestV3URL, options: .atomic)

        for entry in entries {
            let profileEnvelope = PersistentEnvelope(schemaVersion: 3, payload: entry.profile)
            let profileData = try encoder.encode(profileEnvelope)
            try profileData.write(
                to: paths.profileV3URL(for: entry.profile.id),
                options: .atomic
            )
        }
    }

    private func makeRuntimeContext(currentDisplayUUID: String) -> ProfileRuntimeContext {
        makeRuntimeContext(currentDisplayUUID: { currentDisplayUUID })
    }

    private func makeRuntimeContext(
        currentDisplayUUID: String,
        discoverySession: MockProfileDiscoverySession
    ) -> ProfileRuntimeContext {
        makeRuntimeContext(
            currentDisplayUUID: { currentDisplayUUID },
            discoverySession: discoverySession
        )
    }

    private func makeRuntimeContext(
        currentDisplayUUID: @escaping () -> String
    ) -> ProfileRuntimeContext {
        makeRuntimeContext(
            currentDisplayUUID: currentDisplayUUID,
            discoverySession: MockProfileDiscoverySession()
        )
    }

    private func makeRuntimeContext(
        currentDisplayUUID: @escaping () -> String,
        discoverySession: MockProfileDiscoverySession
    ) -> ProfileRuntimeContext {
        ProfileRuntimeContext(
            generalSettings: GeneralSettings(),
            advancedSettings: AdvancedSettings(),
            hotkeysSettings: HotkeysSettings(),
            displaySettings: DisplaySettingsManager(),
            appearanceManager: MenuBarAppearanceManager(),
            discoverySession: discoverySession,
            currentDisplayUUIDProvider: currentDisplayUUID
        )
    }

    private func makeProfile(
        name: String,
        associatedDisplayUUID: String? = nil
    ) -> SeededProfile {
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_710_000_300)
        let profile = Profile(
            id: UUID(),
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            content: ProfileContent(
                generalSettings: GeneralSettingsSnapshot.capture(from: GeneralSettings()),
                advancedSettings: AdvancedSettingsSnapshot.capture(from: AdvancedSettings()),
                hotkeys: [:],
                displayConfigurations: [:],
                appearanceConfiguration: .defaultConfiguration,
                menuBarLayout: MenuBarLayoutSnapshot(layout: .empty)
            )
        )

        var metadata = profile.metadata
        metadata.associatedDisplayUUID = associatedDisplayUUID
        metadata.associatedDisplayName = associatedDisplayUUID

        return SeededProfile(profile: profile, metadata: metadata)
    }

    private func settle(_ manager: ProfileManager) async {
        var consecutiveIdlePasses = 0

        while consecutiveIdlePasses < 2 {
            await Task.yield()

            if let layoutTask = manager.layoutTask {
                consecutiveIdlePasses = 0
                await layoutTask.value
            } else {
                consecutiveIdlePasses += 1
            }
        }
    }
}

private struct SeededProfile {
    let profile: Profile
    let metadata: ProfileMetadata

    var id: UUID {
        profile.id
    }
}

@MainActor
private final class MockProfileDiscoverySession: ProfileDiscoverySessionControlling {
    private(set) var layout = ProfileLayoutV3.empty
    private(set) var refreshInvalidations = [DiscoveryInvalidation]()

    func currentLayoutSnapshot() -> ProfileLayoutV3 {
        layout
    }

    func applyLayoutSnapshot(_ profileLayout: ProfileLayoutV3) async {
        layout = profileLayout
    }

    func refresh(_ invalidation: DiscoveryInvalidation) async {
        refreshInvalidations.append(invalidation)
    }

    func resetRefreshInvalidations() {
        refreshInvalidations.removeAll()
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
