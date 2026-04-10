//
//  AXObservationService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
import AppKit
import ApplicationServices

protocol DiscoveryObserving: Sendable {
    func discoverDescriptors(displaySnapshot: DisplayObservationSnapshot) async -> [MenuExtraDescriptor]
    func discoverDescriptors(
        displaySnapshot: DisplayObservationSnapshot,
        processIdentifiers: Set<pid_t>
    ) async -> [MenuExtraDescriptor]

    var invalidationUpdates: AsyncStream<DiscoveryInvalidation> { get }
    func performSetup() async
}

extension DiscoveryObserving {
    func discoverDescriptors(
        displaySnapshot: DisplayObservationSnapshot,
        processIdentifiers _: Set<pid_t>
    ) async -> [MenuExtraDescriptor] {
        await discoverDescriptors(displaySnapshot: displaySnapshot)
    }

    var invalidationUpdates: AsyncStream<DiscoveryInvalidation> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func performSetup() async {}
}

actor ObservationInvalidationEmitter {
    private let delay: Duration
    private let continuation: AsyncStream<DiscoveryInvalidation>.Continuation
    private var pendingTasks = [String: Task<Void, Never>]()

    init(
        delay: Duration,
        continuation: AsyncStream<DiscoveryInvalidation>.Continuation
    ) {
        self.delay = delay
        self.continuation = continuation
    }

    func schedule(bundleID: String?, processIdentifier: pid_t) {
        schedule(
            invalidation: .axStructureChanged(
                bundleID: bundleID,
                processIdentifier: processIdentifier
            ),
            signature: Self.signature(bundleID: bundleID, processIdentifier: processIdentifier)
        )
    }

    func scheduleObservationRecovery() {
        schedule(
            invalidation: .observationRecoveryRequired,
            signature: "observation-recovery"
        )
    }

    func finish() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
        continuation.finish()
    }

    private static func signature(bundleID: String?, processIdentifier: pid_t) -> String {
        "\(bundleID ?? "unknown-bundle")#\(processIdentifier)"
    }

    private func schedule(
        invalidation: DiscoveryInvalidation,
        signature: String
    ) {
        pendingTasks[signature]?.cancel()
        pendingTasks[signature] = Task { [delay, continuation] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }

            continuation.yield(invalidation)
        }
    }
}

final class AXObservationService: @unchecked Sendable, DiscoveryObserving {
    private enum ObserverRegistrationResult {
        case observed
        case skipped
        case recoveryRequired
    }

    private final class ObserverCallbackContext {
        let bundleID: String?
        let processIdentifier: pid_t
        let invalidationEmitter: ObservationInvalidationEmitter

        init(
            bundleID: String?,
            processIdentifier: pid_t,
            invalidationEmitter: ObservationInvalidationEmitter
        ) {
            self.bundleID = bundleID
            self.processIdentifier = processIdentifier
            self.invalidationEmitter = invalidationEmitter
        }

        func handleNotification() {
            Task {
                await invalidationEmitter.schedule(
                    bundleID: bundleID,
                    processIdentifier: processIdentifier
                )
            }
        }
    }

    private struct ObservedApplication {
        let bundleID: String?
        let observer: AXObserver
        let observedElement: AXUIElement
        let registeredNotifications: [String]
        let runLoopSource: CFRunLoopSource
        let callbackContext: ObserverCallbackContext
    }

    private final class ObserverRegistry {
        private var observedApplications = [pid_t: ObservedApplication]()

        @MainActor
        var processIdentifiers: [pid_t] {
            Array(observedApplications.keys)
        }

        @MainActor
        func contains(processIdentifier: pid_t) -> Bool {
            observedApplications[processIdentifier] != nil
        }

        @MainActor
        func insert(_ observedApplication: ObservedApplication, for processIdentifier: pid_t) {
            observedApplications[processIdentifier] = observedApplication
        }

