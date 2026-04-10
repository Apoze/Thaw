# Thaw V3 Execution Backlog

This document operationalizes [`PLANS.md`](../PLANS.md). If there is any conflict, `PLANS.md` wins.

Scope:
- remaining V3 work after the Focus Filter correction
- sequencing, lot boundaries, and exit criteria
- file-level implementation targets

Out of scope:
- changing the architecture target
- weakening acceptance criteria
- reintroducing legacy compatibility outside the plan

## Working Rules
- Execute lots in order unless the dependency line explicitly allows overlap.
- Do not start a later lot while a blocker or architecture regression is still open in an earlier lot.
- Close every lot with:
  1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Thaw -configuration Debug build`
  2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict`
  3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Thaw -configuration Debug test`
  4. lot-specific grep review
  5. short architecture review against [`PLANS.md`](../PLANS.md)
- New permanent runtime authorities should be added under `Thaw/Runtime/` or the domain folder that will survive V3. Do not deepen `Thaw/RuntimeV2/` with new long-lived code.
- `Thaw/Utilities/Migration.swift` and `Thaw/RuntimeV2/StartupCoordinator.swift` are already absent in this local clone. Keep them absent; do not recreate them as compatibility shells.

## Status Snapshot
- Done and locked: Focus Filter correction in `Permissions and Focus Filters`.
- Done: `Phase 0`.
- Partial: `Phase 1`, `Phase 2`, `Phase 3`, `Phase 4`, `Phase 5`.
- Not finished: `Phase 6`, `Phase 7`.

## Sequence Overview

| Lot | Epic | Status | Estimate | Depends on | Main outcome |
| --- | --- | --- | --- | --- | --- |
| `0.0` | Focus guard rail | done | `0.5d` if touched again | none | Keep the Focus boundary stable |
| `0.1` | Phase 0 | done | `1-2d` | none | Observability, fixtures, baseline contracts |
| `1.1` | Phase 1 | done | `2-3d` | `0.1` | `AppGraph` becomes the real bootstrap root |
| `1.2` | Phase 1 | done | `2-4d` | `1.1` | `MigrationCoordinator`, `WorkspaceEventSource`, `DisplayService` |
| `1.3` | Phase 1 | done | `2-3d` | `1.2` | Explicit AppKit ownership and adapter boundaries |
| `2.1` | Phase 2 | done | `3-5d` | `1.3` | Canonical identity persistence and migration readers |
| `2.2` | Phase 2 | done | `2-4d` | `2.1` | Shadow mode, corpus replay, threshold sign-off |
| `3.1` | Phase 3 | done | `2-3d` | `2.1` | Typed discovery invalidations, no string reasons |
| `3.2` | Phase 3 | done | `3-5d` | `3.1` | Actor discovery, immutable snapshots, AX split |
| `4.1` | Phase 4 | done | `2-4d` | `3.2` | Transactional activation and panel contract |
| `5.1` | Phase 5 | done | `4-6d` | `4.1` | `LayoutService` and `ProfileLayoutV3` |
| `5.2` | Phase 5 | done | `3-5d` | `5.1` | `ProfilesService`, `ProfileManager` demotion, final terminology |
| `6.1` | Phase 6 | done | `2-4d` | `5.2` | V3 becomes the only active runtime path |
| `7.1` | Phase 7 | not started | `2-3d` | `6.1` | Physical legacy deletion |
| `7.2` | Acceptance gate | not started | `1-2d` | `7.1` | Final validation matrix and sign-off |

## Lot Details

### Lot `0.0` — Focus boundary lock
- Epic: `Permissions and Focus Filters`
- Status: done
- Estimate: `0.5d` if touched again during later refactors
- Depends on: none
- Files to protect:
  - `Thaw/Settings/Models/FocusFilterService.swift`
  - `Thaw/Settings/Models/FocusFilterIntent.swift`
  - `Thaw/Settings/Models/ProfileManager.swift`
  - `Thaw/Main/AppGraph.swift`
  - `ThawTests/FocusFilterServiceTests.swift`
  - `ThawTests/ProfileManagerFocusRuntimeTests.swift`
  - `ThawTests/ProfileManagerPersistenceTests.swift`
- Tasks:
  1. Preserve `FocusFilterService` as the only runtime Focus authority.
  2. Prevent bootstrap probing from re-entering `ProfileManager` or future `ProfilesService`.
  3. Keep Focus runtime state out of profile persistence, export, and import paths.
- Tests to keep green:
  - `FocusFilterServiceTests`
  - `ProfileManagerFocusRuntimeTests`
  - `ProfileManagerPersistenceTests`
- Exit grep:
  - `rg -n "ThawFocusFilter\\.current" Thaw`
    Expectation: only `Thaw/Settings/Models/FocusFilterService.swift` may remain.
  - `rg -n "FocusFilterRequestedProfileID" Thaw | rg "Profile\\.swift|export|import|manifest"`
    Expectation: no hits.
- Risks:
  - a future `ProfilesService` extraction reintroduces App Intents probing at bootstrap
  - transient Focus state leaks into persisted profile data

### Lot `0.1` — Observability and baseline contracts
- Epic: `Phase 0: Foundations and observability`
- Status: done
- Estimate: `1-2d`
- Depends on: none
- Main files to touch:
  - `Shared/Utilities/DiagnosticLogger.swift`
  - `Thaw/Main/AppGraph.swift`
  - `Thaw/Main/AppState.swift`
  - `Thaw/RuntimeV2/CommandRouter.swift`
  - `ThawTests/Fixtures/`
  - `ThawTests/CommandRouterTests.swift`
  - `ThawIntegrationTests/LayoutPersistenceIntegrationTests.swift`
  - new `ThawTests/PersistenceMigrationTests.swift`
  - new `ThawIntegrationTests/StartupBaselineIntegrationTests.swift`
- Tasks:
  1. Introduce typed logging categories that match the plan categories exactly.
  2. Add runtime metrics for discovery, activation, identity churn, invalidation counts, layout mutations, confidence changes, and ambiguity.
  3. Expand migration fixtures beyond `profile-layout-v2.json`.
  4. Freeze external compatibility through tests for hotkeys, `thaw://`, and profile files already on disk.
