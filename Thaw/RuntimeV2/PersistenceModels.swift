//
//  PersistenceModels.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

struct PersistentEnvelope<Payload: Codable>: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let updatedAt: Date
    var payload: Payload

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case createdAt
        case updatedAt
        case payload
    }

    init(
        schemaVersion: Int,
        payload: Payload,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        payload = try container.decode(Payload.self, forKey: .payload)

        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        let legacyTimestampFallback = Date(timeIntervalSince1970: 0)

        createdAt = decodedCreatedAt ?? decodedUpdatedAt ?? legacyTimestampFallback
        updatedAt = decodedUpdatedAt ?? decodedCreatedAt ?? legacyTimestampFallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(payload, forKey: .payload)
    }
}
