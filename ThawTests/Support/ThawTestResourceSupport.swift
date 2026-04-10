//
//  ThawTestResourceSupport.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

enum ThawTestResourceSupport {
    static func sourceText(named name: String) throws -> String {
        try String(contentsOf: resourceURL(named: name, withExtension: "swift"), encoding: .utf8)
    }

    static func fixtureURL(named name: String) -> URL {
        resourceURL(named: name, withExtension: "json")
    }

    static func fixtureData(named name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(named: name))
    }

    private static func resourceURL(named name: String, withExtension fileExtension: String) -> URL {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            fatalError("Missing test resource \(name).\(fileExtension)")
        }
        return url
    }

    private static let bundle = Bundle(for: ThawTestResourceSupportBundleToken.self)
}

private final class ThawTestResourceSupportBundleToken {}