- Tests to add or expand:
  - create `PersistenceMigrationTests`
  - expand `CommandRouterTests`
  - create `StartupBaselineIntegrationTests`
- Exit grep:
  - `rg -n "enum DiagLogCategory|case startup|case permission|case discovery|case identity|case activation|case layout|case profiles|case focus|case panel" Thaw/Runtime/Observability/RuntimeObservability.swift`
    Expectation: typed categories match the plan exactly.
  - `rg -n "profile-layout-v2|Fixtures" ThawTests ThawIntegrationTests`
    Expectation: fixtures are present and referenced by tests.
  - `rg -n "ThawFocusFilter\\.current" Thaw`
    Expectation: only `Thaw/Settings/Models/FocusFilterService.swift` remains.
- Risks:
  - later migrations proceed without measurable regressions
  - compatibility breakages go unnoticed because the baseline is not frozen

### Lot `1.1` — Make `AppGraph` the real bootstrap root
- Epic: `Phase 1: App graph and single bootstrap authority`
- Status: done
- Estimate: `2-3d`
- Depends on: `0.1`
- Main files to touch:
  - `Thaw/Main/AppGraph.swift`
  - `Thaw/Main/AppState.swift`
  - `Thaw/Main/AppDelegate.swift`
  - new `Thaw/Main/AppSessionModel.swift`
  - new `ThawTests/AppGraphBootstrapTests.swift`
  - new `ThawTests/PermissionServiceTests.swift`
  - `ThawIntegrationTests/StartupBaselineIntegrationTests.swift`
- Tasks:
  1. Move startup sequencing into `AppGraph`.
  2. Reduce `AppState` to session/UI state and thin adapters.
  3. Remove `performSetup(hasPermissions:)` style orchestration from `AppState`.
  4. Make `AppDelegate` a thin AppKit bridge that forwards lifecycle events into the graph.
- Tests to add or expand:
  - create `AppGraphBootstrapTests`
  - create `PermissionServiceTests`
  - expand `StartupBaselineIntegrationTests`
- Exit grep:
  - `rg -n "performSetup\\(hasPermissions:|permissions\\.permissionsState" Thaw/Main`
    Expectation: no active startup gating remains in `AppState` or `AppDelegate`.
  - `rg -n "lazy var (identityRegistry|discoveryRuntime|iceBarAdapter|searchPanelAdapter|hotkeySessionAdapter|layoutEditorAdapter)" Thaw/Main/AppState.swift`
    Expectation: no runtime authority is still owned directly by `AppState`.
- Risks:
  - breaking first launch, permissions onboarding, or hot reload of app state
  - moving too much UI state out of `AppState` and destabilizing window/session behavior
- Completion notes:
  - `AppGraph` owns startup sequencing and settings URL routing.
  - `PermissionService` is a concrete runtime boundary, not just a typealias façade.
  - `AppDelegate` is reduced to lifecycle forwarding and AppKit bridging.

### Lot `1.2` — Centralize migration, workspace, and display authority
- Epic: `Phase 1: App graph and single bootstrap authority`
- Status: done
- Estimate: `2-4d`
- Depends on: `1.1`
- Main files to touch:
  - `Thaw/Main/AppGraph.swift`
  - `Thaw/Main/AppDelegate.swift`
  - `Thaw/RuntimeV2/DisplayRuntime.swift`
  - `Thaw/Settings/Models/DisplaySettingsManager.swift`
  - `Thaw/Settings/Models/GeneralSettings.swift`
  - new `Thaw/Runtime/Bootstrap/MigrationCoordinator.swift`
  - new `Thaw/Runtime/Workspace/WorkspaceEventSource.swift`
  - new `Thaw/Runtime/Display/DisplayService.swift`
  - new `ThawTests/MigrationCoordinatorTests.swift`
  - new `ThawTests/WorkspaceEventSourceTests.swift`
  - new `ThawTests/DisplayServiceTests.swift`
- Tasks:
  1. Introduce `MigrationCoordinator` as the only migration authority.
  2. Introduce `WorkspaceEventSource` for typed workspace and display invalidations.
  3. Evolve `DisplayRuntime` into `DisplayService`.
  4. Remove any remaining startup dependency on legacy permission state and display helpers.
- Tests to add or expand:
  - create `MigrationCoordinatorTests`
  - create `WorkspaceEventSourceTests`
  - create `DisplayServiceTests`
  - expand `StartupBaselineIntegrationTests`
- Exit grep:
  - `rg -n "NSWorkspace|didLaunchApplicationNotification|didTerminateApplicationNotification|didActivateApplicationNotification|didChangeScreenParametersNotification" Thaw | rg -v "WorkspaceEventSource|DisplayService|Tests"`
    Expectation: no stray workspace/display observation outside the boundary owners.
  - `rg -n "migrat" Thaw | rg -v "MigrationCoordinator|Tests|docs"`
    Expectation: manual audit shows no boot migration path outside `MigrationCoordinator`.
- Risks:
  - migration logic remains duplicated in profile/layout code
  - display events continue to bypass the typed invalidation path
- Completion notes:
  - `MigrationCoordinator` now owns the active bootstrap rewrites for legacy layout envelopes and identity registry canonical-ID upgrades.
  - `LayoutService` and `IdentityRegistry` are compat readers on init/load; they no longer rewrite persistence implicitly during bootstrap.
  - `WorkspaceEventSource` is the sole workspace/display notification owner.
  - `DisplayService` is now the shared display authority for startup/runtime consumers.
  - Remaining `migrat*` references in layout/profile code are tracked as Phase 2 compatibility debt, not active bootstrap rewrites.

