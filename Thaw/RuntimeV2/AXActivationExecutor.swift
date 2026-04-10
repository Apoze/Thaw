//
//  AXActivationExecutor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import AXSwift

@MainActor
protocol AXActivationResolving: AnyObject {
    func resolveCandidate(
        _ descriptor: MenuExtraDescriptor,
        displaySnapshot: DisplayObservationSnapshot
    ) async -> ResolvedCandidate?
}

extension AXActivationResolver: AXActivationResolving {}

struct ActivationConfirmationWindow {
    let pollInterval: Duration
    let maxPollCount: Int

    static let bounded = ActivationConfirmationWindow(
        pollInterval: .milliseconds(80),
        maxPollCount: 10
    )
}

private enum ActivationObservationResult {
    case openedUI
    case noObservedInterface

    var activationOutcome: ActivationOutcome {
        switch self {
        case .openedUI:
            .openedUI
        case .noObservedInterface:
            .openedApp
        }
    }
}

private enum ActivationAttemptResult {
    case completed(ActivationOutcome)
    case retryableFailure(AXError)
}

struct AXActivationEnvironment {
    var isProcessTrusted: () -> Bool = {
        AXHelpers.isProcessTrusted()
    }
    var supportedActions: (UIElement) -> [Action] = { element in
        AXHelpers.actions(for: element)
    }
    var performAction: (Action, UIElement, Float) throws -> Void = { action, element, timeout in
        try AXHelpers.perform(action, on: element, messagingTimeout: timeout)
    }
    var shownMenu: (UIElement) -> UIElement? = { element in
        AXHelpers.shownMenu(for: element)
    }
    var onScreenWindows: () -> [WindowInfo] = {
        WindowInfo.createOnScreenWindowsPublic()
    }
    var activateOwningApplication: (pid_t) -> Bool = { pid in
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.activate()
    }
}

@MainActor
final class AXActivationExecutor: ActivationExecuting {
    private let diagLog = DiagLog(category: "AXActivationExecutor")
    private let axActivationResolver: any AXActivationResolving
    private let environment: AXActivationEnvironment
    private let confirmationWindow: ActivationConfirmationWindow
    private let actionMessagingTimeout: Float = 1.5

    init(
        axActivationResolver: any AXActivationResolving,
        environment: AXActivationEnvironment = AXActivationEnvironment(),
        confirmationWindow: ActivationConfirmationWindow = .bounded
    ) {
        self.axActivationResolver = axActivationResolver
        self.environment = environment
        self.confirmationWindow = confirmationWindow
    }

    convenience init(identityRegistry: IdentityRegistry) {
        self.init(axActivationResolver: AXActivationResolver(identityRegistry: identityRegistry))
    }

    func execute(
        command: ActivationCommand,
        descriptor: MenuExtraDescriptor,
        displayService: DisplayService
    ) async -> ActivationOutcome {
        let start = ContinuousClock.now

        func finalize(_ outcome: ActivationOutcome) -> ActivationOutcome {
            let duration = start.duration(to: .now)
            diagLog.debug(
                """
                Activation \(command.canonicalID) on \(command.surface.rawValue) \
                (\(command.intent.rawValue)) -> \(String(describing: outcome)) in \(duration)
                """
            )
            return outcome
        }

        guard environment.isProcessTrusted() else {
            return finalize(.permissionMissing)
        }

        switch descriptor.capability {
        case .unsupported:
            return finalize(.unsupported)
        case .openApp:
            return finalize(
                environment.activateOwningApplication(descriptor.ownerPID) ? .openedApp : .failedTerminal
            )
        case .axPress:
            return finalize(await activateAXDescriptor(
                descriptor,
                intent: command.intent,
                displayService: displayService
            ))
        }
    }