        @MainActor
        func removeObserver(for processIdentifier: pid_t) {
            guard let observedApplication = observedApplications.removeValue(forKey: processIdentifier) else {
                return
            }

            observedApplication.registeredNotifications.forEach { notification in
                AXObserverRemoveNotification(
                    observedApplication.observer,
                    observedApplication.observedElement,
                    notification as CFString
                )
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), observedApplication.runLoopSource, .commonModes)
        }

        @MainActor
        func removeAllObservers() {
            processIdentifiers.forEach(removeObserver)
        }
    }

    @MainActor
    private static let observedNotifications = [
        "AXChildrenChanged",
        "AXValueChanged",
        "AXTitleChanged",
        "AXSelectedChildrenChanged",
    ]

    private let identityRegistry: IdentityRegistry
    private let diagLog = DiagLog(category: .discovery)
    private let invalidationStream: AsyncStream<DiscoveryInvalidation>
    private let invalidationEmitter: ObservationInvalidationEmitter
    private let observerRegistry = ObserverRegistry()
    @MainActor private var isObserverRecoveryPending = false

    init(identityRegistry: IdentityRegistry) {
        self.identityRegistry = identityRegistry
        var capturedContinuation: AsyncStream<DiscoveryInvalidation>.Continuation?
        invalidationStream = AsyncStream(bufferingPolicy: .bufferingNewest(32)) {
            capturedContinuation = $0
        }
        guard let capturedContinuation else {
            preconditionFailure("AXObservationService invalidation stream was not initialized")
        }
        invalidationEmitter = ObservationInvalidationEmitter(
            delay: .milliseconds(120),
            continuation: capturedContinuation
        )
    }

    deinit {
        let invalidationEmitter = invalidationEmitter
        let observerRegistry = observerRegistry
        Task { @MainActor in
            observerRegistry.removeAllObservers()
        }
        Task {
            await invalidationEmitter.finish()
        }
    }

    nonisolated var invalidationUpdates: AsyncStream<DiscoveryInvalidation> {
        invalidationStream
    }

    func performSetup() async {
        guard AXHelpers.isProcessTrusted() else {
            await MainActor.run {
                removeAllObservers()
                isObserverRecoveryPending = false
            }
            return
        }

        let runningApps = await MainActor.run {
            eligibleRunningApplications()
        }
        await MainActor.run {
            reconcileObservers(with: runningApps)
        }
    }

    func discoverDescriptors(displaySnapshot: DisplayObservationSnapshot) async -> [MenuExtraDescriptor] {
        await discoverDescriptors(
            displaySnapshot: displaySnapshot,
            processIdentifiers: []
        )
    }

    func discoverDescriptors(
        displaySnapshot: DisplayObservationSnapshot,
        processIdentifiers: Set<pid_t>
    ) async -> [MenuExtraDescriptor] {
        guard AXHelpers.isProcessTrusted() else {
            await MainActor.run {
                removeAllObservers()
                isObserverRecoveryPending = false
            }
            return []
        }

        let allRunningApps = await MainActor.run {
            eligibleRunningApplications()
        }
        await MainActor.run {
            reconcileObservers(with: allRunningApps)
        }

        let apps = processIdentifiers.isEmpty
            ? allRunningApps
            : allRunningApps.filter { processIdentifiers.contains($0.processIdentifier) }

        var sources = [DiscoveredMenuExtraCandidate]()

        for runningApp in apps {
            guard
                let bundleIdentifier = runningApp.bundleIdentifier,
                let application = AXHelpers.application(for: runningApp),
                let extrasMenuBar = AXHelpers.extrasMenuBar(for: application)
            else {
                continue
            }

            sources.append(
                contentsOf: AXResolvedCandidateBuilder.observedDescriptorSources(
                    for: runningApp,
                    bundleIdentifier: bundleIdentifier,
                    extrasMenuBar: extrasMenuBar,
                    displaySnapshot: displaySnapshot
                )
            )
        }

        let canonicalizedCandidates = await identityRegistry.resolve(sources)
        return canonicalizedCandidates.map {
            AXResolvedCandidateBuilder.makeDescriptor(
                source: $0.source,
                canonicalID: $0.canonicalID,
                identity: $0.identity
            )
        }
    }

    @MainActor
    private func eligibleRunningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.isFinishedLaunching &&
                !$0.isTerminated &&
                $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    @MainActor
    private func reconcileObservers(with runningApplications: [NSRunningApplication]) {
        let runningApplicationsByPID = Dictionary(
            uniqueKeysWithValues: runningApplications.map { ($0.processIdentifier, $0) }
        )

        let staleProcessIdentifiers = observerRegistry.processIdentifiers.filter {
            runningApplicationsByPID[$0] == nil
        }
        staleProcessIdentifiers.forEach { observerRegistry.removeObserver(for: $0) }

        var requiresRecovery = false

        for runningApplication in runningApplications where !observerRegistry.contains(
            processIdentifier: runningApplication.processIdentifier
        ) {
            switch addObserverIfPossible(for: runningApplication) {
            case .observed, .skipped:
                continue
            case .recoveryRequired:
                requiresRecovery = true
            }
        }

        if requiresRecovery {
            scheduleObservationRecoveryIfNeeded()
        } else {
            isObserverRecoveryPending = false
        }
    }

    @MainActor
    private func addObserverIfPossible(for runningApplication: NSRunningApplication) -> ObserverRegistrationResult {
        let processIdentifier = runningApplication.processIdentifier
        let bundleID = runningApplication.bundleIdentifier

        guard
            let application = AXHelpers.application(for: runningApplication),
            let extrasMenuBar = AXHelpers.extrasMenuBar(for: application)
        else {
            return .skipped
        }

        let callbackContext = ObserverCallbackContext(
            bundleID: bundleID,
            processIdentifier: processIdentifier,
            invalidationEmitter: invalidationEmitter
        )
        var observer: AXObserver?
        let createError = AXObserverCreate(
            processIdentifier,
            Self.axObserverCallback,
            &observer
        )

        guard createError == .success, let observer else {
            diagLog.debug(
                "Failed to create AX observer for pid \(processIdentifier): \(createError.rawValue)"
            )
            return .recoveryRequired
        }

        let rawContext = Unmanaged.passUnretained(callbackContext).toOpaque()
        var registeredNotifications = [String]()
        var encounteredRegistrationFailure = false
        for notification in Self.observedNotifications {
            let addResult = AXObserverAddNotification(
                observer,
                extrasMenuBar.element,
                notification as CFString,
                rawContext
            )

            switch addResult {
            case .success, .notificationAlreadyRegistered:
                registeredNotifications.append(notification)
                continue
            case .notificationUnsupported:
                continue
            default:
                encounteredRegistrationFailure = true
                diagLog.debug(
                    """
                    Failed to register AX notification \(notification) for pid \(processIdentifier): \
                    \(addResult.rawValue)
                    """
                )
            }
        }

        guard !registeredNotifications.isEmpty else {
            return encounteredRegistrationFailure ? .recoveryRequired : .skipped
        }

        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        observerRegistry.insert(
            ObservedApplication(
                bundleID: bundleID,
                observer: observer,
                observedElement: extrasMenuBar.element,
                registeredNotifications: registeredNotifications,
                runLoopSource: runLoopSource,
                callbackContext: callbackContext
            ),
            for: processIdentifier
        )
        return .observed
    }

    @MainActor
    private func removeAllObservers() {
        observerRegistry.removeAllObservers()
    }

    @MainActor
    private func scheduleObservationRecoveryIfNeeded() {
        guard !isObserverRecoveryPending else {
            return
        }

        isObserverRecoveryPending = true
        Task {
            await invalidationEmitter.scheduleObservationRecovery()
        }
    }

    private static let axObserverCallback: AXObserverCallback = { _, _, _, context in
        guard let context else {
            return
        }

        let callbackContext = Unmanaged<ObserverCallbackContext>
            .fromOpaque(context)
            .takeUnretainedValue()
        callbackContext.handleNotification()
    }
}