### Lot `1.3` — Explicit AppKit ownership and adapter boundaries
- Epic: `Phase 1: App graph and single bootstrap authority`
- Status: done
- Estimate: `2-3d`
- Depends on: `1.2`
- Main files to touch:
  - `Thaw/RuntimeV2/MenuChromeController.swift`
  - `Thaw/RuntimeV2/PanelRuntime.swift`
  - `Thaw/MenuBar/Search/MenuBarSearchPanel.swift`
  - `Thaw/MenuBar/IceBar/IceBar.swift`
  - `Thaw/MenuBar/Search/MenuBarSearchModel.swift`
  - `Thaw/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`
  - `Thaw/RuntimeV2/MenuBarLayoutEditorAdapter.swift`
  - new `ThawTests/ViewAdapterTests.swift`
- Tasks:
  1. Make `MenuChromeController` the single owner of status item and panel lifetime.
  2. Keep views/view-models side-effect free and snapshot-driven.
  3. Remove direct runtime reads from SwiftUI surfaces.
  4. Finish adapter boundaries for compact bar, panel content, search, and layout editor.
- Tests to add or expand:
  - create `ViewAdapterTests`
  - expand `CommandRouterTests`
  - add adapter coverage to integration tests where needed
- Exit grep:
  - `rg -n "DiscoveryRuntime|ActivationService|AXRuntime|DisplayRuntime" Thaw/MenuBar Thaw/Settings | rg -v "Adapter|Tests"`
    Expectation: no view or settings surface talks directly to low-level runtime services.
  - `rg -n "MenuChromeController" Thaw`
    Expectation: panel/status ownership is concentrated there.
- Risks:
  - AppKit ownership remains split across window/panel/menu classes
  - SwiftUI surfaces keep hidden side effects and make later cutover fragile
- Completion notes:
  - `MenuChromeController` no longer depends on `AppState`; it is wired with explicit chrome dependencies from `AppGraph`.
  - `IceBarPanel` no longer reaches into `AppState` for its adapter and does not retain `IceBarAdapter`, avoiding a new runtime cycle.
  - `PanelService` now depends on explicit panel/discovery/display protocols instead of `AppState`, with dedicated unit coverage for show/toggle/search flows.
  - The remaining menu bar profile-menu plumbing no longer reads `ProfileManager` directly; it goes through an explicit `MenuBarSessionAdapter.ProfileMenuEntry` contract.
  - Source-boundary tests now lock the removal of `AppState` from `MenuChromeController`, `PanelService`, and `IceBarPanel`.
  - The lot exit grep for low-level runtime references in `MenuBar` and `Settings` is clean on the active path.
  - `1.3 reopen` removed the remaining `AppState` leaks inside `Thaw/MenuBar`; the temporary `MenuBarSection` compatibility shell introduced during that cleanup was later retired in `7.1`, while [`MenuBarAppearanceManager.swift`](/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/Appearance/MenuBarAppearanceManager.swift) now takes explicit `DisplayService` and `MenuBarOverlayAdapter` dependencies.
  - `ViewAdapterTests` guard those source boundaries directly, and the reopen greps `rg -n "performSetup\\(with appState: AppState\\)" Thaw/MenuBar` and `rg -n "AppState" Thaw/MenuBar | rg -v "Tests"` are both clean.

### Lot `2.1` — Canonical identity persistence and migration readers
- Epic: `Phase 2: Canonical identity registry`
- Status: done
- Estimate: `3-5d`
- Depends on: `1.3`
- Main files to touch:
  - `Thaw/RuntimeV2/IdentityRegistry.swift`
  - `Thaw/RuntimeV2/PersistenceModels.swift`
  - `Thaw/RuntimeV2/MenuExtraModels.swift`
  - `Thaw/Settings/Models/Profile.swift`
  - `ThawTests/IdentityRegistryTests.swift`
  - `ThawTests/PersistenceMigrationTests.swift`
- Tasks:
  1. Finalize versioned persistence for canonical IDs and dormant assignments.
  2. Add V2 readers needed for identity and layout/profile migration.
  3. Remove any remaining layout-layer transfer/rekey responsibility.
  4. Ensure all future layout persistence writes are canonical-ID based.
- Tests to add or expand:
  - expand `IdentityRegistryTests`
  - expand `PersistenceMigrationTests`
- Exit grep:
  - `rg -n "IdentityRegistryMode|IdentityRegistryDiagnostics|registerDormantReferencedIdentityIDs|PersistentEnvelope<IdentityRegistrySnapshot>" Thaw`
    Expectation: identity persistence surface is explicit and covered.
  - `rg -n "transfer|rekey" Thaw | rg -v "docs|Tests"`
    Expectation: no active layout transfer/rekey behavior remains.
- Risks:
  - canonical IDs drift during migration
  - dormant assignments are dropped or silently rebound
- Completion notes:
  - `IdentityRegistry` now persists a versioned canonical snapshot with explicit `mode`, `diagnostics`, and dormant records, and legacy snapshots derive deterministic canonical IDs before rewrite.
  - `LayoutService` is canonical-only on the runtime path; legacy reference upgrades happen only through explicit compatibility migration and reader/import boundaries.
  - `ProfileManager` canonicalizes imported and loaded profile layouts at the reader boundary so persisted V3 profile files no longer retain legacy layout identifiers after import/load.
  - `IdentityRegistryTests`, `PersistenceMigrationTests`, `LayoutServiceTests`, and `ProfileManagerPersistenceTests` now lock stable canonical-ID migration, boundary-only canonicalization, and the absence of Focus runtime state in persisted profiles.

### Lot `2.2` — Shadow mode, calibration corpus, and threshold sign-off
- Epic: `Phase 2: Canonical identity registry`
- Status: done
- Estimate: `2-4d`
- Depends on: `2.1`
- Main files to touch:
  - `Thaw/RuntimeV2/IdentityRegistry.swift`
  - `ThawTests/IdentityRegistryTests.swift`
  - new `ThawTests/Fixtures/identity-corpus/`
  - new `ThawIntegrationTests/IdentityCalibrationReplayTests.swift`
  - docs artifacts for scoring reports
- Tasks:
  1. Add the redacted calibration corpus to tests/fixtures.
  2. Replay current resolver vs new registry in shadow mode.
  3. Emit churn, reassignment, ambiguity, and false auto-bind reports.
  4. Capture explicit threshold sign-off before activating final identity cutover.
