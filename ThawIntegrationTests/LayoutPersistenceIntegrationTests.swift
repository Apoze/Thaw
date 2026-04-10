//
//  LayoutPersistenceIntegrationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class LayoutPersistenceIntegrationTests: XCTestCase {
    private var tempDirectory: URL?
    private var paths: ThawPersistencePaths?
    private var encoder: JSONEncoder?

    override func setUp() {
        super.setUp()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutPersistenceIntegrationTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        self.tempDirectory = tempDirectory
        paths = ThawPersistencePaths(rootDirectory: tempDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        encoder = nil
        paths = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testPersistedV3LayoutLoadsFromDisk() throws {
        guard let paths, let encoder else {
            XCTFail("Missing integration test persistence dependencies")
            return
        }
        let layout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: ["alpha": .archive],
                orderedCanonicalIDsByGroup: [.archive: ["alpha"]],
                aliasesByCanonicalID: ["alpha": "Alpha"]
            )
        )
        let envelope = PersistentEnvelope(schemaVersion: 3, payload: layout)
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        try encoder.encode(envelope).write(to: paths.layoutV3URL, options: .atomic)

        let service = LayoutService(paths: paths)
        let snapshot = service.snapshot()

        XCTAssertEqual(snapshot.defaultLayout.groupsByCanonicalID, layout.defaultLayout.groupsByCanonicalID)
        XCTAssertEqual(
            snapshot.defaultLayout.orderedCanonicalIDsByGroup,
            layout.defaultLayout.orderedCanonicalIDsByGroup
        )
        XCTAssertEqual(snapshot.defaultLayout.aliasesByCanonicalID, layout.defaultLayout.aliasesByCanonicalID)
    }

    func testReconcileRetainsDormantAssignmentAcrossIdentityChanges() {
        guard let paths, let encoder else {
            XCTFail("Missing integration test persistence dependencies")
            return
        }
        let staleID = "com.example.alpha::stale-key::alpha::AXMenuBarItem"
        let initialLayout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: [staleID: .archive],
                orderedCanonicalIDsByGroup: [.archive: [staleID]],
                aliasesByCanonicalID: [staleID: "Dormant Alias"],
                dormantIDs: [staleID]
            )
        )
        try? FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
        let envelope = PersistentEnvelope(schemaVersion: 3, payload: initialLayout)
        try? encoder.encode(envelope).write(to: paths.layoutV3URL, options: .atomic)

        let descriptor = makeDescriptor(
            bundleID: "com.example.alpha",
            title: "Alpha",
            stableKeyBasis: "fresh-key",
            canonicalID: MenuExtraCanonicalID(rawValue: "opaque-canonical-alpha")
        )
        XCTAssertNotEqual(descriptor.canonicalID.rawValue, descriptor.id)
        let service = LayoutService(paths: paths)

        let summary = service.reconcile(with: [descriptor])
        let snapshot = service.snapshot()

        XCTAssertTrue(summary.didChange)
        XCTAssertEqual(snapshot.defaultLayout.groupsByCanonicalID[descriptor.canonicalID.rawValue], .hidden)
        XCTAssertEqual(snapshot.defaultLayout.groupsByCanonicalID[staleID], .archive)
        XCTAssertEqual(snapshot.defaultLayout.aliasesByCanonicalID[staleID], "Dormant Alias")
        XCTAssertNil(snapshot.defaultLayout.aliasesByCanonicalID[descriptor.canonicalID.rawValue])
        XCTAssertEqual(snapshot.defaultLayout.orderedCanonicalIDsByGroup[.archive], [staleID])
        XCTAssertEqual(summary.retainedAssignmentCount, 1)
    }

    private func makeDescriptor(
        bundleID: String,
        title: String,
        stableKeyBasis: String,
        canonicalID: MenuExtraCanonicalID? = nil
    ) -> MenuExtraDescriptor {
        let identity = MenuExtraIdentity.make(
            bundleID: bundleID,
            title: title,
            role: "AXMenuBarItem",
            stableKeyBasis: stableKeyBasis
        )

        return MenuExtraDescriptor(
            canonicalID: canonicalID ?? .generated(),
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
