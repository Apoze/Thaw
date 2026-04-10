//
//  ProfilesService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Foundation

@MainActor
protocol ProfileDiscoverySessionControlling: AnyObject {
    func currentLayoutSnapshot() -> ProfileLayoutV3
    func applyLayoutSnapshot(_ profileLayout: ProfileLayoutV3) async
    func refresh(_ invalidation: DiscoveryInvalidation) async
}

extension DiscoverySession: ProfileDiscoverySessionControlling {}

@MainActor
final class ProfileRuntimeContext {
    let generalSettings: GeneralSettings
    let advancedSettings: AdvancedSettings
    let hotkeysSettings: HotkeysSettings
    let displaySettings: DisplaySettingsManager
    let appearanceManager: MenuBarAppearanceManager
    let discoverySession: any ProfileDiscoverySessionControlling

    private let currentDisplayUUIDProvider: () -> String?
    private let displayConfigurationDidChangePublisher: AnyPublisher<Void, Never>
    private let hotkeySetupHandler: (Hotkey) -> Void

    init(
        generalSettings: GeneralSettings,
        advancedSettings: AdvancedSettings,
        hotkeysSettings: HotkeysSettings,
        displaySettings: DisplaySettingsManager,
        appearanceManager: MenuBarAppearanceManager,
        discoverySession: any ProfileDiscoverySessionControlling,
        displayConfigurationDidChangePublisher: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher(),
        currentDisplayUUIDProvider: @escaping () -> String?,
        hotkeySetupHandler: @escaping (Hotkey) -> Void = { _ in }
    ) {
        self.generalSettings = generalSettings
        self.advancedSettings = advancedSettings
        self.hotkeysSettings = hotkeysSettings
        self.displaySettings = displaySettings
        self.appearanceManager = appearanceManager
        self.discoverySession = discoverySession
        self.displayConfigurationDidChangePublisher = displayConfigurationDidChangePublisher
        self.currentDisplayUUIDProvider = currentDisplayUUIDProvider
        self.hotkeySetupHandler = hotkeySetupHandler
    }

    func performSetup(for hotkey: Hotkey) {
        hotkeySetupHandler(hotkey)
    }

    func currentDisplayUUID() -> String? {
        currentDisplayUUIDProvider()
    }

    var displayConfigurationChanges: AnyPublisher<Void, Never> {
        displayConfigurationDidChangePublisher
    }
}

@MainActor
final class ProfilesService: ObservableObject {
    enum ProfileUpdateScope {
        case all
        case layoutOnly
        case configurationOnly
    }

    @Published private(set) var profiles: [ProfileMetadata] = []
    @Published var activeProfileID: UUID?
    @Published private(set) var profileHotkeys: [UUID: Hotkey] = [:]

    private let diagLog = DiagLog(category: .profiles)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let paths: ThawPersistencePaths
    private var runtimeContext: ProfileRuntimeContext?
    private var cancellables = Set<AnyCancellable>()
    private var lastActiveDisplayUUID: String?
    private var focusFilterState: FocusFilterState = .notConfigured
    private var hasResolvedInitialFocusState = false
    private var focusFilterService: FocusFilterService?
    private(set) var layoutTask: Task<Void, Never>?
    private var layoutGeneration: UInt = 0
    private(set) var hotkeyProfileMap: [ObjectIdentifier: UUID] = [:]
    private var profileHotkeyCancellables = Set<AnyCancellable>()

    init(
        fileManager: FileManager = .default,
        paths: ThawPersistencePaths = .default()
    ) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec
        self.fileManager = fileManager
        self.paths = paths