- Tests to add or expand:
  - create `IdentityCalibrationReplayTests`
  - expand `IdentityRegistryTests`
- Exit grep:
  - `rg -n "shadow|IdentityRegistryMode" Thaw/RuntimeV2/IdentityRegistry.swift ThawTests/IdentityRegistryTests.swift ThawIntegrationTests`
    Expectation: shadow-mode behavior and replay coverage exist.
  - `rg -n "identity-corpus|calibration" ThawTests ThawIntegrationTests docs`
    Expectation: corpus and report path are present.
- Risks:
  - Phase 2 exits without empirical sign-off
  - thresholds are tuned against intuition instead of corpus evidence
- Completion notes:
  - The redacted calibration corpus now lives under `ThawTests/Fixtures/identity-corpus/` and is replayed by `ThawIntegrationTests/IdentityCalibrationReplayTests.swift`.
  - The replay harness now compares a frozen legacy reference against `IdentityRegistry(mode: .shadow)` on the same corpus observations and asserts both metric parity and confidence parity directly.
  - `IdentityRegistryTests` lock shadow-mode persistence and reload behavior independently of the corpus replay.
  - `docs/identity-calibration-signoff.md` now records the reviewed threshold values, scenario coverage, and the engineering sign-off captured on 2026-04-09, while keeping final product cutover approval gated to later V3 phases.
  - `docs/identity-calibration-report-v1.json` now mirrors replay evidence with `legacyReferenceMetrics`, `shadowMetrics`, aggregate totals, and parity mismatch counters generated from the real replay contract.
  - Strict closure required fixing `ThawTests.xctest` bundling as well: source-boundary tests now load bundled `.swift` snapshots and fixtures without any repo-path or `#filePath` fallback, which restores full-suite validation of the Phase 2 sign-off.

### Lot `3.1` — Typed invalidations and end of string refresh reasons
- Epic: `Phase 3: Incremental discovery`
- Status: done
- Estimate: `2-3d`
- Depends on: `2.1`
- Main files to touch:
  - `Thaw/RuntimeV2/DiscoveryRuntime.swift`
  - `Thaw/MenuBar/Search/MenuBarSearchAdapter.swift`
  - `Thaw/RuntimeV2/MenuBarLayoutEditorAdapter.swift`
  - `Thaw/RuntimeV2/PanelRuntime.swift`
  - `Thaw/RuntimeV2/IceBarAdapter.swift`
  - `Thaw/Settings/Models/ProfileManager.swift`
  - new `Thaw/Runtime/Discovery/DiscoveryInvalidation.swift`
  - new `ThawTests/DiscoveryInvalidationTests.swift`
- Tasks:
  1. Define `DiscoveryInvalidation`.
  2. Replace every `refresh(reason: String)` active-path call with typed invalidations.
  3. Remove free-form refresh reasons from command routing, layout UI, panel flows, and profile apply flows.
- Tests to add or expand:
  - create `DiscoveryInvalidationTests`
  - expand `CommandRouterTests`
  - expand discovery integration coverage
- Exit grep:
  - `rg -n "refresh\\(reason:" Thaw/RuntimeV2 Thaw/MenuBar/Search Thaw/Settings/Models/ProfileManager.swift`
    Expectation: no hits in active runtime code.
  - `rg -n "\"profile-apply\"|\"search-panel-show\"|\"screen-parameters-changed\"" Thaw/RuntimeV2 Thaw/MenuBar/Search Thaw/Settings/Models/ProfileManager.swift`
    Expectation: no legacy string-coded invalidation call sites remain on the active path.
- Risks:
  - replacing strings incompletely and leaving hidden fallback paths
  - invalidation fan-out becomes broader than necessary during the swap
- Completion notes:
  - `DiscoveryInvalidation` is now the active invalidation contract for discovery refreshes, panel preparation, layout editor presentation/reset, profile apply, activation follow-up, and display/workspace-driven refreshes.
  - `DiscoverySession`, `MenuBarSearchAdapter`, `MenuBarLayoutEditorAdapter`, `PanelService`, and `ProfileManager` no longer call `refresh(reason:)` on the active path.
  - `DiscoveryInvalidationTests` now lock both the typed invalidation behavior and the absence of legacy `refresh(reason:)` usage in the active lot `3.1` source files.

### Lot `3.2` — Actor discovery service, immutable snapshots, and AX split
- Epic: `Phase 3: Incremental discovery`
- Status: done
- Estimate: `3-5d`
- Depends on: `3.1`
- Main files to touch:
  - `Thaw/RuntimeV2/DiscoveryRuntime.swift`
  - `Thaw/RuntimeV2/AXActivationResolver.swift`
  - `Thaw/RuntimeV2/DisplayRuntime.swift`
  - `Thaw/MenuBar/Search/MenuBarSearchModel.swift`
  - `Thaw/RuntimeV2/IceBarAdapter.swift`
  - `Thaw/RuntimeV2/MenuBarLayoutEditorAdapter.swift`
  - new `Thaw/Runtime/Discovery/DiscoveryService.swift`
  - new `Thaw/Runtime/Discovery/AXObservationService.swift`
  - new `ThawTests/DiscoveryServiceTests.swift`
  - new `ThawIntegrationTests/DiscoveryIntegrationTests.swift`
- Tasks:
  1. Introduce actor-based `DiscoveryService`.
  2. Split AX observation from activation execution.
  3. Publish immutable snapshots only.
  4. Rewire search, layout editor, compact bar, and panel to adapters built on snapshots.
  5. Stop using `@MainActor` as the home of discovery work.
- Tests to add or expand:
  - create `DiscoveryServiceTests`
  - create `DiscoveryIntegrationTests`
  - expand `ViewAdapterTests`
