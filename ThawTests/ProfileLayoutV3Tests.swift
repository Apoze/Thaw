//
//  ProfileLayoutV3Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

final class ProfileLayoutV3Tests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testMenuBarLayoutSnapshotEncodesV3LayoutKey() throws {
        let snapshot = MenuBarLayoutSnapshot(
            layout: ProfileLayoutV3(
                defaultLayout: LayoutStateV3(
                    groupsByCanonicalID: ["alpha": .archive],
                    orderedCanonicalIDsByGroup: [.archive: ["alpha"]],
                    aliasesByCanonicalID: ["alpha": "Alpha"]
                )
            )
        )

        let data = try encoder.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"layout\""))
        XCTAssertFalse(json.contains("\"virtualLayout\""))
        XCTAssertEqual(snapshot.layout.defaultLayout.groupsByCanonicalID["alpha"], .archive)
        XCTAssertEqual(snapshot.layout.defaultLayout.aliasesByCanonicalID["alpha"], "Alpha")
    }

    func testMenuBarLayoutSnapshotDecodesLegacyVirtualLayoutPayload() throws {
        struct LegacyPayload: Codable {
            let virtualLayout: ProfileLayoutV2
        }

        let data = try encoder.encode(
            LegacyPayload(
                virtualLayout: ProfileLayoutV2(
                    groupsByIdentityID: ["alpha": .archive],
                    orderedIdentityIDsByGroup: [.archive: ["alpha"]],
                    customNamesByIdentityID: ["alpha": "Alpha"]
                )
            )
        )

        let snapshot = try decoder.decode(MenuBarLayoutSnapshot.self, from: data)
        let decoded = snapshot.layout.defaultLayout

        XCTAssertEqual(decoded.groupsByCanonicalID["alpha"], .archive, "decoded layout: \(decoded)")
        XCTAssertEqual(
            decoded.orderedCanonicalIDsByGroup[.archive],
            ["alpha"],
            "decoded layout: \(decoded)"
        )
        XCTAssertEqual(
            decoded.aliasesByCanonicalID["alpha"],
            "Alpha",
            "decoded layout: \(decoded)"
        )
    }

    func testMenuBarLayoutSnapshotDecodesLegacyFlatKeysPayload() throws {
        let data = Data(
            """
            {
              "customNames": {
                "alpha": "Alpha"
              },
              "itemOrder": {
                "alwaysHidden": [
                  "alpha"
                ]
              },
              "itemSectionMap": {
                "alpha": "alwaysHidden"
              }
            }
            """.utf8
        )

        let snapshot = try decoder.decode(MenuBarLayoutSnapshot.self, from: data)
        let reencoded = try encoder.encode(snapshot)
        let reencodedJSON = try XCTUnwrap(String(data: reencoded, encoding: .utf8))

        XCTAssertEqual(snapshot.layout.defaultLayout.groupsByCanonicalID["alpha"], .archive)
        XCTAssertEqual(snapshot.layout.defaultLayout.orderedCanonicalIDsByGroup[.archive], ["alpha"])
        XCTAssertEqual(snapshot.layout.defaultLayout.aliasesByCanonicalID["alpha"], "Alpha")
        XCTAssertTrue(reencodedJSON.contains("\"layout\""))
        XCTAssertFalse(reencodedJSON.contains("\"virtualLayout\""))
    }

    func testLayoutFlagsLegacyReferencesUntilCanonicalized() {
        let layout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: ["legacy-alpha": .archive],
                orderedCanonicalIDsByGroup: [.archive: ["legacy-alpha"]],
                aliasesByCanonicalID: ["legacy-alpha": "Alpha"],
                dormantIDs: ["legacy-alpha"]
            )
        )

        XCTAssertTrue(layout.requiresCanonicalIDUpgrade)
        XCTAssertEqual(layout.legacyReferencedIDs, ["legacy-alpha"])
    }

    func testCanonicalizedLayoutRewritesLegacyReferencesAndDeduplicatesOrder() {
        let layout = ProfileLayoutV3(
            defaultLayout: LayoutStateV3(
                groupsByCanonicalID: ["legacy-alpha": .archive],
                orderedCanonicalIDsByGroup: [
                    .archive: [
                        "legacy-alpha",
                        "ffffffff-1111-2222-3333-444444444444",
                        "legacy-alpha",
                    ],
                ],
                aliasesByCanonicalID: ["legacy-alpha": "Alpha"],
                dormantIDs: ["legacy-alpha"]
            )
        )
        let mapping = [
            "legacy-alpha": MenuExtraCanonicalID(rawValue: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        ]

        let canonicalized = layout.canonicalized(using: mapping)

        XCTAssertFalse(canonicalized.requiresCanonicalIDUpgrade)
        XCTAssertEqual(
            canonicalized.groupsByCanonicalID,
            ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee": .archive]
        )
        XCTAssertEqual(
            canonicalized.orderedCanonicalIDsByGroup[.archive],
            [
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "ffffffff-1111-2222-3333-444444444444",
            ]
        )
        XCTAssertEqual(
            canonicalized.customNamesByCanonicalID,
            ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee": "Alpha"]
        )
        XCTAssertEqual(canonicalized.dormantIDs, ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
    }
}
