//
//  ActivationService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
protocol ActivationExecuting: AnyObject {
    func execute(
        command: ActivationCommand,
        descriptor: MenuExtraDescriptor,
        displayService: DisplayService
    ) async -> ActivationOutcome
}

protocol ActivationContextProviding: Sendable {
    func descriptor(for canonicalID: MenuExtraCanonicalID) async -> MenuExtraDescriptor?
    func recordThawInitiatedActivation() async
    func refresh(invalidation: DiscoveryInvalidation) async
}

protocol ActivationCommandHandling: Sendable {
    func activate(_ command: ActivationCommand) async -> ActivationOutcome
}

enum PanelInteractionDisposition: Hashable, Sendable {
    case dismiss
    case keepPresented
}

struct PanelInteractionResult: Hashable, Sendable {
    let outcome: ActivationOutcome
    let disposition: PanelInteractionDisposition
}

protocol PanelInteractionHandling: Sendable {
    func interactWithPanel(using command: ActivationCommand) async -> PanelInteractionResult
}

actor ActivationService {
    private let diagLog = DiagLog(category: .activation)
    private let executor: any ActivationExecuting
    private let contextProvider: any ActivationContextProviding
    private let displayService: DisplayService
    private var inFlightCanonicalIDs = Set<MenuExtraCanonicalID>()
    private var waitingContinuations = [MenuExtraCanonicalID: [CheckedContinuation<ActivationOutcome, Never>]]()

    init(
        executor: any ActivationExecuting,
        contextProvider: any ActivationContextProviding,
        displayService: DisplayService
    ) {
        self.executor = executor
        self.contextProvider = contextProvider
        self.displayService = displayService
    }

    func activate(_ command: ActivationCommand) async -> ActivationOutcome {
        guard let descriptor = await contextProvider.descriptor(for: command.canonicalID) else {
            diagLog.warning("Activation requested for missing canonical ID \(command.canonicalID)")
            return .failedRecoverable
        }
        await contextProvider.recordThawInitiatedActivation()

        if inFlightCanonicalIDs.contains(command.canonicalID) {
            return await withCheckedContinuation { continuation in
                waitingContinuations[command.canonicalID, default: []].append(continuation)
            }
        }

        inFlightCanonicalIDs.insert(command.canonicalID)
        let start = ContinuousClock.now
        let outcome = await executor.execute(
            command: command,
            descriptor: descriptor,
            displayService: displayService
        )
        RuntimeMetrics.shared.recordActivationDuration(start.duration(to: .now).timeInterval)
        diagLog.debug("Activation \(command.intent.rawValue) on \(command.surface.rawValue) returned \(outcome)")
        if shouldTriggerFollowUp(for: outcome) {
            await contextProvider.refresh(invalidation: command.followUpInvalidation)
        }
        let continuations = waitingContinuations.removeValue(forKey: command.canonicalID) ?? []
        inFlightCanonicalIDs.remove(command.canonicalID)
        continuations.forEach { $0.resume(returning: outcome) }
        return outcome
    }

    func interactWithPanel(using command: ActivationCommand) async -> PanelInteractionResult {
        let outcome = await activate(command)
        return PanelInteractionResult(
            outcome: outcome,
            disposition: panelDisposition(for: outcome)
        )
    }

    private func shouldTriggerFollowUp(for outcome: ActivationOutcome) -> Bool {
        outcome.shouldTriggerFollowUp
    }

    private func panelDisposition(for outcome: ActivationOutcome) -> PanelInteractionDisposition {
        outcome.panelDisposition
    }
}

extension ActivationService: ActivationCommandHandling {}
extension ActivationService: PanelInteractionHandling {}