- Exit grep:
  - `rg -n "\\bDiscoveryRuntime\\b" Thaw | rg -v "RuntimeV2/DiscoveryRuntime\\.swift|Tests|docs"`
    Expectation: no feature surface depends directly on the legacy discovery runtime anymore.
  - `rg -n "AXRuntime" Thaw | rg -v "AXObservationService|AXActivationExecutor|Tests|docs"`
    Expectation: AX responsibilities are split cleanly.
- Risks:
  - snapshot publication still leaks mutable runtime state
  - AX observer loss or workspace churn causes global refresh storms
- Completion notes:
  - `DiscoveryService` is now the actor authority for runtime discovery state and depends on the `DiscoveryObserving` boundary instead of live AX-only construction, which makes service-level coverage possible without AppKit AX probing.
  - `AXObservationService` keeps per-PID AX observers, explicitly removes AX notifications during teardown, coalesces repeated invalidations into `.axStructureChanged(bundleID:processIdentifier:)`, and only falls back to global refresh when startup, permission, or setup recovery requires it.
  - Discovery refreshes now merge scoped AX and workspace invalidations back into the prior snapshot instead of recomputing every descriptor on each app-scoped change.
  - `DiscoveryServiceTests`, `DiscoveryIntegrationTests`, and `AXObservationServiceTests` cover setup, partial merge, invalidation-driven refresh, bounded recovery coalescing, and the invariant that unaffected layout assignments survive app-scoped refreshes.
  - AX observation and activation resolution are split cleanly between [`AXObservationService`](../Thaw/Runtime/Discovery/AXObservationService.swift), [`AXActivationResolver`](../Thaw/RuntimeV2/AXActivationResolver.swift), and [`AXActivationExecutor`](../Thaw/RuntimeV2/AXActivationExecutor.swift); `AppGraph` no longer wires `AXRuntime` directly.
  - `ViewAdapterTests` now assert that `IceBarAdapter`, search, layout editor, and panel-facing adapters consume typed discovery-session boundaries instead of reaching into `DiscoveryService`, `AXObservationService`, `AXRuntime`, or `AXActivationResolver`.

### Lot `4.1` — Transactional activation and typed panel interaction
- Epic: `Phase 4: Transactional activation`
- Status: done
- Estimate: `2-4d`
- Depends on: `3.2`
- Main files to touch:
  - `Thaw/RuntimeV2/ActivationService.swift`
  - `Thaw/RuntimeV2/AXActivationExecutor.swift`
  - `Thaw/RuntimeV2/PanelRuntime.swift`
  - `Thaw/MenuBar/Search/MenuBarSearchAdapter.swift`
  - `Thaw/RuntimeV2/IceBarAdapter.swift`
  - `Thaw/MenuBar/IceBar/IceBar.swift`
  - `ThawTests/ActivationServiceTests.swift`
  - new `ThawIntegrationTests/PanelActivationIntegrationTests.swift`
- Tasks:
  1. Make `ActivationService` the sole activation transaction owner.
  2. Route UI activation only through `ActivationCommand`.
  3. Enforce `prepare -> show -> interact -> dismiss` for panel presentation.
  4. Remove refresh-after-show as the normal path.
  5. Add typed outcomes and explicit follow-up invalidations.
- Tests to add or expand:
  - expand `ActivationServiceTests`
  - create `PanelActivationIntegrationTests`
- Exit grep:
  - `rg -n "discoveryRuntime\\.activate\\(" Thaw`
    Expectation: no feature surface activates through discovery anymore.
  - `rg -n "icebar-panel-show|search-panel-show|icebar-panel-prepare" Thaw`
    Expectation: panel behavior is no longer controlled by string refresh hooks.
- Risks:
  - panel state mutates from UI callbacks outside the typed contract
  - serialized activation regresses fast repeated interactions
- Completion notes:
  - `ActivationService` is the sole activation transaction owner on the active path; feature surfaces no longer activate through discovery runtime helpers.
  - Search and IceBar activation paths route UI actions through `ActivationCommand` and receive typed `PanelInteractionResult` values instead of string-driven panel hooks.
  - `PanelService` keeps the normal panel flow on the explicit `prepare -> show -> interact -> dismiss` path: presentation first refreshes `.panelPreparation`, successful interactions dismiss only when the presentation ID still matches, and recoverable failures keep the panel visible.
  - `ActivationServiceTests`, `PanelServiceTests`, and `PanelActivationIntegrationTests` now lock repeated activation coalescing, missing-descriptor behavior, typed follow-up invalidations, search-panel preparation-before-show, and dismiss-vs-keepPresented handling for both IceBar and search panel closures.

### Lot `4.2` — Strict AX retry policy and bounded confirmation window
- Epic: `Phase 4: Transactional activation`
- Status: done
- Estimate: `1-3d`
- Depends on: `4.1`
- Main files to touch:
  - `Thaw/RuntimeV2/AXActivationExecutor.swift`
  - `Thaw/RuntimeV2/ActivationService.swift`
  - `ThawTests/AXActivationExecutorTests.swift`
  - `ThawTests/ActivationServiceTests.swift`
  - `ThawIntegrationTests/PanelActivationIntegrationTests.swift`
- Tasks:
  1. Enforce the `axPress` retry policy from `PLANS.md`: one direct attempt, then at most one re-resolution/retry for `invalidUIElement` or `cannotComplete` only.
  2. Make the confirmation window for outcome observation explicit and bounded in the executor path.
  3. Keep typed outcomes and targeted follow-up invalidations unchanged at the service boundary.
  4. Lock the retry and confirmation behavior with executor-level tests before moving to the layout/profile phase.
- Tests to add or expand:
  - create `AXActivationExecutorTests`
  - expand `ActivationServiceTests`
  - expand `PanelActivationIntegrationTests`
- Exit grep:
  - `rg -n "maxActionAttempts|actionRetryDelay|attempt in 1 ... maxActionAttempts" Thaw/RuntimeV2/AXActivationExecutor.swift`
    Expectation: the generic multi-attempt AX loop is gone from the active executor path.
  - `rg -n "bounded confirmation window|confirmation window|invalidUIElement|cannotComplete" Thaw/RuntimeV2 ThawTests ThawIntegrationTests`
    Expectation: the retry and observation contract is explicit, typed, and covered by tests.
