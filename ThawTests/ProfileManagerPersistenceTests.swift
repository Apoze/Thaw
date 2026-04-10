//
//  ProfileManagerPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class ProfileManagerPersistenceTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ThawPersistencePaths!
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileManagerPersistenceTests.\(UUID().uuidString)", isDirectory: true)
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

    func testRenameProfilePreservesV3Envelope() throws {
        let profile = makeProfile(name: "Work")
        try seedProfile(profile, metadata: profile.metadata)

        let manager = ProfileManager(paths: paths)
        try manager.renameProfile(id: profile.id, to: "Renamed")

        let persisted = try decodeProfileEnvelope(id: profile.id)
        XCTAssertEqual(persisted.schemaVersion, 3)
        XCTAssertEqual(persisted.payload.name, "Renamed")
    }

    func testDuplicateProfileWritesV3Envelope() throws {
        let profile = makeProfile(name: "Work")
        try seedProfile(profile, metadata: profile.metadata)

        let manager = ProfileManager(paths: paths)
        try manager.duplicateProfile(id: profile.id, newName: "Copy")

        let duplicatedMetadata = try XCTUnwrap(
            manager.profiles.first(where: { $0.name == "Copy" })
        )
        let duplicated = try decodeProfileEnvelope(id: duplicatedMetadata.id)

        XCTAssertEqual(duplicated.schemaVersion, 3)
        XCTAssertEqual(duplicated.payload.name, "Copy")
    }

    func testExportDoesNotSerializeFocusRuntimeState() throws {
        let profile = makeProfile(name: "Work")
        try seedProfile(profile, metadata: profile.metadata)

        UserDefaults.standard.set(
            profile.id.uuidString,
            forKey: FocusFilterConstants.requestedProfileIDKey
        )
        UserDefaults.standard.set(
            true,
            forKey: FocusFilterConstants.hasKnownConfigurationKey
        )
        defer {
            UserDefaults.standard.removeObject(forKey: FocusFilterConstants.requestedProfileIDKey)
            UserDefaults.standard.removeObject(forKey: FocusFilterConstants.hasKnownConfigurationKey)
        }

        let manager = ProfileManager(paths: paths)
        let exported = try XCTUnwrap(manager.exportAllProfiles())

        XCTAssertFalse(exported.contains(FocusFilterConstants.requestedProfileIDKey))
        XCTAssertFalse(exported.contains(FocusFilterConstants.hasKnownConfigurationKey))
    }

    func testImportProfileDoesNotPersistFocusRuntimeStateIntoProfileFile() async throws {
        let manager = ProfileManager(paths: paths)
        let fixtureURL = try writeFixtureExportBundle()

        UserDefaults.standard.set("stale-profile-id", forKey: FocusFilterConstants.requestedProfileIDKey)
        UserDefaults.standard.set(true, forKey: FocusFilterConstants.hasKnownConfigurationKey)
        defer {
            UserDefaults.standard.removeObject(forKey: FocusFilterConstants.requestedProfileIDKey)
            UserDefaults.standard.removeObject(forKey: FocusFilterConstants.hasKnownConfigurationKey)
        }

        try manager.importProfile(from: fixtureURL)

        let metadata = try XCTUnwrap(manager.profiles.first)
        let importedEnvelope = try decodeProfileEnvelope(id: metadata.id)
        let registrySnapshot = await IdentityRegistry(paths: paths).snapshot()
        let importedLayout = importedEnvelope.payload.menuBarLayout.layout.defaultLayout
        let importedAliasEntry = try XCTUnwrap(importedLayout.aliasesByCanonicalID.first)
        let canonicalID = importedAliasEntry.key

        XCTAssertEqual(importedEnvelope.schemaVersion, 3)
        XCTAssertEqual(importedEnvelope.payload.name, "Fixture Profile")
        XCTAssertFalse(importedEnvelope.payload.menuBarLayout.layout.requiresCanonicalIDUpgrade)
        XCTAssertTrue(MenuExtraCanonicalID.isOpaquePersistentIdentifier(canonicalID))
        XCTAssertEqual(importedLayout.aliasesByCanonicalID.count, 1)
        XCTAssertEqual(importedAliasEntry.value, "Fixture Alias")
        XCTAssertEqual(importedLayout.groupsByCanonicalID[canonicalID], .archive)
        XCTAssertEqual(
            importedLayout.orderedCanonicalIDsByGroup[.archive],
            [canonicalID]
        )
        XCTAssertTrue(registrySnapshot.records.contains { $0.canonicalID.rawValue == canonicalID })
        let profileData = try Data(contentsOf: paths.profileV3URL(for: metadata.id))
        let profileJSON = String(decoding: profileData, as: UTF8.self)
        XCTAssertTrue(profileJSON.contains("\"layout\""))
        XCTAssertFalse(profileJSON.contains("\"virtualLayout\""))
        XCTAssertFalse(profileJSON.contains(FocusFilterConstants.requestedProfileIDKey))
        XCTAssertFalse(profileJSON.contains(FocusFilterConstants.hasKnownConfigurationKey))
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: FocusFilterConstants.requestedProfileIDKey),
            "stale-profile-id"
        )
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FocusFilterConstants.hasKnownConfigurationKey))
    }

    private func seedProfile(_ profile: Profile, metadata: ProfileMetadata) throws {
        try FileManager.default.createDirectory(at: paths.profilesDirectory, withIntermediateDirectories: true)

        let manifestEnvelope = PersistentEnvelope(schemaVersion: 3, payload: [metadata])
        let manifestData = try encoder.encode(manifestEnvelope)
        try manifestData.write(to: paths.profilesManifestV3URL, options: .atomic)

        let profileEnvelope = PersistentEnvelope(schemaVersion: 3, payload: profile)
        let profileData = try encoder.encode(profileEnvelope)
        try profileData.write(to: paths.profileV3URL(for: profile.id), options: .atomic)
    }

    private func decodeProfileEnvelope(id: UUID) throws -> PersistentEnvelope<Profile> {
        let data = try Data(contentsOf: paths.profileV3URL(for: id))
        return try decoder.decode(PersistentEnvelope<Profile>.self, from: data)
    }

    private func makeProfile(name: String) -> Profile {
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_710_000_300)
        return Profile(
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
                menuBarLayout: MenuBarLayoutSnapshot(
                    layout: ProfileLayoutV3(
                        defaultLayout: LayoutStateV3(
                            groupsByCanonicalID: ["alpha": .hidden],
                            orderedCanonicalIDsByGroup: [.hidden: ["alpha"]],
                            aliasesByCanonicalID: ["alpha": "Alpha"]
                        )
                    )
                )
            )
        )
    }

    private func writeFixtureExportBundle() throws -> URL {
        let url = tempDirectory.appendingPathComponent("profile-export-bundle-v1.json")
        let profile = Profile(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "Fixture Profile",
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_300),
            content: ProfileContent(
                generalSettings: GeneralSettingsSnapshot(
                    showIceIcon: Defaults.DefaultValue.showIceIcon,
                    iceIcon: Defaults.DefaultValue.iceIcon,
                    lastCustomIceIcon: nil,
                    customIceIconIsTemplate: Defaults.DefaultValue.customIceIconIsTemplate,
                    useIceBar: Defaults.DefaultValue.useIceBar,
                    useIceBarOnlyOnNotchedDisplay: Defaults.DefaultValue.useIceBarOnlyOnNotchedDisplay,
                    iceBarLocation: Defaults.DefaultValue.iceBarLocation,
                    iceBarLocationOnHotkey: Defaults.DefaultValue.iceBarLocationOnHotkey,
                    showOnClick: Defaults.DefaultValue.showOnClick,
                    showOnDoubleClick: Defaults.DefaultValue.showOnDoubleClick,
                    showOnHover: Defaults.DefaultValue.showOnHover,
                    showOnScroll: Defaults.DefaultValue.showOnScroll,
                    autoRehide: Defaults.DefaultValue.autoRehide,
                    rehideStrategyRawValue: Defaults.DefaultValue.rehideStrategy.rawValue,
                    rehideInterval: Defaults.DefaultValue.rehideInterval
                ),
                advancedSettings: AdvancedSettingsSnapshot(
                    enableAlwaysHiddenSection: Defaults.DefaultValue.enableAlwaysHiddenSection,
                    sectionDividerStyle: Defaults.DefaultValue.sectionDividerStyle.rawValue,
                    enableSecondaryContextMenu: Defaults.DefaultValue.enableSecondaryContextMenu,
                    showOnHoverDelay: Defaults.DefaultValue.showOnHoverDelay,
                    tooltipDelay: Defaults.DefaultValue.tooltipDelay,
                    showMenuBarTooltips: Defaults.DefaultValue.showMenuBarTooltips,
                    iconRefreshInterval: Defaults.DefaultValue.iconRefreshInterval,
                    enableDiagnosticLogging: Defaults.DefaultValue.enableDiagnosticLogging
                ),
                hotkeys: [:],
                displayConfigurations: [:],
                appearanceConfiguration: .defaultConfiguration,
                menuBarLayout: MenuBarLayoutSnapshot(
                    layout: ProfileLayoutV3(
                        defaultLayout: LayoutStateV3(
                            groupsByCanonicalID: [
                                "com.example.fixture::fixture-key::AXMenuBarItem": .archive,
                            ],
                            orderedCanonicalIDsByGroup: [
                                .archive: ["com.example.fixture::fixture-key::AXMenuBarItem"],
                            ],
                            aliasesByCanonicalID: [
                                "com.example.fixture::fixture-key::AXMenuBarItem": "Fixture Alias",
                            ]
                        )
                    )
                )
            )
        )
        let bundle = ProfileExportBundle(entries: [
            ProfileExportEntry(
                profile: profile,
                associatedDisplayUUID: "fixture-display-uuid",
                associatedDisplayName: "Fixture Display"
            )
        ])
        let data = try encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
        return url
    }
}