struct ResolvedCandidate {
    let element: UIElement
    let descriptor: MenuExtraDescriptor
}

struct RawResolvedCandidate {
    let element: UIElement
    let descriptor: DiscoveredMenuExtraCandidate
}

enum AXResolvedCandidateBuilder {
    static func rawResolvedCandidates(
        for runningApp: NSRunningApplication,
        bundleIdentifier: String,
        extrasMenuBar: UIElement,
        displaySnapshot: DisplayObservationSnapshot
    ) -> [RawResolvedCandidate] {
        resolveElementPairs(
            for: runningApp,
            bundleIdentifier: bundleIdentifier,
            extrasMenuBar: extrasMenuBar,
            displaySnapshot: displaySnapshot
        )
        .map { RawResolvedCandidate(element: $0.0, descriptor: $0.1) }
    }

    static func observedDescriptorSources(
        for runningApp: NSRunningApplication,
        bundleIdentifier: String,
        extrasMenuBar: UIElement,
        displaySnapshot: DisplayObservationSnapshot
    ) -> [DiscoveredMenuExtraCandidate] {
        resolveElementPairs(
            for: runningApp,
            bundleIdentifier: bundleIdentifier,
            extrasMenuBar: extrasMenuBar,
            displaySnapshot: displaySnapshot
        )
        .map(\.1)
    }