- Risks:
  - retry policy regresses into a broad hidden loop
  - confirmation timing becomes implicit or duplicated across multiple layers
  - executor tests miss the retry/failure split and let a legacy path drift back in
- Completion notes:
  - `AXActivationExecutor` now models the plan’s `axPress` contract directly: one direct pass, then at most one re-resolution/retry only for `invalidUIElement` or `cannotComplete`.
  - The outcome observation step is now an explicit `ActivationConfirmationWindow` instead of a hidden retry loop with scattered timing constants.
  - `ActivationService` and panel-facing contracts stay unchanged at the service boundary; typed outcomes and targeted follow-up invalidations remain intact.
  - `AXActivationExecutorTests` now lock retryable-vs-terminal failure handling and the bounded confirmation-window mapping to `.openedUI` vs `.openedApp`.

### Lot `5.1` — Replace `VirtualLayoutStore` with `LayoutService`
- Epic: `Phase 5: Virtual layout and profiles on the new substrate`
- Status: done
- Estimate: `4-6d`
- Depends on: `4.1`
- Main files to touch:
  - `Thaw/RuntimeV2/VirtualLayoutStore.swift`
  - `Thaw/RuntimeV2/MenuExtraModels.swift`
  - `Thaw/RuntimeV2/DiscoveryRuntime.swift`
  - `Thaw/Settings/Models/Profile.swift`
  - `Thaw/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`
  - `Thaw/RuntimeV2/MenuBarLayoutEditorAdapter.swift`
  - `Thaw/Runtime/Bootstrap/StartupMigrationRunner.swift`
  - `ThawTests/VirtualLayoutStoreTests.swift`
  - `ThawTests/AppGraphBootstrapTests.swift`
  - `ThawTests/StartupMigrationRunnerTests.swift`
  - `ThawIntegrationTests/LayoutPersistenceIntegrationTests.swift`
  - new `Thaw/Runtime/Layout/LayoutService.swift`
  - new `Thaw/Runtime/Layout/ProfileLayoutV3.swift`
  - new `ThawTests/LayoutServiceTests.swift`
- Tasks:
  1. Introduce `LayoutService`.
  2. Introduce `ProfileLayoutV3`.
  3. Migrate the active layout substrate off `VirtualLayoutStore`.
  4. Rework the layout editor to operate only on canonical IDs and virtual groups.
  5. Preserve the final semantics `Quick Access`, `Panel`, and `Archive`.
- Tests to add or expand:
  - create `LayoutServiceTests`
  - expand `LayoutPersistenceIntegrationTests`
  - retire or reduce `VirtualLayoutStoreTests` once compatibility scope is minimal
- Exit grep:
  - `rg -n "VirtualLayoutStore|ProfileLayoutV2" Thaw ThawTests | rg -v "Tests|docs|migration"`
    Expectation: no active runtime path depends on the V2 layout substrate.
  - `rg -n "Quick Access|Panel|Archive" Thaw/Settings Thaw/MenuBar Thaw/Runtime`
    Expectation: final user-facing group semantics are present.
- Risks:
  - profile/layout migration loses order, alias, or dormant items
  - active runtime continues to write V2 layout shape after the new service lands
- Completion notes:
  - `LayoutService` and `ProfileLayoutV3` are the active layout substrate.
  - `StartupMigrationRunner` is now the official bootstrap-migration authority under `Runtime/Bootstrap`, and `AppGraph` delegates startup migration execution through that boundary instead of constructing migration steps inline.
  - `AppGraphBootstrapTests` now proves the second-startup layout bookkeeping path through `AppGraph.performStartupBootstrap()`, not through a bare `MigrationCoordinator` assembled inside the test.
  - `StartupMigrationRunnerTests` lock the bootstrap migration authority itself: the first run migrates the legacy layout envelope, and the second run on the same persisted state performs no further layout migration work.
  - `PersistenceMigrationTests` now covers a full legacy profile envelope reader boundary and V3 rewrite without semantic loss.
  - `VirtualLayoutStore` is not part of the active code path; grep shows only migration/test references for legacy layout shape.

### Lot `5.2` — Introduce `ProfilesService` and demote `ProfileManager`
- Epic: `Phase 5: Virtual layout and profiles on the new substrate`
- Status: done
- Estimate: `3-5d`
- Depends on: `5.1`
- Main files to touch:
  - `Thaw/Settings/Models/ProfileManager.swift`
  - `Thaw/Settings/Models/Profile.swift`
  - `Thaw/Settings/Models/FocusFilterService.swift`
  - `Thaw/Settings/SettingsPanes/GeneralSettingsPane.swift`
  - `Thaw/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`
  - `ThawTests/ProfileManagerPersistenceTests.swift`
  - `ThawTests/ProfileManagerFocusRuntimeTests.swift`
  - new `Thaw/Runtime/Profiles/ProfilesService.swift`
  - new `ThawTests/ProfilesServiceTests.swift`
- Tasks:
  1. Move apply/import/export/update/delete/duplicate responsibilities into `ProfilesService`.
  2. Reduce `ProfileManager` to a UI-facing adapter or remove it if unnecessary.
  3. Keep `FocusFilterService` integrated only through typed profile-runtime events.
  4. Remove final user-visible legacy terminology and application-menus controls in this phase.
- Tests to add or expand:
  - create `ProfilesServiceTests`
  - expand `ProfileManagerPersistenceTests`
  - expand `ProfileManagerFocusRuntimeTests`
- Exit grep:
  - `rg -n "PersistentEnvelope<Profile>|PersistentEnvelope<\\[ProfileMetadata\\]>" Thaw/Settings/Models/ProfileManager.swift`
    Expectation: profile persistence no longer lives in `ProfileManager`.
  - `rg -n "application-menus|toggleApplicationMenus" Thaw/Settings Thaw/MenuBar`
    Expectation: no active product UI exposes application-menus controls.
- Risks:
  - profile persistence logic remains split between manager and service
  - final product copy and settings still expose legacy semantics
