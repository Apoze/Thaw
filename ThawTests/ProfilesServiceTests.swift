//
//  ProfilesServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class ProfilesServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ThawPersistencePaths!
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfilesServiceTests.\(UUID().uuidString)", isDirectory: true)
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

    func testProfilesServiceRenamesPersistedProfileWithoutProfileManagerPersistencePath() throws {
        let profile = makeProfile(name: "Work")
        try seedProfile(profile, metadata: profile.metadata)

        let service = ProfilesService(paths: paths)
        try service.renameProfile(id: profile.id, to: "Renamed")

        let persisted = try decodeProfileEnvelope(id: profile.id)
        XCTAssertEqual(persisted.schemaVersion, 3)
        XCTAssertEqual(persisted.payload.name, "Renamed")
        XCTAssertEqual(service.profiles.first?.name, "Renamed")
    }

    func testProfileManagerSourceIsFacadeOverProfilesService() throws {
        let source = try ThawTestResourceSupport.sourceText(named: "ProfileManager")

        XCTAssertTrue(source.contains("let service: ProfilesService"))
        XCTAssertFalse(source.contains("PersistentEnvelope<Profile>"))
        XCTAssertFalse(source.contains("PersistentEnvelope<[ProfileMetadata]>"))
        XCTAssertFalse(source.contains("FocusFilterState"))
        XCTAssertFalse(source.contains("ProfileRuntimeContext(appState:"))
        XCTAssertFalse(source.contains("func performSetup(with appState:"))
    }

    func testProfilesServiceSourceUsesRuntimeContextSetupOnly() throws {
        let source = try ThawTestResourceSupport.sourceText(named: "ProfilesService")

        XCTAssertTrue(source.contains("runtimeContext: ProfileRuntimeContext"))
        XCTAssertFalse(source.contains("func performSetup(with appState:"))
        XCTAssertFalse(source.contains("ProfileRuntimeContext(appState:"))
    }

    func testRuntimeAdaptersDependOnProfilesServiceInsteadOfProfileManager() throws {
        let hotkeySource = try ThawTestResourceSupport.sourceText(named: "HotkeySessionAdapter")
        let menuSource = try ThawTestResourceSupport.sourceText(named: "MenuBarSessionAdapter")

        XCTAssertTrue(hotkeySource.contains("let profilesService: ProfilesService"))
        XCTAssertFalse(hotkeySource.contains("let profileManager: ProfileManager"))
        XCTAssertTrue(menuSource.contains("private let profilesService: ProfilesService"))
        XCTAssertFalse(menuSource.contains("private let profileManager: ProfileManager"))
    }

    private func seedProfile(_ profile: Profile, metadata: ProfileMetadata) throws {
        try FileManager.default.createDirectory(at: paths.profilesDirectory, withIntermediateDirectories: true)

        let manifestEnvelope = PersistentEnvelope(schemaVersion: 3, payload: [metadata])
        try encoder.encode(manifestEnvelope).write(to: paths.profilesManifestV3URL, options: .atomic)

        let profileEnvelope = PersistentEnvelope(schemaVersion: 3, payload: profile)
        try encoder.encode(profileEnvelope).write(to: paths.profileV3URL(for: profile.id), options: .atomic)
    }

    private func decodeProfileEnvelope(id: UUID) throws -> PersistentEnvelope<Profile> {
        let data = try Data(contentsOf: paths.profileV3URL(for: id))
        return try decoder.decode(PersistentEnvelope<Profile>.self, from: data)
    }

    private func makeProfile(name: String) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_300),
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
}
