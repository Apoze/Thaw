//
//  PersistenceMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ThawPersistencePaths!
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceMigrationTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        decoder = nil
        encoder = nil
        paths = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testFixtureProfileExportBundleImportsAsV3ProfileFiles() async throws {
        let manager = ProfileManager(paths: paths)
        let fixtureURL = fixtureURL(named: "profile-export-bundle-v1.json")

        try manager.importProfile(from: fixtureURL)

        let metadata = try XCTUnwrap(manager.profiles.first)
        let profileEnvelope = try decodeProfileEnvelope(id: metadata.id)
        let registrySnapshot = await IdentityRegistry(paths: paths).snapshot()
        let canonicalID = try XCTUnwrap(registrySnapshot.records.first?.canonicalID.rawValue)
        let importedLayout = profileEnvelope.payload.menuBarLayout.layout.defaultLayout

        XCTAssertEqual(profileEnvelope.schemaVersion, 3)
        XCTAssertEqual(profileEnvelope.payload.name, "Fixture Profile")
        XCTAssertFalse(profileEnvelope.payload.menuBarLayout.layout.requiresCanonicalIDUpgrade)
        XCTAssertTrue(MenuExtraCanonicalID.isOpaquePersistentIdentifier(canonicalID))
        XCTAssertEqual(importedLayout.groupsByCanonicalID[canonicalID], .archive)
        XCTAssertEqual(importedLayout.aliasesByCanonicalID[canonicalID], "Fixture Alias")
        XCTAssertEqual(importedLayout.orderedCanonicalIDsByGroup[.archive], [canonicalID])

        let exported = try XCTUnwrap(manager.exportAllProfiles())
        let bundle = try decoder.decode(ProfileExportBundle.self, from: Data(exported.utf8))

        XCTAssertEqual(bundle.version, 1)
        XCTAssertEqual(bundle.entries.count, 1)
        XCTAssertEqual(bundle.entries[0].profile.name, "Fixture Profile")
        XCTAssertEqual(bundle.entries[0].associatedDisplayUUID, "fixture-display-uuid")
        XCTAssertEqual(bundle.entries[0].associatedDisplayName, "Fixture Display")
        XCTAssertEqual(
            bundle.entries[0].profile.menuBarLayout.layout.defaultLayout.aliasesByCanonicalID[canonicalID],
            "Fixture Alias"
        )
        XCTAssertEqual(
            bundle.entries[0].profile.menuBarLayout.layout.defaultLayout.orderedCanonicalIDsByGroup[.archive],
            [canonicalID]
        )

        let importedData = try Data(contentsOf: paths.profileV3URL(for: metadata.id))
        let importedJSONString = try XCTUnwrap(String(data: importedData, encoding: .utf8))
        XCTAssertTrue(importedJSONString.contains("\"layout\""))
        XCTAssertFalse(importedJSONString.contains("\"virtualLayout\""))
    }

    func testProfileExportBundleFixtureRoundTripsLayoutSnapshot() throws {
        let data = try Data(contentsOf: fixtureURL(named: "profile-export-bundle-v1.json"))
        let bundle = try decoder.decode(ProfileExportBundle.self, from: data)

        let layout = bundle.entries[0].profile.menuBarLayout.layout.defaultLayout
        let expectedLegacyLayout = ProfileLayoutV2(
            groupsByIdentityID: [
                "com.example.fixture::fixture-key::AXMenuBarItem": .archive
            ],
            orderedIdentityIDsByGroup: [
                .archive: ["com.example.fixture::fixture-key::AXMenuBarItem"]
            ],
            customNamesByIdentityID: [
                "com.example.fixture::fixture-key::AXMenuBarItem": "Fixture Alias"
            ]
        )

        XCTAssertEqual(
            ProfileLayoutMigration.legacyCompatibilityLayout(from: ProfileLayoutV3(defaultLayout: layout)),
            expectedLegacyLayout
        )
    }

    func testFixturePersistedV3ProfileFilesLoadFromDisk() async throws {
        let envelopeURL = fixtureURL(named: "profile-v3-envelope.json")
        let envelopeData = try Data(contentsOf: envelopeURL)
        let envelope = try decoder.decode(PersistentEnvelope<Profile>.self, from: envelopeData)

        try fileManager.createDirectory(
            at: paths.profilesDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(
            at: fixtureURL(named: "profiles-manifest-v3.json"),
            to: paths.profilesManifestV3URL
        )
        try envelopeData.write(
            to: paths.profileV3URL(for: envelope.payload.id),
            options: .atomic
        )

        let manager = ProfileManager(paths: paths)
        let metadata = try XCTUnwrap(manager.profiles.first)
        let profile = try manager.loadProfile(id: metadata.id)
        let registrySnapshot = await IdentityRegistry(paths: paths).snapshot()
        let importedCanonicalID = try XCTUnwrap(registrySnapshot.records.first?.canonicalID.rawValue)

        XCTAssertEqual(metadata.name, "Fixture Profile")
        XCTAssertEqual(metadata.associatedDisplayUUID, "fixture-display-uuid")
        XCTAssertEqual(metadata.associatedDisplayName, "Fixture Display")
        XCTAssertEqual(profile.id, envelope.payload.id)
        XCTAssertFalse(profile.menuBarLayout.layout.requiresCanonicalIDUpgrade)
        XCTAssertTrue(MenuExtraCanonicalID.isOpaquePersistentIdentifier(importedCanonicalID))
        XCTAssertEqual(
            profile.menuBarLayout.layout.defaultLayout.groupsByCanonicalID[importedCanonicalID],
            .archive
        )
        XCTAssertEqual(
            profile.menuBarLayout.layout.defaultLayout.aliasesByCanonicalID[importedCanonicalID],
            "Fixture Alias"
        )
        XCTAssertEqual(
            profile.menuBarLayout.layout.defaultLayout.orderedCanonicalIDsByGroup[.archive],
            [importedCanonicalID]
        )
    }

    func testMenuBarLayoutSnapshotDecodesBothLayoutAndLegacyVirtualLayoutKeys() throws {
        let legacyLayout = ProfileLayoutV2(
            groupsByIdentityID: ["legacy-alpha": .archive],
            orderedIdentityIDsByGroup: [.archive: ["legacy-alpha"]],
            customNamesByIdentityID: ["legacy-alpha": "Alpha Alias"]
        )
        struct LegacyPayload: Codable {
            let virtualLayout: ProfileLayoutV2
        }

        struct V3Payload: Codable {
            let layout: ProfileLayoutV3
        }

        let legacyData = try encoder.encode(LegacyPayload(virtualLayout: legacyLayout))
        let v3Data = try encoder.encode(
            V3Payload(layout: ProfileLayoutMigration.migrate(legacyLayout))
        )

        let decodedLegacy = try decoder.decode(
            MenuBarLayoutSnapshot.self,
            from: legacyData
        )
        let decodedV3 = try decoder.decode(
            MenuBarLayoutSnapshot.self,
            from: v3Data
        )

        XCTAssertEqual(
            ProfileLayoutMigration.legacyCompatibilityLayout(from: decodedLegacy.layout),
            legacyLayout
        )
        XCTAssertEqual(
            ProfileLayoutMigration.legacyCompatibilityLayout(from: decodedV3.layout),
            legacyLayout
        )
    }

    func testImportedFixtureProfileRoundTripsLegacyLayoutThroughReaderBoundary() throws {
        let bundleData = try Data(contentsOf: fixtureURL(named: "profile-export-bundle-v1.json"))
        let bundle = try decoder.decode(ProfileExportBundle.self, from: bundleData)
        let importedLayout = bundle.entries[0].profile.menuBarLayout.layout

        XCTAssertEqual(
            ProfileLayoutMigration.legacyCompatibilityLayout(from: importedLayout),
            ProfileLayoutV2(
                groupsByIdentityID: [
                    "com.example.fixture::fixture-key::AXMenuBarItem": .archive
                ],
                orderedIdentityIDsByGroup: [
                    .archive: ["com.example.fixture::fixture-key::AXMenuBarItem"]
                ],
                customNamesByIdentityID: [
                    "com.example.fixture::fixture-key::AXMenuBarItem": "Fixture Alias"
                ]
            )
        )
    }

    func testLegacyProfileEnvelopeLoadsAndReencodesWithoutLoss() throws {
        let profileID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_710_000_300)
        let legacyLayout = ProfileLayoutV2(
            groupsByIdentityID: [
                "11111111-1111-1111-1111-111111111111": .archive
            ],
            orderedIdentityIDsByGroup: [
                .archive: ["11111111-1111-1111-1111-111111111111"]
            ],
            customNamesByIdentityID: [
                "11111111-1111-1111-1111-111111111111": "Legacy Alpha"
            ]
        )
        let legacyProfile = LegacyProfilePayload(
            id: profileID,
            name: "Legacy Profile",
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            generalSettings: GeneralSettingsSnapshot(
                showIceIcon: false,
                iceIcon: Defaults.DefaultValue.iceIcon,
                lastCustomIceIcon: nil,
                customIceIconIsTemplate: true,
                useIceBar: true,
                useIceBarOnlyOnNotchedDisplay: true,
                iceBarLocation: .mousePointer,
                iceBarLocationOnHotkey: true,
                showOnClick: false,
                showOnDoubleClick: true,
                showOnHover: true,
                showOnScroll: false,
                autoRehide: false,
                rehideStrategyRawValue: RehideStrategy.timed.rawValue,
                rehideInterval: 42
            ),
            advancedSettings: AdvancedSettingsSnapshot(
                enableAlwaysHiddenSection: true,
                sectionDividerStyle: SectionDividerStyle.chevron.rawValue,
                enableSecondaryContextMenu: false,
                showOnHoverDelay: 0.4,
                tooltipDelay: 0.9,
                showMenuBarTooltips: true,
                iconRefreshInterval: 1.2,
                enableDiagnosticLogging: true
            ),
            hotkeys: [
                "profileApply": Data([0xde, 0xad, 0xbe, 0xef])
            ],
            displayConfigurations: [
                "fixture-display-uuid": DisplayIceBarConfiguration(
                    useIceBar: true,
                    iceBarLocation: .iceIcon,
                    alwaysShowHiddenItems: true
                )
            ],
            appearanceConfiguration: MenuBarAppearanceConfigurationV2.defaultConfiguration,
            menuBarLayout: LegacyMenuBarLayoutPayload(virtualLayout: legacyLayout)
        )
        let legacyEnvelope = PersistentEnvelope(
            schemaVersion: 2,
            payload: legacyProfile,
            createdAt: createdAt,
            updatedAt: modifiedAt
        )

        try fileManager.createDirectory(
            at: paths.profilesDirectory,
            withIntermediateDirectories: true
        )
        try encoder.encode(legacyEnvelope).write(to: paths.profileV3URL(for: profileID), options: .atomic)

        let manager = ProfileManager(paths: paths)
        let loadedProfile = try manager.loadProfile(id: profileID)

        XCTAssertEqual(loadedProfile.id, profileID)
        XCTAssertEqual(loadedProfile.name, "Legacy Profile")
        XCTAssertEqual(loadedProfile.createdAt, createdAt)
        XCTAssertEqual(loadedProfile.modifiedAt, modifiedAt)
        XCTAssertEqual(loadedProfile.generalSettings.showIceIcon, false)
        XCTAssertEqual(loadedProfile.generalSettings.useIceBar, true)
        XCTAssertEqual(loadedProfile.generalSettings.iceBarLocation, .mousePointer)
        XCTAssertEqual(loadedProfile.advancedSettings.enableAlwaysHiddenSection, true)
        XCTAssertEqual(loadedProfile.advancedSettings.enableDiagnosticLogging, true)
        XCTAssertEqual(loadedProfile.hotkeys["profileApply"], Data([0xde, 0xad, 0xbe, 0xef]))
        XCTAssertEqual(
            loadedProfile.displayConfigurations["fixture-display-uuid"],
            DisplayIceBarConfiguration(
                useIceBar: true,
                iceBarLocation: .iceIcon,
                alwaysShowHiddenItems: true
            )
        )
        XCTAssertEqual(
            ProfileLayoutMigration.legacyCompatibilityLayout(from: loadedProfile.menuBarLayout.layout),
            legacyLayout
        )

        let reencoded = PersistentEnvelope(
            schemaVersion: 3,
            payload: loadedProfile,
            createdAt: createdAt,
            updatedAt: modifiedAt
        )
        try encoder.encode(reencoded).write(to: paths.profileV3URL(for: profileID), options: .atomic)

        let reloadedProfile = try manager.loadProfile(id: profileID)

        XCTAssertEqual(reloadedProfile.id, loadedProfile.id)
        XCTAssertEqual(reloadedProfile.name, loadedProfile.name)
        XCTAssertEqual(reloadedProfile.createdAt, loadedProfile.createdAt)
        XCTAssertEqual(reloadedProfile.modifiedAt, loadedProfile.modifiedAt)
        XCTAssertEqual(reloadedProfile.generalSettings.showIceIcon, loadedProfile.generalSettings.showIceIcon)
        XCTAssertEqual(reloadedProfile.generalSettings.useIceBar, loadedProfile.generalSettings.useIceBar)
        XCTAssertEqual(
            reloadedProfile.advancedSettings.enableAlwaysHiddenSection,
            loadedProfile.advancedSettings.enableAlwaysHiddenSection
        )
        XCTAssertEqual(reloadedProfile.hotkeys, loadedProfile.hotkeys)
        XCTAssertEqual(reloadedProfile.displayConfigurations, loadedProfile.displayConfigurations)
        XCTAssertEqual(reloadedProfile.menuBarLayout.layout, loadedProfile.menuBarLayout.layout)

        let rewrittenData = try Data(contentsOf: paths.profileV3URL(for: profileID))
        let rewrittenEnvelope = try decoder.decode(PersistentEnvelope<Profile>.self, from: rewrittenData)
        XCTAssertEqual(rewrittenEnvelope.schemaVersion, 3)
        XCTAssertEqual(rewrittenEnvelope.payload.menuBarLayout.layout, loadedProfile.menuBarLayout.layout)
    }

    private var fileManager: FileManager {
        .default
    }

    private func fixtureURL(named name: String) -> URL {
        let resourceName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        return ThawTestResourceSupport.fixtureURL(named: resourceName)
    }

    private func decodeProfileEnvelope(id: UUID) throws -> PersistentEnvelope<Profile> {
        let data = try Data(contentsOf: paths.profileV3URL(for: id))
        return try decoder.decode(PersistentEnvelope<Profile>.self, from: data)
    }
}

private struct LegacyMenuBarLayoutPayload: Codable {
    let virtualLayout: ProfileLayoutV2
}

private struct LegacyProfilePayload: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let generalSettings: GeneralSettingsSnapshot
    let advancedSettings: AdvancedSettingsSnapshot
    let hotkeys: [String: Data]
    let displayConfigurations: [String: DisplayIceBarConfiguration]
    let appearanceConfiguration: MenuBarAppearanceConfigurationV2
    let menuBarLayout: LegacyMenuBarLayoutPayload
}