- Completion notes:
  - `ProfilesService` is now the runtime authority for profile persistence, runtime apply/delete/rename/duplicate/import/export operations, hotkey mappings, display auto-switch, and Focus-driven profile state transitions.
  - `ProfileManager` is reduced to a thin UI-facing facade over `ProfilesService`; source-boundary tests now lock the absence of profile persistence envelopes and Focus runtime ownership inside `ProfileManager`.
  - `HotkeySessionAdapter` and `MenuBarSessionAdapter` now depend directly on `ProfilesService`, while settings UI keeps using `ProfileManager` as the explicit presentation adapter.
  - `AppGraph` owns both `ProfilesService` and the `ProfileManager` facade, and `FocusFilterService` is wired into the profile runtime through `ProfilesService.performSetup(...)`, not through direct `ProfileManager` runtime logic.
  - `ProfilesServiceTests`, `ProfileManagerPersistenceTests`, and `ProfileManagerFocusRuntimeTests` now cover the extracted runtime boundary, persisted V3 envelopes, Focus fallback behavior, hotkey continuity, and the absence of transient Focus state in saved/imported profile files.
  - Exit greps are clean: `ProfileManager.swift` no longer contains profile persistence envelopes or Focus runtime state, runtime adapters no longer depend on `ProfileManager`, and no active settings/menu UI exposes `application-menus` controls.

### Lot `6.1` — Runtime cutover to V3-only active path
- Epic: `Phase 6: Runtime cutover`
- Status: done
- Estimate: `2-4d`
- Depends on: `5.2`
- Main files to touch:
  - `Thaw/Main/AppGraph.swift`
  - `Thaw/Main/AppState.swift`
  - `Thaw/Main/AppDelegate.swift`
  - `Thaw/RuntimeV2/CommandRouter.swift`
  - `Thaw/RuntimeV2/MenuChromeController.swift`
  - `Thaw/MenuBar/Search/MenuBarSearchModel.swift`
  - `Thaw/Settings/Models/HotkeysSettings.swift`
  - `ThawTests/CommandRouterTests.swift`
  - new `ThawIntegrationTests/CommandRoutingIntegrationTests.swift`
- Tasks:
  1. Make V3 the only active path for discovery, activation, layout, profiles, search, panel/bar, permissions, and focus.
  2. Move all URL, hotkey, and menu command handling through `CommandRouter`.
  3. Keep legacy URL hosts and hotkey payloads mapped during the compatibility window.
  4. Retire `MenuBarItemService` if it no longer has active product ownership.
- Tests to add or expand:
  - expand `CommandRouterTests`
  - create `CommandRoutingIntegrationTests`
  - expand hotkey and URL integration coverage
- Exit grep:
  - `rg -n "\\bRuntimeV2\\b" Thaw/Main Thaw/MenuBar Thaw/Settings Thaw/UI | rg -v "docs|Tests"`
    Expectation: no surviving product surface depends on V2-named runtime modules.
  - `rg -n "toggle-hidden|toggle-always-hidden|toggleApplicationMenus" Thaw`
    Expectation: only compatibility mappings and tests remain where allowed.
- Risks:
  - hidden dual-path behavior survives under adapters
  - compatibility mappings for launchers and stored hotkeys are dropped too early
- Completion notes:
  - `CommandRouter` no longer depends on `AppState`; it now routes through explicit command dependencies wired by `AppGraph`, which keeps URL, hotkey, and menu command handling inside a graph-owned boundary instead of a runtime service locator.
  - The old control-item settings route was eliminated before `7.1`; settings now route through `MenuBarSessionAdapter -> CommandRouter`, matching the status-item and search-panel command path.
  - `CommandRouterTests`, `ViewAdapterTests`, `StartupBaselineIntegrationTests`, and `AppGraphBootstrapTests` now lock the explicit-dependency router contract, the removal of the `AppDelegate` selector from the control-item menu, and the graph-owned routing of incoming settings URLs/reopen flows.
  - `AppSessionModel` no longer reaches into `SwiftUI.EnvironmentValues` or `NSApp.windows` to open or observe windows. `IceWindow`, `SettingsWindow`, and `PermissionsWindow` now install explicit window commands and bind live window visibility back through adapters, which keeps the session boundary testable and removes the `bundleProxyForCurrentProcess` crash path under `xctest`.
  - `UserNotificationManager` no longer touches `UNUserNotificationCenter.current()` during `AppState` initialization. The system notification-center adapter now resolves the center lazily on first real use, so the graph-owned bootstrap path remains headless-safe in tests and does not recreate the old `bundleProxyForCurrentProcess` failure through a default argument side effect.
  - Exit greps are clean: no active `performSetup(with appState:)` path remains in production code, no surviving product surface under `Main/MenuBar/Settings/UI` depends on `RuntimeV2` by name, and no active runtime code references `toggle-hidden`, `toggle-always-hidden`, or `toggleApplicationMenus`.
  - Validation closure is complete: targeted `6.1` suites, full `xcodebuild -scheme Thaw -configuration Debug build`, `swiftlint lint --strict`, and full `xcodebuild -scheme Thaw -configuration Debug test` all passed on April 9, 2026.

### Lot `7.1` — Physical legacy deletion
- Epic: `Phase 7: Dead code removal`
- Status: done
- Estimate: `2-3d`
- Depends on: `6.1`
- Main files to touch:
  - `Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift`
  - `Thaw/Events/HIDEventManager.swift`
  - `Shared/Bridging/Shims.swift`
  - `Thaw/MenuBar/MenuBarSection.swift`
  - `Thaw/MenuBar/MenuBarManager.swift`
  - any cursor transport helpers or synthetic move code path
  - docs and tests that still reference removed legacy paths
- Tasks:
  1. Delete the legacy runtime code listed in `PLANS.md`.
  2. Remove compatibility shells that only preserve old section semantics.
  3. Keep V2 readers only if they are still inside the compatibility window and still needed for migration.
  4. Update developer-facing docs to reflect the final architecture.
- Tests to add or expand:
  - remove obsolete tests and replace them with final-surface coverage where needed
  - rerun the full suite and acceptance matrix
