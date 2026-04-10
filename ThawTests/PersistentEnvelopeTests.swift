//
//  PersistentEnvelopeTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

final class PersistentEnvelopeTests: XCTestCase {
    func testLegacyMinimalEnvelopeDecodesWithFallbackTimestamps() throws {
        let decoder = makeDecoder()
        let jsonString = """
        {
          "schemaVersion": 3,
          "payload": {
            "value": "legacy"
          }
        }
        """
        guard let legacyJSON = jsonString.data(using: .utf8) else {
            XCTFail("Failed to build legacy envelope fixture JSON")
            return
        }

        let envelope = try decoder.decode(PersistentEnvelope<PayloadFixture>.self, from: legacyJSON)

        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertEqual(envelope.payload, PayloadFixture(value: "legacy"))
        XCTAssertEqual(envelope.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(envelope.updatedAt, Date(timeIntervalSince1970: 0))
    }

    func testNewEnvelopeEncodesAndRoundTripsTimestamps() throws {
        let encoder = makeEncoder()
        let decoder = makeDecoder()
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_710_000_300)
        let initial = PersistentEnvelope(
            schemaVersion: 3,
            payload: PayloadFixture(value: "current"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let data = try encoder.encode(initial)
        let encodedJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(encodedJSON?["createdAt"])
        XCTAssertNotNil(encodedJSON?["updatedAt"])

        let decoded = try decoder.decode(PersistentEnvelope<PayloadFixture>.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.payload, PayloadFixture(value: "current"))
        XCTAssertEqual(decoded.createdAt, createdAt)
        XCTAssertEqual(decoded.updatedAt, updatedAt)
    }

    func testDefaultTimestampsStartEqualOnFreshEnvelope() {
        let envelope = PersistentEnvelope(
            schemaVersion: 3,
            payload: PayloadFixture(value: "fresh")
        )

        XCTAssertEqual(envelope.createdAt, envelope.updatedAt)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct PayloadFixture: Codable, Equatable {
    let value: String
}