        ensureDirectoryExists()
        loadManifest()
    }

    func performSetup(
        runtimeContext: ProfileRuntimeContext,
        focusFilterService: FocusFilterService
    ) {
        self.runtimeContext = runtimeContext
        self.focusFilterService = focusFilterService
        lastActiveDisplayUUID = currentDisplayUUID()
        rebuildProfileHotkeys()

        $profiles
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildProfileHotkeys()
            }
            .store(in: &cancellables)

        runtimeContext.displayConfigurationChanges
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.checkDisplayAndAutoSwitch() }
            }
            .store(in: &cancellables)

        focusFilterService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                Task { await self.handleFocusFilterStateChange(state) }
            }
            .store(in: &cancellables)
    }

    func loadProfile(id: UUID) throws -> Profile {
        let url = profileURL(for: id)
        let data = try Data(contentsOf: url)
        let envelope = try decoder.decode(PersistentEnvelope<Profile>.self, from: data)
        return canonicalizedProfile(envelope.payload)
    }

    func hasProfile(id: UUID) -> Bool {
        profiles.contains { $0.id == id }
    }

    func reloadFromDisk() {
        loadManifest()
        rebuildProfileHotkeys()
    }

    func saveProfile(name: String) throws {
        guard let runtimeContext else {
            return
        }
        let profile = Profile(
            name: name,
            content: ProfileContent(
                generalSettings: GeneralSettingsSnapshot.capture(from: runtimeContext.generalSettings),
                advancedSettings: AdvancedSettingsSnapshot.capture(from: runtimeContext.advancedSettings),
                hotkeys: Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:],
                displayConfigurations: runtimeContext.displaySettings.configurations,
                appearanceConfiguration: runtimeContext.appearanceManager.configuration,
                menuBarLayout: captureCurrentLayout()
            )
        )

        try writeProfileEnvelope(profile, to: profileURL(for: profile.id))
        profiles.append(profile.metadata)
        saveManifest()
    }

    func applyProfile(_ profile: Profile) {
        guard let runtimeContext else {
            return
        }
        profile.generalSettings.apply(to: runtimeContext.generalSettings)
        profile.advancedSettings.apply(to: runtimeContext.advancedSettings)

        Defaults.set(profile.hotkeys, forKey: .hotkeys)
        for hotkey in runtimeContext.hotkeysSettings.hotkeys {
            guard let data = profile.hotkeys[hotkey.action.rawValue] else {
                hotkey.keyCombination = nil
                continue
            }
            do {
                let keyCombination = try decoder.decode(KeyCombination?.self, from: data)
                hotkey.keyCombination = keyCombination
            } catch {
                diagLog.error("Failed to decode hotkey for \(hotkey.action.rawValue): \(error)")
            }
        }

        runtimeContext.displaySettings.configurations = profile.displayConfigurations
        runtimeContext.appearanceManager.configuration = profile.appearanceConfiguration

        layoutTask?.cancel()
        layoutGeneration &+= 1
        let generation = layoutGeneration
        layoutTask = Task { [weak self] in
            await runtimeContext.discoverySession.applyLayoutSnapshot(profile.menuBarLayout.layout)
            await runtimeContext.discoverySession.refresh(.profileApplied)
            if self?.layoutGeneration == generation {
                self?.layoutTask = nil
            }
        }
    }

    func applyProfile(id: UUID) async throws {
        let profile = try loadProfile(id: id)
        activeProfileID = id
        applyProfile(profile)
        await layoutTask?.value
    }

    func deleteProfile(id: UUID) throws {
        try fileManager.removeItem(at: profileURL(for: id))
        profiles.removeAll { $0.id == id }
        saveManifest()
        focusFilterService?.clearRequestedProfileIfInvalid(id)
    }

    func renameProfile(id: UUID, to newName: String) throws {
        var profile = try loadProfile(id: id)
        profile = Profile(
            id: profile.id,
            name: newName,
            createdAt: profile.createdAt,
            modifiedAt: Date(),
            content: profile.content
        )

        try writeProfileEnvelope(profile, to: profileURL(for: id))

        if let index = profiles.firstIndex(where: { $0.id == id }) {
            var updated = profiles[index]
            updated.name = newName
            updated.modifiedAt = profile.modifiedAt
            profiles[index] = updated
        }
        saveManifest()
    }

    func duplicateProfile(id: UUID, newName: String) throws {
        let original = try loadProfile(id: id)
        let duplicate = Profile(name: newName, content: original.content)

        try writeProfileEnvelope(duplicate, to: profileURL(for: duplicate.id))
        profiles.append(duplicate.metadata)
        saveManifest()
    }

    func exportProfile(id: UUID, to url: URL) throws {
        let profile = try loadProfile(id: id)
        let metadata = profiles.first { $0.id == id }
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: metadata?.associatedDisplayUUID,
            associatedDisplayName: metadata?.associatedDisplayName
        )
        let bundle = ProfileExportBundle(entries: [entry])
        try encoder.encode(bundle).write(to: url, options: .atomic)
    }

    func updateProfile(id: UUID, scope: ProfileUpdateScope) throws {
        switch scope {
        case .all:
            try updateProfileWithCurrentState(id: id)
        case .layoutOnly:
            try updateProfileLayout(id: id)
        case .configurationOnly:
            try updateProfileConfiguration(id: id)
        }
    }

    func exportAllProfiles() -> String? {
        var entries = [ProfileExportEntry]()
        for metadata in profiles {
            guard let profile = try? loadProfile(id: metadata.id) else {
                continue
            }
            entries.append(ProfileExportEntry(
                profile: profile,
                associatedDisplayUUID: metadata.associatedDisplayUUID,
                associatedDisplayName: metadata.associatedDisplayName
            ))
        }
        let bundle = ProfileExportBundle(entries: entries)
        guard let data = try? encoder.encode(bundle) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setAssociatedDisplay(uuid: String?, displayName: String? = nil, forProfileID profileID: UUID) {
        if let uuid {
            for index in profiles.indices where profiles[index].associatedDisplayUUID == uuid {
                profiles[index].associatedDisplayUUID = nil
                profiles[index].associatedDisplayName = nil
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].associatedDisplayUUID = uuid
            profiles[index].associatedDisplayName = uuid != nil ? displayName : nil
        }
        saveManifest()
    }

    func setAssociatedDisplay(uuid _: String?, forDisplayUUID displayUUID: String) {
        for index in profiles.indices where profiles[index].associatedDisplayUUID == displayUUID {
            profiles[index].associatedDisplayUUID = nil
            profiles[index].associatedDisplayName = nil
        }
        saveManifest()
    }

    func handlePotentialDisplaySwitch(to currentUUID: String?) async {
        guard let currentUUID else { return }
        guard currentUUID != lastActiveDisplayUUID else { return }
        lastActiveDisplayUUID = currentUUID
        guard !isFocusFilterActive else { return }
        await applyProfileForDisplay(uuid: currentUUID)
    }

    func importProfile(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let bundle = try decoder.decode(ProfileExportBundle.self, from: data)

        for entry in bundle.entries {
            let importedSourceProfile = canonicalizedProfile(entry.profile)
            let imported = Profile(name: importedSourceProfile.name, content: importedSourceProfile.content)

            try writeProfileEnvelope(imported, to: profileURL(for: imported.id))
            profiles.append(imported.metadata)

            if let displayUUID = entry.associatedDisplayUUID {
                setAssociatedDisplay(
                    uuid: displayUUID,
                    displayName: entry.associatedDisplayName,
                    forProfileID: imported.id
                )
            }
        }
        saveManifest()
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: paths.rootDirectory.path) {
            do {
                try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
            } catch {
                diagLog.error("Failed to create root directory: \(error)")
            }
        }
        if !fileManager.fileExists(atPath: paths.profilesDirectory.path) {
            do {
                try fileManager.createDirectory(at: paths.profilesDirectory, withIntermediateDirectories: true)
            } catch {
                diagLog.error("Failed to create profiles directory: \(error)")
            }
        }
    }

    private func loadManifest() {
        guard fileManager.fileExists(atPath: paths.profilesManifestV3URL.path) else {
            profiles = []
            return
        }
        do {
            let data = try Data(contentsOf: paths.profilesManifestV3URL)
            let envelope = try decoder.decode(PersistentEnvelope<[ProfileMetadata]>.self, from: data)
            profiles = envelope.payload
        } catch {
            diagLog.error("Failed to load profiles manifest: \(error)")
            profiles = []
        }
    }

    private func saveManifest() {
        do {
            let envelope = PersistentEnvelope(schemaVersion: 3, payload: profiles)
            let data = try encoder.encode(envelope)
            try data.write(to: paths.profilesManifestV3URL, options: .atomic)
        } catch {
            diagLog.error("Failed to save profiles manifest: \(error)")
        }
    }

    private func profileURL(for id: UUID) -> URL {
        paths.profileV3URL(for: id)
    }

    private func writeProfileEnvelope(_ profile: Profile, to url: URL) throws {
        let envelope = PersistentEnvelope(schemaVersion: 3, payload: profile)
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: .atomic)
    }

    private func updateProfileWithCurrentState(id: UUID) throws {
        guard let old = profiles.first(where: { $0.id == id }) else {
            return
        }

        let tempName = "__temp_update__"
        try saveProfile(name: tempName)
        guard let tempMetadata = profiles.last, tempMetadata.name == tempName else {
            return
        }

        var updated = try loadProfile(id: tempMetadata.id)
        updated = Profile(
            id: id,
            name: old.name,
            createdAt: old.createdAt,
            modifiedAt: Date(),
            content: updated.content
        )

        try writeProfileEnvelope(updated, to: profileURL(for: id))
        try? fileManager.removeItem(at: profileURL(for: tempMetadata.id))
        profiles.removeAll { $0.id == tempMetadata.id }

        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].modifiedAt = updated.modifiedAt
        }
        saveManifest()
    }

    private func captureCurrentLayout() -> MenuBarLayoutSnapshot {
        guard let runtimeContext else {
            return MenuBarLayoutSnapshot(layout: .empty)
        }
        return MenuBarLayoutSnapshot(layout: runtimeContext.discoverySession.currentLayoutSnapshot())
    }

    private func applyCurrentConfiguration(to profile: inout Profile) {
        guard let runtimeContext else {
            return
        }
        profile.generalSettings = GeneralSettingsSnapshot.capture(from: runtimeContext.generalSettings)
        profile.advancedSettings = AdvancedSettingsSnapshot.capture(from: runtimeContext.advancedSettings)
        profile.hotkeys = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:]
        profile.displayConfigurations = runtimeContext.displaySettings.configurations
        profile.appearanceConfiguration = runtimeContext.appearanceManager.configuration
    }

    private func saveProfileAndUpdateManifest(_ profile: Profile) throws {
        try writeProfileEnvelope(profile, to: profileURL(for: profile.id))

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].modifiedAt = profile.modifiedAt
        }
        saveManifest()
    }

    private func updateProfileLayout(id: UUID) throws {
        var profile = try loadProfile(id: id)
        profile.menuBarLayout = captureCurrentLayout()
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
    }

    private func updateProfileConfiguration(id: UUID) throws {
        var profile = try loadProfile(id: id)
        applyCurrentConfiguration(to: &profile)
        profile.modifiedAt = Date()
        try saveProfileAndUpdateManifest(profile)
    }

    private func rebuildProfileHotkeys() {
        guard let runtimeContext else { return }

        for (_, hotkey) in profileHotkeys {
            hotkey.disable()
        }
        hotkeyProfileMap.removeAll()
        profileHotkeyCancellables.removeAll()

        let profileIDs = Set(profiles.map(\.id.uuidString))
        if var saved = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] {
            let before = saved.count
            saved = saved.filter { profileIDs.contains($0.key) }
            if saved.count != before {
                Defaults.set(saved, forKey: .profileHotkeys)
            }
        }

        let saved = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
        let hotkeyDecoder = JSONDecoder()
        let hotkeyEncoder = JSONEncoder()

        var newHotkeys = [UUID: Hotkey]()
        for metadata in profiles {
            let profileID = metadata.id
            let hotkey = Hotkey(action: .profileApply)
            runtimeContext.performSetup(for: hotkey)

            if let data = saved[metadata.id.uuidString],
               let combo = try? hotkeyDecoder.decode(KeyCombination?.self, from: data)
            {
                hotkey.keyCombination = combo
            }

            hotkeyProfileMap[ObjectIdentifier(hotkey)] = profileID

            hotkey.$keyCombination
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newCombo in
                    guard let self else { return }
                    var dict = Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
                    if let combo = newCombo, let data = try? hotkeyEncoder.encode(combo) {
                        dict[profileID.uuidString] = data
                    } else {
                        dict.removeValue(forKey: profileID.uuidString)
                    }
                    Defaults.set(dict, forKey: .profileHotkeys)
                    self.hotkeyProfileMap[ObjectIdentifier(hotkey)] = newCombo != nil ? profileID : nil
                }
                .store(in: &profileHotkeyCancellables)

            newHotkeys[metadata.id] = hotkey
        }
        profileHotkeys = newHotkeys
    }

    private func checkDisplayAndAutoSwitch() async {
        await handlePotentialDisplaySwitch(to: currentDisplayUUID())
    }

    private var isFocusFilterActive: Bool {
        if case .active = focusFilterState {
            return true
        }
        return false
    }

    private func handleFocusFilterStateChange(_ state: FocusFilterState) async {
        let previousState = focusFilterState
        focusFilterState = state

        switch state {
        case let .active(profileID):
            await applyFocusOwnedProfile(id: profileID)
        case .inactive, .notConfigured:
            let shouldRestoreDisplayProfile: Bool
            if !hasResolvedInitialFocusState {
                shouldRestoreDisplayProfile = true
            } else if case .active = previousState {
                shouldRestoreDisplayProfile = true
            } else {
                shouldRestoreDisplayProfile = false
            }

            guard shouldRestoreDisplayProfile else {
                hasResolvedInitialFocusState = true
                return
            }

            diagLog.info("Focus Filter inactive — restoring display profile")
            await restoreDisplayProfile()
        }

        hasResolvedInitialFocusState = true
    }

    private func applyFocusOwnedProfile(id profileID: UUID) async {
        guard profileID != activeProfileID else {
            return
        }
        guard runtimeContext != nil else {
            return
        }

        diagLog.info("Focus Filter: applying profile \(profileID.uuidString)")
        do {
            let profile = try loadProfile(id: profileID)
            activeProfileID = profileID
            applyProfile(profile)
        } catch {
            diagLog.warning("Focus Filter apply failed for \(profileID): \(error)")
            focusFilterService?.clearRequestedProfileIfInvalid(profileID)
        }
    }

    private func restoreDisplayProfile() async {
        guard let currentUUID = currentDisplayUUID() else {
            activeProfileID = nil
            return
        }

        let applied = await applyProfileForDisplay(uuid: currentUUID)
        if !applied {
            activeProfileID = nil
        }
    }

    @discardableResult
    private func applyProfileForDisplay(uuid: String) async -> Bool {
        guard let metadata = profiles.first(where: { $0.associatedDisplayUUID == uuid }) else {
            return false
        }
        guard runtimeContext != nil else {
            return false
        }

        if metadata.id == activeProfileID {
            return true
        }

        diagLog.info("Auto-switching to profile \(metadata.name) for display \(uuid)")
        do {
            let profile = try loadProfile(id: metadata.id)
            activeProfileID = metadata.id
            applyProfile(profile)
            return true
        } catch {
            diagLog.error("Auto-switch failed: \(error)")
            return false
        }
    }

    private func currentDisplayUUID() -> String? {
        runtimeContext?.currentDisplayUUID()
    }

    private func canonicalizedProfile(_ profile: Profile) -> Profile {
        let canonicalLayout = canonicalizedLayout(profile.menuBarLayout.layout)
        guard canonicalLayout != profile.menuBarLayout.layout else {
            return profile
        }

        var updatedProfile = profile
        updatedProfile.menuBarLayout = MenuBarLayoutSnapshot(layout: canonicalLayout)
        return updatedProfile
    }

    private func canonicalizedLayout(_ layout: ProfileLayoutV3) -> ProfileLayoutV3 {
        guard layout.requiresCanonicalIDUpgrade else {
            return layout
        }

        return IdentityRegistry.canonicalizeLayoutReferences(
            layout,
            fileManager: fileManager,
            paths: paths
        )
    }
}
