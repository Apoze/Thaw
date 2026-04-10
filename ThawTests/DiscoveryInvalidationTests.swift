//
//  DiscoveryInvalidationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import XCTest
@testable import Thaw

@MainActor
final class DiscoveryInvalidationTests: XCTestCase {
    func testSearchAndLayoutAdaptersUseTypedInvalidations() async {
        let descriptor = makeDescriptor(
            bundleID: "com.example.discovery",
            title: "Discovery Item",
            role: "AXMenuBarItem",
            stableKeyBasis: "discovery-panel"
        )

        let runtime = StubDiscoverySession(
            snapshot: DiscoverySnapshot(descriptors: [descriptor], generatedAt: .init(timeIntervalSince1970: 1))
        )
        let searchAdapter = MenuBarSearchAdapter(
            discoverySession: runtime,
            panelInteractionController: RecordingPanelInteractionController()
        )
        let layoutAdapter = MenuBarLayoutEditorAdapter(discoverySession: runtime)

        await searchAdapter.refresh()
        await layoutAdapter.refresh()
        await layoutAdapter.resetSuggestedLayout()

        XCTAssertEqual(
            runtime.refreshInvalidations,
            [
                .panelPreparation,
                .layoutEditorPresented,
                .layoutReset,
            ]
        )
    }

    func testActivationCommandBuildsTypedFollowUpInvalidations() {
        let canonicalID = MenuExtraCanonicalID(rawValue: "opaque-id")

        XCTAssertEqual(
            ActivationCommand(
                canonicalID: canonicalID,
                surface: .quickAccess,
                intent: .primary
            ).followUpInvalidation,
            .activationFollowUp(
                canonicalID: canonicalID,
                surface: .quickAccess,
                intent: .primary
            )
        )

        XCTAssertEqual(
            ActivationCommand(
                canonicalID: canonicalID,
                surface: .search,
                intent: .automatic
            ).followUpInvalidation,
            .activationFollowUp(
                canonicalID: canonicalID,
                surface: .search,
                intent: .automatic
            )
        )
    }

    func testProfileApplyUsesTypedProfileInvalidation() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoveryInvalidationTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let paths = ThawPersistencePaths(rootDirectory: tempDirectory)
        let manager = ProfileManager(paths: paths)
        let runtime = RecordingProfileDiscoverySession()
        let context = ProfileRuntimeContext(
            generalSettings: GeneralSettings(),
            advancedSettings: AdvancedSettings(),
            hotkeysSettings: HotkeysSettings(),
            displaySettings: DisplaySettingsManager(),
            appearanceManager: MenuBarAppearanceManager(),
            discoverySession: runtime,
            currentDisplayUUIDProvider: { nil }
        )

        let profile = Profile(
            name: "Discovery",
            content: ProfileContent(
                generalSettings: GeneralSettingsSnapshot.capture(from: GeneralSettings()),
                advancedSettings: AdvancedSettingsSnapshot.capture(from: AdvancedSettings()),
                hotkeys: [:],
                displayConfigurations: [:],
                appearanceConfiguration: .defaultConfiguration,
                menuBarLayout: MenuBarLayoutSnapshot(layout: .empty)
            )
        )

        manager.performSetup(runtimeContext: context, focusFilterService: FocusFilterService())
        try seedProfile(profile, in: paths)

        try await manager.applyProfile(id: profile.id)
        await manager.layoutTask?.value

        XCTAssertEqual(runtime.refreshInvalidations, [.profileApplied])
    }

    func testActiveRuntimeSourcesDoNotUseLegacyRefreshReasons() throws {
        try assertSource(
            named: SourceResource.discoveryRuntime,
            doesNotContain: [
                "refresh(reason:",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarSearchAdapter,
            doesNotContain: [
                "refresh(reason:",
                "\"search-panel-show\"",
            ]
        )

        try assertSource(
            named: SourceResource.menuBarLayoutEditorAdapter,
            doesNotContain: [
                "refresh(reason:",
                "\"layout-editor-show\"",
                "\"layout-reset\"",
            ]
        )

        try assertSource(
            named: SourceResource.panelRuntime,
            doesNotContain: [
                "refresh(reason:",
                "\"panel-show\"",
                "\"search-panel-show\"",
            ]
        )

        try assertSource(
            named: SourceResource.iceBarAdapter,
            doesNotContain: [
                "refresh(reason:",
            ]
        )

        try assertSource(
            named: SourceResource.profileManager,
            doesNotContain: [
                "refresh(reason:",
                "\"profile-apply\"",
            ]
        )
    }

    private func assertSource(
        named resourceName: String,
        doesNotContain forbiddenTokens: [String]
    ) throws {
        let source = try ThawTestResourceSupport.sourceText(named: resourceName)

        for token in forbiddenTokens {
            XCTAssertFalse(source.contains(token), "Unexpected \(token) in \(resourceName).swift")
        }
    }

    private func seedProfile(_ profile: Profile, in paths: ThawPersistencePaths) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: paths.profilesDirectory, withIntermediateDirectories: true)
        let metadata = ProfileMetadata(
            id: profile.id,
            name: profile.name,
            createdAt: profile.createdAt,
            modifiedAt: profile.modifiedAt
        )
        let manifest = PersistentEnvelope(schemaVersion: 3, payload: [metadata])
        try encoder.encode(manifest).write(to: paths.profilesManifestV3URL, options: .atomic)
        let envelope = PersistentEnvelope(schemaVersion: 3, payload: profile)
        try encoder.encode(envelope).write(to: paths.profileV3URL(for: profile.id), options: .atomic)
    }

    private func makeDescriptor(
        bundleID: String,
        title: String,
        role: String,
        stableKeyBasis: String
    ) -> MenuExtraDescriptor {
        let identity = MenuExtraIdentity.make(
            bundleID: bundleID,
            title: title,
            role: role,
            stableKeyBasis: stableKeyBasis
        )

        return MenuExtraDescriptor(
            canonicalID: .generated(),
            identity: identity,
            ownerPID: 42,
            bundleIdentifier: bundleID,
            bundleURL: nil,
            applicationName: bundleID,
            title: title,
            rawRole: role,
            frame: .zero,
            displayID: nil,
            displayUUID: nil,
            capability: .axPress,
            group: .hidden,
            customName: nil
        )
    }
}

private enum SourceResource {
    static let discoveryRuntime = "DiscoveryRuntime"
    static let menuBarSearchAdapter = "MenuBarSearchAdapter"
    static let menuBarLayoutEditorAdapter = "MenuBarLayoutEditorAdapter"
    static let panelRuntime = "PanelRuntime"
    static let iceBarAdapter = "IceBarAdapter"
    static let profileManager = "ProfileManager"
}

private final class RecordingPanelInteractionController: PanelInteractionHandling {
    func interactWithPanel(using command: ActivationCommand) async -> PanelInteractionResult {
        _ = command
        return PanelInteractionResult(outcome: .openedUI, disposition: .dismiss)
    }
}

@MainActor
private final class RecordingProfileDiscoverySession: ProfileDiscoverySessionControlling {
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
}
