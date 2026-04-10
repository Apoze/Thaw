//
//  FocusFilterIntent.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppIntents

/// An entity representing a Thaw profile, exposed to the system
/// so users can pick one when configuring a Focus Filter.
struct ProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Thaw Profile"
    }

    static var defaultQuery = ProfileEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Queries the on-disk profile manifest so the system can list
/// available profiles without requiring the full app state.
struct ProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        allProfiles().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        allProfiles()
    }

    private func allProfiles() -> [ProfileEntity] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let paths = ThawPersistencePaths.default()
        guard
            let data = try? Data(contentsOf: paths.profilesManifestV3URL),
            let envelope = try? decoder.decode(
                PersistentEnvelope<[ProfileMetadata]>.self,
                from: data
            )
        else {
            return []
        }

        return envelope.payload.map {
            ProfileEntity(id: $0.id.uuidString, name: $0.name)
        }
    }
}

/// Focus Filter that applies a Thaw profile when a Focus mode activates.
/// Appears in System Settings → Focus → [mode] → Focus Filters → Add "Thaw".
struct ThawFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Thaw Profile"
    static var description: IntentDescription? = IntentDescription(
        "Apply a Thaw profile when this Focus activates.",
        categoryName: "Profiles"
    )

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Set Thaw Profile",
            subtitle: profile.map { "Profile: \($0.name)" } ?? "No profile selected"
        )
    }

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let profile,
              UUID(uuidString: profile.id) != nil
        else {
            // Focus deactivated — clear the stored profile and notify.
            UserDefaults.standard.removeObject(forKey: FocusFilterConstants.requestedProfileIDKey)
            DistributedNotificationCenter.default().postNotificationName(
                FocusFilterConstants.deactivationNotification,
                object: nil,
                deliverImmediately: true
            )
            return .result()
        }

        UserDefaults.standard.set(
            profile.id,
            forKey: FocusFilterConstants.requestedProfileIDKey
        )
        UserDefaults.standard.set(true, forKey: FocusFilterConstants.hasKnownConfigurationKey)
        DistributedNotificationCenter.default().postNotificationName(
            FocusFilterConstants.activationNotification,
            object: nil,
            userInfo: ["profileID": profile.id],
            deliverImmediately: true
        )

        return .result()
    }
}
