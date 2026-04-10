//
//  DiscoveryService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

struct DiscoveryServiceState: Hashable, Sendable {
    let snapshot: DiscoverySnapshot
    let layoutSnapshot: ProfileLayoutV3
    let isReady: Bool
    let lastRefreshAt: Date?

    static let empty = DiscoveryServiceState(
        snapshot: .empty,
        layoutSnapshot: .empty,
        isReady: false,
        lastRefreshAt: nil
    )
}

actor DiscoveryService {
    private enum RefreshScope: Equatable {
        case all
        case processIdentifiers(Set<pid_t>)
    }

    private struct RefreshOutcome {
        let reconcileSummary: LayoutService.ReconcileSummary
        let previousDescriptorCount: Int
    }

    private struct PendingRefreshRequest {
        let invalidation: DiscoveryInvalidation
        var continuations = [CheckedContinuation<Void, Never>]()
    }

    private struct PendingWorkspaceActivation {
        let signature: String
        let invalidation: DiscoveryInvalidation
    }

    private let diagLog = DiagLog(category: .discovery)
    private let consistencyFollowUpDelay = Duration.seconds(4)
    private let workspaceActivationDebounce = Duration.milliseconds(250)
    private let explicitActivationSuppressionWindow = Duration.milliseconds(500)
    private let thawInitiatedActivationGracePeriod = Duration.seconds(1)

    private let observationService: any DiscoveryObserving
    private let displayService: DisplayService
    private let workspaceEventSource: WorkspaceEventSource
    private let layoutService: LayoutService
    private let identityRegistry: IdentityRegistry
    private let stateContinuation: AsyncStream<DiscoveryServiceState>.Continuation
    private let stateStream: AsyncStream<DiscoveryServiceState>

    private var state = DiscoveryServiceState.empty
    private var hasPerformedSetup = false
    private var consistencyRefreshTask: Task<Void, Never>?
    private var observationInvalidationTask: Task<Void, Never>?
    private var workspaceActivationRefreshTask: Task<Void, Never>?
    private var isExclusiveOperationActive = false
    private var pendingRefreshRequests = [PendingRefreshRequest]()
    private var pendingWorkspaceActivation: PendingWorkspaceActivation?
    private var lastProcessedWorkspaceActivationSignature: String?
    private var lastExplicitActivationRefreshSignature: String?
    private var lastExplicitActivationRefreshAt: ContinuousClock.Instant?
    private var lastThawInitiatedActivationAt: ContinuousClock.Instant?

    init(
        displayService: DisplayService,
        identityRegistry: IdentityRegistry,
        workspaceEventSource: WorkspaceEventSource,
        observationService: any DiscoveryObserving,
        layoutService: LayoutService = LayoutService()
    ) {
        var capturedStateContinuation: AsyncStream<DiscoveryServiceState>.Continuation?
        let stateStream = AsyncStream<DiscoveryServiceState>(bufferingPolicy: .bufferingNewest(1)) {
            capturedStateContinuation = $0
        }
        guard let stateContinuation = capturedStateContinuation else {
            preconditionFailure("DiscoveryService state stream continuation was not initialized")
        }

        self.displayService = displayService
        self.identityRegistry = identityRegistry
        self.workspaceEventSource = workspaceEventSource
        self.layoutService = layoutService
        self.observationService = observationService
        self.stateStream = stateStream
        self.stateContinuation = stateContinuation
        stateContinuation.yield(state)
    }

    deinit {
        consistencyRefreshTask?.cancel()
        observationInvalidationTask?.cancel()
        workspaceActivationRefreshTask?.cancel()
        stateContinuation.finish()
    }

    nonisolated var stateUpdates: AsyncStream<DiscoveryServiceState> {
        stateStream
    }

    func currentState() -> DiscoveryServiceState {
        state
    }

    func performSetup() async {
        guard !hasPerformedSetup else {
            return
        }

        hasPerformedSetup = true
        await observationService.performSetup()
        startObservationInvalidationTaskIfNeeded()
        await refresh(invalidation: .startup)
    }

    func refresh(_ invalidation: DiscoveryInvalidation) async {
        await refresh(invalidation: invalidation)
    }

    func refresh(invalidation: DiscoveryInvalidation) async {
        RuntimeMetrics.shared.incrementInvalidationCount(cause: invalidation.runtimeMetricCause)

        switch invalidation {
        case .appActivated(let bundleID, let processIdentifier):
            handleWorkspaceActivation(bundleID: bundleID, processIdentifier: processIdentifier)
            return
        default:
            break
        }

        guard beginExclusiveOperation() else {
            await withCheckedContinuation { continuation in
                enqueueDeferredRefresh(invalidation, continuation: continuation)
            }
            return
        }

        let outcome = await performRefresh(invalidation: invalidation)
        updateConsistencyFollowUp(after: invalidation, outcome: outcome)
        await recordRefreshState(after: invalidation)
        await finishExclusiveOperation()
    }

    func currentLayoutSnapshot() -> ProfileLayoutV3 {
        layoutService.snapshot()
    }

    func applyLayoutSnapshot(_ profileLayout: ProfileLayoutV3) {
        layoutService.apply(profileLayout)
        publishState(
            snapshot: DiscoverySnapshot(
                descriptors: layoutService.orderedDescriptors(from: state.snapshot.descriptors),
                generatedAt: Date()
            ),
            isReady: state.isReady,
            lastRefreshAt: state.lastRefreshAt
        )
    }

    func resetSuggestedLayout() {
        layoutService.resetSuggestedLayout(for: state.snapshot.descriptors)
        publishState(
            snapshot: DiscoverySnapshot(
                descriptors: layoutService.orderedDescriptors(from: state.snapshot.descriptors),
                generatedAt: Date()
            ),
            isReady: state.isReady,
            lastRefreshAt: state.lastRefreshAt
        )
    }

    func assign(_ group: VirtualGroup, to canonicalID: MenuExtraCanonicalID) {
        layoutService.assign(group: group, to: canonicalID)
        publishState(
            snapshot: DiscoverySnapshot(
                descriptors: layoutService.orderedDescriptors(from: state.snapshot.descriptors),
                generatedAt: Date()
            ),
            isReady: state.isReady,
            lastRefreshAt: state.lastRefreshAt
        )
    }

    func rename(canonicalID: MenuExtraCanonicalID, to customName: String?) {
        layoutService.rename(canonicalID: canonicalID, to: customName)
        publishState(
            snapshot: DiscoverySnapshot(
                descriptors: layoutService.orderedDescriptors(from: state.snapshot.descriptors),
                generatedAt: Date()
            ),
            isReady: state.isReady,
            lastRefreshAt: state.lastRefreshAt
        )
    }

    func reorder(group: VirtualGroup, descriptors: [MenuExtraDescriptor]) {
        layoutService.setOrder(for: group, canonicalIDs: descriptors.map(\.canonicalID))
        publishState(
            snapshot: DiscoverySnapshot(
                descriptors: layoutService.orderedDescriptors(from: state.snapshot.descriptors),
                generatedAt: Date()
            ),
            isReady: state.isReady,
            lastRefreshAt: state.lastRefreshAt
        )
    }

    private func performRefresh(invalidation: DiscoveryInvalidation) async -> RefreshOutcome {
        let start = ContinuousClock.now
        let previousDescriptorCount = state.snapshot.descriptors.count
        let displaySnapshot = await MainActor.run { displayService.observationSnapshot() }
        let refreshScope = await refreshScope(for: invalidation)
        let reconciledDescriptors = await descriptors(
            afterApplying: refreshScope,
            displaySnapshot: displaySnapshot
        )
        let summary = layoutService.reconcile(with: reconciledDescriptors)
        let snapshot = DiscoverySnapshot(
            descriptors: layoutService.orderedDescriptors(from: reconciledDescriptors),
            generatedAt: Date()
        )
        publishState(snapshot: snapshot, isReady: true, lastRefreshAt: snapshot.generatedAt)

        let unsupportedCount = reconciledDescriptors.filter { $0.capability == .unsupported }.count
        let duration = start.duration(to: .now)
        RuntimeMetrics.shared.recordDiscoveryDuration(duration.timeInterval)
        diagLog.debug(
            """
            Discovery refresh (\(invalidation)) produced \(summary.liveDescriptorCount) descriptors \
            (\(unsupportedCount) unsupported) in \(duration)
            """
        )

        return RefreshOutcome(
            reconcileSummary: summary,
            previousDescriptorCount: previousDescriptorCount
        )
    }

    private func startObservationInvalidationTaskIfNeeded() {
        guard observationInvalidationTask == nil else {
            return
        }

        let invalidationUpdates = observationService.invalidationUpdates
        observationInvalidationTask = Task { [weak self] in
            for await invalidation in invalidationUpdates {
                await self?.refresh(invalidation: invalidation)
            }
        }
    }

    private func refreshScope(for invalidation: DiscoveryInvalidation) async -> RefreshScope {
        switch invalidation {
        case .startup,
             .observationRecoveryRequired,
             .permissionChanged,
             .layoutEditorPresented,
             .layoutReset,
             .panelPreparation,
             .panelPresented,
             .profileApplied,
             .displayConfigurationChanged,
             .consistencyFollowUp:
            return .all
        case .appLaunched(_, let processIdentifier),
             .appTerminated(_, let processIdentifier),
             .axStructureChanged(_, let processIdentifier):
            return .processIdentifiers([processIdentifier])
        case .workspaceActivationSettled:
            guard let frontmostApplication = await MainActor.run(body: {
                workspaceEventSource.frontmostApplication
            }) else {
                return .all
            }

            guard !frontmostApplication.isCurrentApplication else {
                return .all
            }

            return .processIdentifiers([frontmostApplication.processIdentifier])
        case .activationFollowUp(let canonicalID, _, _):
            guard let descriptor = descriptor(withCanonicalID: canonicalID) else {
                return .all
            }

            return .processIdentifiers([descriptor.ownerPID])
        case .appActivated(_, let processIdentifier):
            return .processIdentifiers([processIdentifier])
        }
    }

    private func descriptors(
        afterApplying refreshScope: RefreshScope,
        displaySnapshot: DisplayObservationSnapshot
    ) async -> [MenuExtraDescriptor] {
        switch refreshScope {
        case .all:
            return await observationService.discoverDescriptors(
                displaySnapshot: displaySnapshot
            )
        case .processIdentifiers(let processIdentifiers):
            guard !processIdentifiers.isEmpty else {
                return await observationService.discoverDescriptors(
                    displaySnapshot: displaySnapshot
                )
            }

            let refreshedDescriptors = await observationService.discoverDescriptors(
                displaySnapshot: displaySnapshot,
                processIdentifiers: processIdentifiers
            )
            let unaffectedDescriptors = state.snapshot.descriptors.filter {
                !processIdentifiers.contains($0.ownerPID)
            }
            return unaffectedDescriptors + refreshedDescriptors
        }
    }

    private func finishExclusiveOperation() async {
        guard let request = dequeueDeferredRefreshRequest() else {
            isExclusiveOperationActive = false
            return
        }

        isExclusiveOperationActive = true
        let outcome = await performRefresh(invalidation: request.invalidation)
        updateConsistencyFollowUp(after: request.invalidation, outcome: outcome)
        await recordRefreshState(after: request.invalidation)
        request.continuations.forEach { $0.resume() }
        await finishExclusiveOperation()
    }

    private func updateConsistencyFollowUp(
        after invalidation: DiscoveryInvalidation,
        outcome: RefreshOutcome
    ) {
        if case .consistencyFollowUp = invalidation {
            consistencyRefreshTask = nil
            return
        }

        if case .appActivated = invalidation {
            return
        }

        guard let trigger = invalidation.consistencyFollowUpTrigger else {
            if case .workspaceActivationSettled = invalidation {
                return
            }
            if outcome.reconcileSummary.retainedAssignmentCount == 0 {
                cancelConsistencyFollowUp()
            }
            return
        }

        let liveDescriptorCount = outcome.reconcileSummary.liveDescriptorCount
        let shouldSchedule = switch trigger {
        case .workspaceDidLaunch:
            true
        case .workspaceDidTerminate, .icebarActivateLeft, .icebarActivateRight:
            liveDescriptorCount != outcome.previousDescriptorCount
        }

        if shouldSchedule {
            scheduleConsistencyFollowUp(trigger: trigger)
        } else {
            cancelConsistencyFollowUp()
        }
    }

    private func scheduleConsistencyFollowUp(trigger: DiscoveryConsistencyFollowUpTrigger) {
        cancelConsistencyFollowUp()
        let delay = consistencyFollowUpDelay

        consistencyRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            await self?.refresh(.consistencyFollowUp(trigger: trigger))
        }
    }

    private func cancelConsistencyFollowUp() {
        consistencyRefreshTask?.cancel()
        consistencyRefreshTask = nil
    }

    private func handleWorkspaceActivation(bundleID: String?, processIdentifier: pid_t) {
        if let lastThawInitiatedActivationAt,
           lastThawInitiatedActivationAt.duration(to: .now) < thawInitiatedActivationGracePeriod
        {
            return
        }

        let signature = workspaceActivationSignature(
            bundleID: bundleID,
            processIdentifier: processIdentifier
        )

        if pendingWorkspaceActivation?.signature == signature, workspaceActivationRefreshTask != nil {
            return
        }

        pendingWorkspaceActivation = PendingWorkspaceActivation(
            signature: signature,
            invalidation: .workspaceActivationSettled
        )
        workspaceActivationRefreshTask?.cancel()
        let debounce = workspaceActivationDebounce

        workspaceActivationRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else {
                return
            }
            await self?.processWorkspaceActivationAfterDebounce(expectedSignature: signature)
        }
    }

    private func processWorkspaceActivationAfterDebounce(expectedSignature: String) async {
        defer {
            if pendingWorkspaceActivation?.signature == expectedSignature {
                pendingWorkspaceActivation = nil
                workspaceActivationRefreshTask = nil
            }
        }

        guard let pendingWorkspaceActivation,
              pendingWorkspaceActivation.signature == expectedSignature else {
            return
        }

        guard let finalSignature = await currentWorkspaceActivationSignature() else {
            return
        }

        guard shouldRefreshForWorkspaceActivation(signature: finalSignature) else {
            return
        }

        await refresh(pendingWorkspaceActivation.invalidation)
    }

    private func shouldRefreshForWorkspaceActivation(signature: String) -> Bool {
        if lastProcessedWorkspaceActivationSignature == signature {
            return false
        }

        if let lastExplicitActivationRefreshAt,
           let lastExplicitActivationRefreshSignature,
           lastExplicitActivationRefreshSignature == signature,
           lastExplicitActivationRefreshAt.duration(to: .now) < explicitActivationSuppressionWindow
        {
            return false
        }

        return true
    }

    private func recordRefreshState(after invalidation: DiscoveryInvalidation) async {
        guard let signature = await currentWorkspaceActivationSignature() else {
            return
        }

        switch invalidation {
        case .workspaceActivationSettled:
            lastProcessedWorkspaceActivationSignature = signature
        case .activationFollowUp(_, let surface, let intent)
            where surface == .quickAccess && (intent == .primary || intent == .secondary):
            lastProcessedWorkspaceActivationSignature = signature
            lastExplicitActivationRefreshSignature = signature
            lastExplicitActivationRefreshAt = .now
        default:
            break
        }
    }

    private func currentWorkspaceActivationSignature() async -> String? {
        await MainActor.run {
            guard let frontmostApplication = workspaceEventSource.frontmostApplication else {
                return nil
            }

            guard !frontmostApplication.isCurrentApplication else {
                return nil
            }

            return frontmostApplication.activationSignature
        }
    }

    private func workspaceActivationSignature(
        bundleID: String?,
        processIdentifier: pid_t
    ) -> String {
        let bundleID = bundleID ?? "unknown-bundle"
        return "\(bundleID)#\(processIdentifier)"
    }

    private func descriptor(withCanonicalID canonicalID: MenuExtraCanonicalID) -> MenuExtraDescriptor? {
        state.snapshot.descriptors.first(where: { $0.canonicalID == canonicalID })
    }

    private func beginExclusiveOperation() -> Bool {
        guard !isExclusiveOperationActive else {
            return false
        }
        isExclusiveOperationActive = true
        return true
    }

    private func enqueueDeferredRefresh(
        _ invalidation: DiscoveryInvalidation,
        continuation: CheckedContinuation<Void, Never>
    ) {
        if let existingRequestIndex = pendingRefreshRequests.firstIndex(where: { $0.invalidation == invalidation }) {
            pendingRefreshRequests[existingRequestIndex].continuations.append(continuation)
            return
        }

        pendingRefreshRequests.append(
            PendingRefreshRequest(invalidation: invalidation, continuations: [continuation])
        )
    }

    private func dequeueDeferredRefreshRequest() -> PendingRefreshRequest? {
        guard !pendingRefreshRequests.isEmpty else {
            return nil
        }

        return pendingRefreshRequests.removeFirst()
    }

    private func publishState(
        snapshot: DiscoverySnapshot,
        isReady: Bool,
        lastRefreshAt: Date?
    ) {
        let newState = DiscoveryServiceState(
            snapshot: snapshot,
            layoutSnapshot: layoutService.snapshot(),
            isReady: isReady,
            lastRefreshAt: lastRefreshAt
        )

        guard newState != state else {
            return
        }

        state = newState
        stateContinuation.yield(newState)
    }
}

extension DiscoveryService: ActivationContextProviding {
    func descriptor(for canonicalID: MenuExtraCanonicalID) async -> MenuExtraDescriptor? {
        descriptor(withCanonicalID: canonicalID)
    }

    func recordThawInitiatedActivation() async {
        lastThawInitiatedActivationAt = .now
    }
}
