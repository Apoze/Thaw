//
//  ProfileManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

@MainActor
final class ProfileManager: ObservableObject {
    typealias ProfileUpdateScope = ProfilesService.ProfileUpdateScope

    let service: ProfilesService

    private var cancellables = Set<AnyCancellable>()

    init(
        service: ProfilesService? = nil,
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) {
        self.service = service ?? ProfilesService(
            fileManager: fileManager,
            paths: paths
        )

        self.service.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var profiles: [ProfileMetadata] {
        service.profiles
    }

    var activeProfileID: UUID? {
        get { service.activeProfileID }
        set { service.activeProfileID = newValue }
    }

    var profileHotkeys: [UUID: Hotkey] {
        service.profileHotkeys
    }

    var hotkeyProfileMap: [ObjectIdentifier: UUID] {
        service.hotkeyProfileMap
    }

    var layoutTask: Task<Void, Never>? {
        service.layoutTask
    }

    func performSetup(
        runtimeContext: ProfileRuntimeContext,
        focusFilterService: FocusFilterService
    ) {
        service.performSetup(
            runtimeContext: runtimeContext,
            focusFilterService: focusFilterService
        )
    }

    func saveProfile(name: String) throws {
        try service.saveProfile(name: name)
    }

    func loadProfile(id: UUID) throws -> Profile {
        try service.loadProfile(id: id)
    }

    func hasProfile(id: UUID) -> Bool {
        service.hasProfile(id: id)
    }

    func reloadFromDisk() {
        service.reloadFromDisk()
    }

    func applyProfile(_ profile: Profile) {
        service.applyProfile(profile)
    }

    func applyProfile(id: UUID) async throws {
        try await service.applyProfile(id: id)
    }

    func deleteProfile(id: UUID) throws {
        try service.deleteProfile(id: id)
    }

    func renameProfile(id: UUID, to newName: String) throws {
        try service.renameProfile(id: id, to: newName)
    }

    func duplicateProfile(id: UUID, newName: String) throws {
        try service.duplicateProfile(id: id, newName: newName)
    }

    func exportProfile(id: UUID, to url: URL) throws {
        try service.exportProfile(id: id, to: url)
    }

    func updateProfile(id: UUID, scope: ProfileUpdateScope) throws {
        try service.updateProfile(id: id, scope: scope)
    }

    func exportAllProfiles() -> String? {
        service.exportAllProfiles()
    }

    func setAssociatedDisplay(uuid: String?, displayName: String? = nil, forProfileID profileID: UUID) {
        service.setAssociatedDisplay(
            uuid: uuid,
            displayName: displayName,
            forProfileID: profileID
        )
    }

    func setAssociatedDisplay(uuid: String?, forDisplayUUID displayUUID: String) {
        service.setAssociatedDisplay(uuid: uuid, forDisplayUUID: displayUUID)
    }

    func handlePotentialDisplaySwitch(to currentUUID: String?) async {
        await service.handlePotentialDisplaySwitch(to: currentUUID)
    }

    func importProfile(from url: URL) throws {
        try service.importProfile(from: url)
    }
}