    static func makeDescriptor(
        source: DiscoveredMenuExtraCandidate,
        canonicalID: MenuExtraCanonicalID,
        identity: MenuExtraIdentity
    ) -> MenuExtraDescriptor {
        MenuExtraDescriptor(
            canonicalID: canonicalID,
            identity: identity,
            ownerPID: source.ownerPID,
            bundleIdentifier: source.bundleIdentifier,
            bundleURL: source.bundleURL,
            applicationName: source.applicationName,
            title: source.title,
            rawRole: source.rawRole,
            frame: source.frame,
            displayID: source.displayID,
            displayUUID: source.displayUUID,
            capability: source.capability,
            group: .hidden,
            customName: nil
        )
    }

    private static func resolveElementPairs(
        for runningApp: NSRunningApplication,
        bundleIdentifier: String,
        extrasMenuBar: UIElement,
        displaySnapshot: DisplayObservationSnapshot
    ) -> [(UIElement, DiscoveredMenuExtraCandidate)] {
        let children = AXHelpers.children(for: extrasMenuBar)
            .filter { AXHelpers.isEnabled($0) }

        let sortedChildren = children.sorted { lhs, rhs in
            let leftFrame = AXHelpers.frame(for: lhs) ?? .zero
            let rightFrame = AXHelpers.frame(for: rhs) ?? .zero
            if leftFrame.minY != rightFrame.minY {
                return leftFrame.minY < rightFrame.minY
            }
            return leftFrame.minX < rightFrame.minX
        }

        return sortedChildren.enumerated().compactMap { index, child in
            let title = AXHelpers.title(for: child) ??
                AXHelpers.axDescription(for: child) ??
                runningApp.localizedName ??
                bundleIdentifier

            let role = AXHelpers.role(for: child)?.rawValue ?? "AXUnknown"
            let axIdentifier = AXHelpers.identifier(for: child)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = MenuExtraIdentity.normalizedTitle(title)

            let actions = AXHelpers.actions(for: child)
            let capability: MenuExtraCapability
            if actions.contains(.press) || actions.contains(.showMenu) {
                capability = .axPress
            } else if runningApp.activationPolicy != .prohibited {
                capability = .openApp
            } else {
                capability = .unsupported
            }

            let frame = AXHelpers.frame(for: child)
            let displayID = displaySnapshot.displayID(for: frame?.center)
            let displayUUID = displaySnapshot.displayUUID(for: displayID)

            let descriptor = DiscoveredMenuExtraCandidate(
                ownerPID: runningApp.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                bundleURL: runningApp.bundleURL,
                applicationName: runningApp.localizedName ?? bundleIdentifier,
                title: title,
                normalizedTitle: normalizedTitle,
                rawRole: role,
                axIdentifier: axIdentifier,
                slotIndex: index,
                slotSignature: "\(displayUUID ?? "unknown"):\(index)",
                frame: frame,
                displayID: displayID,
                displayUUID: displayUUID,
                capability: capability
            )

            return (child, descriptor)
        }
    }
}
