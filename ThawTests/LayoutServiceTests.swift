//
//  LayoutServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

final class LayoutServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ThawPersistencePaths!
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutServiceTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        decoder = nil
        encoder = nil
        paths = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testLoadKeepsLegacyV2EnvelopeOnDiskWhileHydratingV3Snapshot() throws {
        let legacyLayout = ProfileLayoutV2(
            groupsByIdentityID: ["legacy-alpha": .archive],
            orderedIdentityIDsByGroup: [.archive: ["legacy-alpha"]],
            customNamesByIdentityID: ["legacy-alpha": "Alpha"]
        )
        let legacyEnvelope = PersistentEnvelope(schemaVersion: 3, payload: legacyLayout)
        let legacyData = try encoder.encode(legacyEnvelope)
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        try legacyData.write(to: paths.layoutV3URL, options: .atomic)

        let service = LayoutService(paths: paths)
        let snapshot = service.snapshot()
        let persistedData = try Data(contentsOf: paths.layoutV3URL)
        let expectedLayout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: ["legacy-alpha": .archive],
                orderedCanonicalIDsByGroup: [.archive: ["legacy-alpha"]],
                aliasesByCanonicalID: ["legacy-alpha": "Alpha"]
            )
        )

        XCTAssertEqual(snapshot, expectedLayout)
        XCTAssertEqual(persistedData, legacyData)
        XCTAssertEqual(
            try decoder.decode(PersistentEnvelope<ProfileLayoutV2>.self, from: persistedData).payload,
            legacyLayout
        )
    }

    func testReconcileKeepsCanonicalLayoutCanonicalWithoutLiveMigration() {
        let descriptor = makeDescriptor(
            bundleID: "com.example.alpha",
            title: "Alpha",
            stableKeyBasis: "legacy-alpha",
            canonicalID: MenuExtraCanonicalID(rawValue: "opaque-canonical-alpha")
        )
        XCTAssertNotEqual(descriptor.identity.id, descriptor.canonicalID.rawValue)

        let canonicalLayout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: [descriptor.canonicalID.rawValue: .archive],
                orderedCanonicalIDsByGroup: [.archive: [descriptor.canonicalID.rawValue]],
                aliasesByCanonicalID: [descriptor.canonicalID.rawValue: "Alpha Alias"]
            )
        )
        let service = LayoutService(paths: paths)
        service.apply(canonicalLayout)

        let summary = service.reconcile(with: [descriptor])
        let snapshot = service.snapshot()

        XCTAssertEqual(summary.liveDescriptorCount, 1)
        XCTAssertEqual(snapshot.groupsByCanonicalID, canonicalLayout.groupsByCanonicalID)
        XCTAssertEqual(snapshot.customNamesByCanonicalID, canonicalLayout.customNamesByCanonicalID)
        XCTAssertEqual(
            snapshot.orderedCanonicalIDsByGroup[.archive],
            canonicalLayout.orderedCanonicalIDsByGroup[.archive]
        )
        XCTAssertNil(snapshot.groupsByCanonicalID[descriptor.identity.id])
        XCTAssertNil(snapshot.customNamesByCanonicalID[descriptor.identity.id])
    }

    private func makeDescriptor(
        bundleID: String,
        title: String,
        stableKeyBasis: String,
        canonicalID: MenuExtraCanonicalID
    ) -> MenuExtraDescriptor {
        let identity = MenuExtraIdentity.make(
            bundleID: bundleID,
            title: title,
            role: "AXMenuBarItem",
            stableKeyBasis: stableKeyBasis
        )

        return MenuExtraDescriptor(
            canonicalID: canonicalID,
            identity: identity,
            ownerPID: 99,
            bundleIdentifier: bundleID,
            bundleURL: nil,
            applicationName: bundleID,
            title: title,
            rawRole: "AXMenuBarItem",
            frame: .init(x: 0, y: 0, width: 18, height: 18),
            displayID: nil,
            displayUUID: nil,
            capability: .axPress,
            group: .hidden,
            customName: nil
        )
    }
}
