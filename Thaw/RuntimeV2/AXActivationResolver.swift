//
//  AXActivationResolver.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
import AppKit

@MainActor
final class AXActivationResolver {
    private let identityRegistry: IdentityRegistry

    init(identityRegistry: IdentityRegistry) {
        self.identityRegistry = identityRegistry
    }

    func resolveCandidate(
        _ descriptor: MenuExtraDescriptor,
        displaySnapshot: DisplayObservationSnapshot
    ) async -> ResolvedCandidate? {
        guard
            let app = NSRunningApplication(processIdentifier: descriptor.ownerPID),
            let bundleIdentifier = app.bundleIdentifier,
            let application = AXHelpers.application(for: app),
            let extrasMenuBar = AXHelpers.extrasMenuBar(for: application)
        else {
            return nil
        }

        let candidates = AXResolvedCandidateBuilder.rawResolvedCandidates(
            for: app,
            bundleIdentifier: bundleIdentifier,
            extrasMenuBar: extrasMenuBar,
            displaySnapshot: displaySnapshot
        )
        let resolvedCandidates = await identityRegistry.resolve(candidates.map(\.descriptor))

        guard let index = resolvedCandidates.firstIndex(where: { $0.canonicalID == descriptor.canonicalID }) else {
            return nil
        }
        guard candidates.indices.contains(index) else {
            return nil
        }

        return ResolvedCandidate(
            element: candidates[index].element,
            descriptor: AXResolvedCandidateBuilder.makeDescriptor(
                source: resolvedCandidates[index].source,
                canonicalID: resolvedCandidates[index].canonicalID,
                identity: resolvedCandidates[index].identity
            )
        )
    }
}