- Exit grep:
  - `rg -n "MenuBarItemManager|HIDEventManager|MenuBarSection|MenuBarManager" Thaw Shared`
    Expectation: no hits.
  - `rg -n "cursor transport|synthetic drag|CGS" Thaw Shared`
    Expectation: no active runtime usage.
- Risks:
  - deleting a compatibility reader still needed for upgraded installs
  - leaving dead code in project files while assuming it is gone
- Completion notes:
  - [`MenuBarSection.swift`](/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/MenuBarSection.swift) and [`ControlItem.swift`](/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/ControlItem/ControlItem.swift) were deleted physically; the runtime no longer carries hidden spacer/control-item section logic or a compatibility shell for old section semantics.
  - [`IceBar.swift`](/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/IceBar/IceBar.swift) now presents only `VirtualGroup`; `currentSection` and `show(section:)` are gone, so the active panel path no longer maps through legacy menu-bar section names.
  - [`project.pbxproj`](/Users/maz/Documents/GitHub/Thaw/Thaw.xcodeproj/project.pbxproj) no longer contains explicit references to `MenuBarSection`, `ControlItem.swift`, `MenuBarItemService`, `MenuBarItemManager`, `HIDEventManager`, or `MenuBarManager`.
  - [`ViewAdapterTests.swift`](/Users/maz/Documents/GitHub/Thaw/ThawTests/ViewAdapterTests.swift) now guards the final `IceBar` surface directly instead of asserting boundaries on deleted legacy files.
  - Exit greps are clean for production code: no `MenuBarSection`, `ControlItem`, `show(section:)`, or `currentSection` symbols remain under `Thaw`/`Shared`, and no removed legacy targets remain in the Xcode project.
  - Validation closure is complete: `xcodebuild -scheme Thaw -configuration Debug build`, `swiftlint lint --strict`, and `xcodebuild -scheme Thaw -configuration Debug test` all passed on April 9, 2026.

### Lot `7.2` — Final acceptance gate
- Epic: `Acceptance Criteria`
- Status: partial
- Estimate: `1-2d`
- Depends on: `7.1`
- Main files to touch:
  - `PLANS.md`
  - final test artifacts and docs only if acceptance reveals a gap
- Tasks:
  1. Run the manual validation matrix from `PLANS.md`.
  2. Confirm the acceptance criteria line by line.
  3. Record any residual stabilization issues before calling the refactor complete.
- Tests to add or expand:
  - only if the acceptance matrix reveals missing automated coverage
- Exit grep:
  - `rg -n "refresh\\(reason:|toggleApplicationMenus|MenuBarItemManager|HIDEventManager|ThawFocusFilter\\.current" Thaw Shared`
    Expectation: no forbidden active-path symbols remain.
  - `rg -n "Quick Access|Panel|Archive" Thaw`
    Expectation: final terminology is consistent across UI and docs.
- Risks:
  - calling the refactor done while the manual matrix still exposes hybrid behavior
  - shipping final docs that still describe the transitional architecture
- Completion notes:
  - Final automated validation was re-run on 2026-04-09: `xcodebuild -scheme Thaw -configuration Debug build`, `swiftlint lint --strict`, and `xcodebuild -scheme Thaw -configuration Debug test` all passed.
  - [`README.md`](/Users/maz/Documents/GitHub/Thaw/README.md) was aligned with final V3 terminology and target OS expectations so the public docs no longer describe `Always-hidden`/pre-V3 semantics.
  - [`V3_ACCEPTANCE_AUDIT.md`](/Users/maz/Documents/GitHub/Thaw/docs/V3_ACCEPTANCE_AUDIT.md) now records the acceptance review line by line against [`PLANS.md`](/Users/maz/Documents/GitHub/Thaw/PLANS.md).
  - [`docs/identity-calibration-report-v1.json`](/Users/maz/Documents/GitHub/Thaw/docs/identity-calibration-report-v1.json) now exposes `acceptanceSummary`, and the replay stabilization slice is at `0` churn with `0` false auto-bind on the checked-in corpus while keeping deliberate probe scenarios visible separately.
  - [`docs/runtime-performance-acceptance-report-v1.json`](/Users/maz/Documents/GitHub/Thaw/docs/runtime-performance-acceptance-report-v1.json) was exported from the passing `RuntimePerformanceAcceptanceTests` attachment and proves the three service-level `p95` thresholds on the local macOS host.
  - [`docs/V3_MANUAL_VALIDATION_2026-04-09.md`](/Users/maz/Documents/GitHub/Thaw/docs/V3_MANUAL_VALIDATION_2026-04-09.md) now records the live-machine matrix work that was actually executed on 2026-04-09, including the host state, the external-launcher URL exercise, and the concrete host blockers that still prevent closure.
  - The coarse forbidden-symbol grep still surfaces `ThawFocusFilter.current` inside [`FocusFilterService.swift`](/Users/maz/Documents/GitHub/Thaw/Thaw/Settings/Models/FocusFilterService.swift), but that call remains confined to the explicit resync path reviewed as plan-compliant; it is not part of the default bootstrap path.
  - The local machine also cannot yet finish the remaining matrix cleanly: Thaw launches into the permissions/settings flow, no external display is attached, `MacVirt` is not installed, and no upgraded-install scenario was prepared.
  - The live matrix exposed a compatibility-window regression on the legacy external hosts, that regression was fixed in `CommandRouter`, and the live external-launcher check was rerun successfully afterward.
  - `7.2` is therefore still not closable for one reason: the remaining live validation matrix still has to be executed on a machine that matches the plan.

## Recommended Commit Strategy
- One lot per branch when possible.
- Do not mix bootstrap, discovery, layout, and profile substrate rewrites in the same changeset.
- For high-risk lots, split into:
  - substrate introduction
  - consumer rewiring
  - legacy removal

## Done Criteria for the Full Refactor
- All lots above are closed.
- `PLANS.md` acceptance criteria are satisfied.
- The repo has no active legacy runtime path left.
