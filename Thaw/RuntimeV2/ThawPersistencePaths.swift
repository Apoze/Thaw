//
//  ThawPersistencePaths.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

struct ThawPersistencePaths {
    let rootDirectory: URL

    var runtimeDirectory: URL {
        rootDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    var profilesDirectory: URL {
        rootDirectory.appendingPathComponent("profiles", isDirectory: true)
    }

    var layoutV3URL: URL {
        runtimeDirectory.appendingPathComponent("layout-v3.json")
    }

    var identityRegistryV3URL: URL {
        runtimeDirectory.appendingPathComponent("identity-registry-v3.json")
    }

    var profilesManifestV3URL: URL {
        profilesDirectory.appendingPathComponent("manifest-v3.json")
    }

    func profileV3URL(for id: UUID) -> URL {
        profilesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    static func `default`(fileManager: FileManager = .default) -> ThawPersistencePaths {
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory not found")
        }
        return ThawPersistencePaths(
            rootDirectory: appSupport.appendingPathComponent("Thaw", isDirectory: true)
        )
    }
}