    private func orderedActions(for intent: ActivationIntent) -> [Action] {
        let preferredAction: Action? = switch intent {
        case .automatic:
            nil
        case .primary:
            .press
        case .secondary:
            .showMenu
        }

        var result = [Action]()
        if let preferredAction {
            result.append(preferredAction)
        }

        for action in [Action.press, .showMenu] where !result.contains(action) {
            result.append(action)
        }

        return result
    }

    private func activateAXDescriptor(
        _ descriptor: MenuExtraDescriptor,
        intent: ActivationIntent,
        displayService: DisplayService
    ) async -> ActivationOutcome {
        let initialSnapshot = displayService.observationSnapshot()
        guard let candidate = await axActivationResolver.resolveCandidate(
            descriptor,
            displaySnapshot: initialSnapshot
        ) else {
            diagLog.debug("Could not resolve AX candidate for \(descriptor.id) on initial attempt")
            return .timeout
        }

        switch await performAXPass(
            candidate: candidate,
            for: descriptor,
            intent: intent
        ) {
        case let .completed(outcome):
            return outcome
        case let .retryableFailure(error):
            diagLog.warning("Retryable AX failure for \(descriptor.id); re-resolving once: \(error)")
        }

        let retrySnapshot = displayService.observationSnapshot()
        guard let retryCandidate = await axActivationResolver.resolveCandidate(
            descriptor,
            displaySnapshot: retrySnapshot
        ) else {
            diagLog.error("Re-resolution failed after retryable AX error for \(descriptor.id)")
            return .failedRecoverable
        }

        switch await performAXPass(
            candidate: retryCandidate,
            for: descriptor,
            intent: intent
        ) {
        case let .completed(outcome):
            return outcome
        case let .retryableFailure(error):
            diagLog.error("AX retry exhausted for \(descriptor.id): \(error)")
            return .failedRecoverable
        }
    }

    private func performAXPass(
        candidate: ResolvedCandidate,
        for descriptor: MenuExtraDescriptor,
        intent: ActivationIntent
    ) async -> ActivationAttemptResult {
        let supportedActions = environment.supportedActions(candidate.element)
        let candidateActions = orderedActions(for: intent)
            .filter { supportedActions.contains($0) }

        guard !candidateActions.isEmpty else {
            diagLog.warning("Resolved AX candidate \(descriptor.id) without supported actions")
            return .completed(.unsupported)
        }

        for action in candidateActions {
            let windowsBefore = environment.onScreenWindows()

            do {
                try environment.performAction(
                    action,
                    candidate.element,
                    actionMessagingTimeout
                )
            } catch let error as AXError where error == .cannotComplete || error == .invalidUIElement {
                return .retryableFailure(error)
            } catch {
                diagLog.error("Failed to perform AX action \(action) for \(descriptor.id): \(error)")
                return .completed(.failedTerminal)
            }

            let observation = await observeConfirmationWindow(
                for: descriptor,
                element: candidate.element,
                windowsBefore: windowsBefore
            )
            if observation == .noObservedInterface {
                diagLog.debug(
                    """
                    AX action \(action) for \(descriptor.id) completed without an observed \
                    interface during the confirmation window; trusting the AX action result
                    """
                )
            }
            return .completed(observation.activationOutcome)
        }

        return .completed(.unsupported)
    }

    private func observeConfirmationWindow(
        for descriptor: MenuExtraDescriptor,
        element: UIElement,
        windowsBefore: [WindowInfo]
    ) async -> ActivationObservationResult {
        for _ in 0 ..< confirmationWindow.maxPollCount {
            if environment.shownMenu(element) != nil {
                return .openedUI
            }

            let windowsAfter = environment.onScreenWindows()
            let ownerWindowDelta = windowsAfter.contains {
                $0.ownerPID == descriptor.ownerPID && !windowsBefore.contains($0)
            }
            if ownerWindowDelta {
                return .openedUI
            }

            try? await Task.sleep(for: confirmationWindow.pollInterval)
        }

        return .noObservedInterface
    }
}
