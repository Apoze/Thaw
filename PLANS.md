# Thaw V3 Refactor Plan

## Summary
- Product contract is locked to **launcher / organizer autonome**.
- Thaw will no longer attempt to physically hide, move, or reorder third-party menu extras in the native macOS menu bar.
- The implementation target is a **single public-API-first runtime** with canonical identity, incremental discovery, transactional activation, virtual layout/profiles, and full legacy removal.
- The current codebase is still hybrid. This plan is the full replacement target for the remaining architecture work.
- Execution note for this local clone: because Thaw is not yet in production use, the final cutover target is **zero retained legacy**. Intermediate compatibility-window steps described below are implementation history, not a constraint on the final repo state.
- The operational lot-by-lot execution backlog lives in [`docs/V3_EXECUTION_BACKLOG.md`](docs/V3_EXECUTION_BACKLOG.md). If there is any conflict, this file remains the source of truth.

## Product Contract

### What Thaw does
- Discover third-party menu extras.
- Present them inside Thaw's own UI.
- Activate them using public APIs when supported.
- Persist grouping, ordering, aliases, profiles, and per-display preferences.

### What Thaw does not do
- Physically hide a third-party menu extra from the native macOS menu bar.
- Physically reorder or move third-party menu extras in the native macOS menu bar.
- Warp, hide, or move the cursor.
- Use private CGS APIs, synthetic drag pipelines, or off-screen spacer/control-item geometry as a core runtime primitive.

### User-facing semantics
- `Quick Access`: shortcuts visible in Thaw's compact bar.
- `Panel`: items shown in Thaw's expanded panel.
- `Archive`: items excluded from the main panel but still available in search and profiles.

### First-launch defaults
- With no saved user data:
  - `Quick Access` is empty.
  - All discovered extras go to `Panel`.
  - `Archive` is empty.
- With saved user data:
  - Restore exactly what was saved.
  - Do not auto-populate `Quick Access`.

## Architecture Target

### Core principles
- One active runtime only.
- Public API first.
- Event-driven before polling.
- Typed invalidations instead of string reasons.
- Canonical identity before layout persistence.
- Layout and profiles are purely virtual.
- Discovery never mutates layout.
- Activation never mutates layout.
- Migration is versioned, atomic, and idempotent.
- External interfaces remain backward-compatible during a bounded deprecation window.

### Runtime modules
- `AppGraph`
  - Single dependency container.
  - Owns service construction and wiring.
- `AppSessionModel`
  - Minimal `@MainActor` observable UI/session state.
  - No discovery or activation logic.
- `ViewModelAdapters`
  - `@MainActor` adapters that transform immutable runtime snapshots into view-ready data.
  - No side effects and no direct AX/workspace access.
- `PermissionService`
  - Single authority for Accessibility permission state and prompting.
- `WorkspaceEventSource`
  - Adapts `NSWorkspace` and display notifications into typed invalidations.
- `DisplayService`
  - `@MainActor` service dedicated to active display, display UUID mapping, panel anchoring inputs, and per-display context.
- `DiscoveryService`
  - Actor.
  - Produces immutable snapshots from AX/workspace/window observations.
- `IdentityRegistry`
  - Actor.
  - Only source of truth for canonical item identity.
- `ActivationService`
  - Actor.
  - Serializes item activation transactions.
- `LayoutService`
  - Actor.
  - Persists groups, order, aliases, and migrations.
- `ProfilesService`
  - Actor.
  - Applies virtual layouts and per-display/profile configuration.
- `FocusFilterService`
  - Wraps App Intents / Focus Filters.
  - Converts "no current action" into a normal `notConfigured` state.
- `PanelService`
  - `@MainActor`.
  - Owns panel presentation state and panel session lifecycle.
- `IconService`
  - Resolves and caches icons independently from discovery and layout.
- `CommandRouter`
  - `@MainActor`.
  - Single authority for `thaw://` URLs, menu actions, and hotkey-dispatched commands.
- `MenuChromeController`
  - `@MainActor`.
  - Single AppKit boundary owner for:
    - Thaw status item
    - IceBar panel
    - Search panel
    - appearance/editor panels
    - menu bar menus and contextual menus
- `MigrationCoordinator`
  - Single authority for schema upgrades, backups, idempotent migration execution, and migration bookkeeping.

### Active-path constraints
- No production calls to private `CGS` APIs.
- No production cursor transport or synthetic drag/click flow.
- No legacy control-item geometry or hidden spacer runtime.
- No refresh causes encoded as free-form strings.
- No dual permission authority.
- No dual runtime ownership of the same feature.
- No UI object ownership split across multiple runtime objects.
- No product feature survives if it fundamentally depends on native menu-bar manipulation that V3 forbids.
- No migration logic outside `MigrationCoordinator`.
- No SwiftUI view talks directly to runtime services other than view-model adapters and command closures.

## Core Types

### Identity
- `MenuExtraCanonicalID`
  - Stable UUID assigned by Thaw.
  - The only persisted key for layout and profiles.
- `MenuExtraFingerprint`
  - `bundleID`
  - `role`
  - `normalizedTitle`
  - `axIdentifier?`
  - `axPathSignature?`
  - `slotSignature?`
  - `displayUUID?`
- `IdentityMatchConfidence`
  - `exact`
  - `high`
  - `provisional`
  - `ambiguous`

### Runtime state
- `MenuExtraCapability`
  - `axPress`
  - `openApp`
  - `unsupported`
- `ThawGroup`
  - `shortcut`
  - `panel`
  - `archive`
- `MenuExtraSnapshot`
  - `canonicalID`
  - `fingerprint`
  - owning app metadata
  - display metadata
  - capability
  - confidence
  - current group
  - alias
  - icon token
- `DiscoverySnapshot`
  - immutable list of `MenuExtraSnapshot`
  - generation time
  - typed source/invalidation cause

### Discovery and activation
- `DiscoveryInvalidation`
  - `appLaunched(bundleID)`
  - `appTerminated(bundleID)`
  - `appActivated(bundleID)`
  - `axStructureChanged(bundleID, pid)`
  - `permissionChanged`
  - `panelRequested(displayUUID)`
  - `activationFollowUp(canonicalID)`
  - `displayConfigurationChanged`
- `ActivationCommand`
  - `activate(canonicalID, surface, intent)`
- `ActivationOutcome`
  - `openedUI`
  - `openedApp`
  - `unsupported`
  - `permissionMissing`
  - `timeout`
  - `failedRecoverable`
  - `failedTerminal`

### Layout and profiles
- `LayoutStateV3`
  - `groupByCanonicalID`
  - `orderedCanonicalIDsByGroup`
  - `aliasesByCanonicalID`
  - `dormantIDs`
- `ProfileLayoutV3`
  - default layout
  - per-display overrides
  - appearance overrides
  - hotkey bindings
  - optional focus-filter binding
- `PersistentEnvelope<T>`
  - `schemaVersion`
  - `createdAt`
  - `updatedAt`
  - `payload`
- `ExternalCommand`
  - typed representation of routed URLs, menu commands, and hotkey commands
- `DeprecationPolicy`
  - current name
  - legacy aliases
  - remove-after version

## Design Rules

### Canonical identity
- Discovery produces raw candidates only.
- `IdentityRegistry` is the only place allowed to attach or reuse canonical IDs.
- Matching order:
  1. same `bundleID + axIdentifier + role`
  2. same `bundleID + axPathSignature + role`
  3. same `bundleID + role + normalizedTitle + slotSignature` with strict uniqueness
  4. otherwise `ambiguous`
- `exact` and `high` may reuse an existing canonical ID automatically.
- `provisional` may be shown but must not overwrite an existing persisted identity.
- `ambiguous` must remain isolated and must never steal another item's identity.
- Persist dormant IDs while they are referenced by layout or profiles.

### Empirical identity calibration
- The identity algorithm must be tuned in an explicit calibration phase before final cutover.
- Build a local corpus of redacted discovery snapshots covering at minimum:
  - single-extra apps
  - multi-extra apps from the same bundle
  - extras with identical titles
  - extras without AX identifiers
  - extras that disappear during activation
  - display changes
  - app relaunch with new PID
- The minimum validation corpus includes:
  - Tabby
  - Bitwarden
  - OrbStack
  - MacVirt
  - AltTab
  - Joplin
  - Control Center items
  - Spotlight
- Corpus capture must be:
  - local only
  - opt-in diagnostic mode only
  - redacted for user text beyond normalized titles needed for matching
  - stored outside repo and never uploaded automatically
- Matching inputs must expose feature vectors explicitly:
  - same bundle
  - same role
  - same AX identifier
  - same normalized title
  - same display UUID
  - same relative slot band
  - frame-distance score
  - prior canonical match
- Convert confidence labels into deterministic score ranges:
  - `exact`: AX identifier or AX path signature exact match with no competing candidate
  - `high`: score at or above the auto-bind threshold with a unique best match and margin above runner-up
  - `provisional`: score above the candidate threshold but below the auto-bind threshold, or margin too small
  - `ambiguous`: no candidate above threshold or multiple near-equal candidates
- Required thresholds to define in implementation as named constants, not literals:
  - auto-bind minimum score
  - provisional minimum score
  - minimum winner margin
  - frame-distance tolerance by display scale
  - slot-band tolerance
- The thresholds must be calibrated in shadow mode first:
  - old resolver and new registry run side by side
  - only the old active identity drives UI
  - the new registry records predicted canonical matches and churn metrics
- Shadow-mode exit criteria:
  - zero identity steals across the validation corpus
  - no canonical reassignment for stable single-extra apps
  - no profile/layout corruption caused by identity churn
  - churn rate below `0.5%` across repeated open/close/relaunch scenarios
- Promotion rules:
  - a `provisional` match may promote to `high` only after repeated consistent observations across at least 3 discovery generations
  - an `exact` or `high` match may downgrade only after repeated contradiction, never on a single refresh
- The plan must treat calibration data and scoring reports as first-class deliverables before enabling V3 identity cutover.

### Incremental discovery
- `DiscoveryService` is actor-based and not UI-driven.
- Prefer app-scoped refreshes.
- Only do a full scan:
  - at cold start
  - after permission grant
  - after observer loss or invalidation that cannot be narrowed
- `CGWindowListCopyWindowInfo` is observation-only and never identity authority.
- No permanent recovery polling loop.
- `NSWorkspace` notifications must come from `NSWorkspace.shared.notificationCenter`.
- `DisplayService` is the only place allowed to map points/windows to display UUIDs and active-screen context.

### Transactional activation
- One activation transaction per item at a time.
- Coalesce repeated clicks on the same item while activation is in flight.
- Activation flow:
  1. load latest snapshot for canonical ID
  2. resolve fresh AX target if needed
  3. execute capability action
  4. observe outcome during a bounded confirmation window
  5. publish typed outcome
  6. emit at most one targeted follow-up invalidation
- `axPress` retry policy:
  - first direct attempt
  - on `invalidUIElement` or `cannotComplete`, re-resolve once and retry once
  - otherwise fail terminally
- Never mutate layout or groups as a side effect of activation.
- Never "open the app anyway" after an AX failure unless capability is explicitly `openApp`.

### Layout and profiles
- Layout persists only canonical IDs.
- Clicking an item must never move it between groups.
- Group changes only happen from:
  - explicit user action
  - profile application
  - explicit reset
- Profiles store:
  - group assignments
  - ordering
  - aliases
  - appearance overrides
  - per-display overrides
  - optional focus-filter bindings
- Group semantics must not depend on the presence or absence of native control items.

### Persistence and migration
- All persisted runtime state lives under `~/Library/Application Support/Thaw/`.
- Persist V3 runtime state in separate files:
  - `runtime/identity-registry-v3.json`
  - `runtime/layout-v3.json`
  - `profiles/manifest-v3.json`
  - `profiles/<uuid>.json`
- Every persisted document uses `PersistentEnvelope<T>` with an explicit `schemaVersion`.
- All writes must be atomic using Foundation atomic write semantics.
- `MigrationCoordinator` is the only object allowed to:
  - inspect old schema versions
  - create `.bak` files
  - write migration markers
  - decide whether migration should run
- Migrations are one-way and idempotent:
  - read V2 and V3
  - if V3 exists, it wins
  - if only V2 exists, migrate once and write V3
  - never rewrite V2 in place
- Keep V2 read compatibility for one major release only.
- During migration, create one best-effort `.bak` sibling before first V3 write for:
  - layout
  - profiles manifest
  - each migrated profile file
- Layout/profile migration must preserve:
  - group assignments
  - ordering
  - aliases/custom names
  - display associations
  - hotkeys
  - appearance overrides
- If identity matching is only `provisional` during migration, preserve the assignment as dormant instead of force-rebinding.
- Calibration logs and scoring reports are diagnostics only and must not be persisted in the user’s functional state files.
- Migration bookkeeping must be stored separately from functional state, in a dedicated migration metadata file.

### External interface compatibility
- Preserve legacy `HotkeyAction.rawValue` strings for one major release.
- Preserve existing `thaw://` URL hosts for one major release.
- Route legacy commands through `CommandRouter`, not through legacy managers.
- Required command remapping:
  - `thaw://toggle-hidden` -> toggle `panel`
  - `thaw://toggle-always-hidden` -> toggle `archive`
  - `thaw://toggle-thawbar` -> toggle Thaw compact bar/panel according to current display config
  - `thaw://search` -> open search
  - `thaw://open-settings` -> open settings
- Feature disposition:
  - `toggleApplicationMenus` is deprecated immediately
  - it remains routable during the compatibility window
  - its routed behavior becomes a no-op with a debug deprecation log
  - it is removed entirely when the compatibility window ends
- Settings/UI labels must use final product terminology immediately, even while legacy command names remain accepted internally.
- Emit a debug-only deprecation log when a legacy URL host or legacy hotkey semantic path is exercised.

### Permissions and Focus Filters
- `PermissionService` is the only runtime authority for permission state.
- The permission UI remains re-clickable until the permission is actually granted.
- The app bootstrap depends on `PermissionService`, not legacy permission state.
- `FocusFilterService` treats App Intents "no current action available" as a normal `notConfigured` state, logged only at debug level.
- Do not call `ThawFocusFilter.current` during bootstrap unless `FocusFilterService` has prior local evidence that a Focus configuration has existed for this install.

#### Focus Filter correction plan
- Problem statement:
  - The current bootstrap path must not call `ThawFocusFilter.current` unconditionally.
  - On systems with no configured Focus action, App Intents returns `DNDErrorDomain Code=1007` ("No current action is available. Supply the caller with the default.").
  - This is not a runtime failure; it is the normal `notConfigured` state and must not surface as an app error.
  - Important: even if the app catches that error and downgrades it to debug, the underlying Apple framework still emits error-level system log noise when `current` is queried unnecessarily.
- Target runtime contract:
  - `FocusFilterService` is the single authority for Focus Filter state.
  - `ProfileManager` and UI code do not call App Intents directly.
  - Focus state is modeled explicitly as:
    - `inactive`
    - `active(profileID)`
    - `notConfigured`
  - `notConfigured` is an internal normal state, not a user-visible error.
- Challenged assumptions:
  - Do not assume `UserDefaults` mirror state alone is always sufficient forever.
  - Do not assume the system will always redeliver a Focus activation after app launch.
  - Do not assume querying `ThawFocusFilter.current` is harmless if the result is immediately caught.
  - Do not add an app-owned persisted "Focus binding" field to the profile model unless the product also introduces in-app Focus configuration UI.
  - System Settings owns Focus-to-profile configuration; Thaw owns only its local runtime mirror and application behavior.
- Bootstrap rules:
  - At startup, first inspect local persisted state only.
  - Read `FocusFilterRequestedProfileID` from local defaults.
  - If a valid profile ID is present, treat the Focus Filter as active and apply that profile.
  - If no local requested profile exists, do not query `ThawFocusFilter.current`; fall back directly to the display-based profile path.
  - If the requested profile ID points to a deleted or unreadable profile, clear the local mirror and fall back to the display-based profile path.
  - Only allow a `current` query in explicit resync paths, never as the default startup path.
  - A resync path is allowed only when there is prior local evidence that a Focus configuration has existed for this install.
  - Prior local evidence must come from `FocusFilterService` state, not from a new profile schema field.
- Local mirror rules:
  - `FocusFilterRequestedProfileID` is ephemeral runtime state, not profile metadata.
  - Do not include Focus activation state in profile export/import payloads.
  - Do not include Focus activation state in profile save/update/duplicate flows.
  - Do not migrate Focus activation state into profile files or manifest metadata.
  - If a future App Intents extension is introduced, move the mirror store out of `UserDefaults.standard` into an App Group-backed store before shipping that extension.
- Event flow:
  - `ThawFocusFilter.perform()` remains the write point for local mirror state.
  - Activation writes `FocusFilterRequestedProfileID` and emits `com.stonerl.Thaw.focusFilterActivated`.
  - Deactivation clears `FocusFilterRequestedProfileID` and emits `com.stonerl.Thaw.focusFilterDeactivated`.
  - `FocusFilterService` consumes those notifications and publishes typed state transitions to the profile runtime.
  - `FocusFilterService` is responsible for deduping repeated activation/deactivation events so profile application does not loop or thrash.
- Error handling:
  - Map `DNDErrorDomain Code=1007` to `notConfigured`.
  - Log that state only at debug level.
  - Do not emit error-level logs, alerts, or diagnostics for `notConfigured`.
  - Any other App Intents failure may be logged as warning/error depending on whether it blocks profile application.
- Resync policy:
  - The steady-state product path must not depend on `ThawFocusFilter.current`.
  - Resync exists only as a recovery path for local mirror drift.
  - A valid recovery trigger is: local service state says a Focus configuration has existed before, but startup has neither an active local requested profile nor a deactivation event.
  - Resync must run after profile manifest load and runtime-context readiness, not during the earliest bootstrap phase.
  - Resync must be asynchronous and must never block first paint, panel presentation, or discovery startup.
  - If resync returns `notConfigured`, update local service state so the app does not probe again on every launch.
- Required refactor:
  - Move bootstrap Focus logic out of `ProfileManager`.
  - Introduce `FocusFilterService`.
  - Make `ProfileManager` depend on typed Focus state/events instead of App Intents calls.
  - Keep `FocusFilterIntent` responsible only for intent/entity definition and local mirror writes.
- Execution order:
  - Step 1: Define typed `FocusFilterState` and `FocusFilterService`.
  - Step 2: Move notification subscription and startup resolution out of `ProfileManager`.
  - Step 3: Make `ProfileManager` consume typed state transitions.
  - Step 4: Remove direct `ThawFocusFilter.current` usage from bootstrap.
  - Step 5: Add explicit recovery/resync logic guarded by prior local evidence.
  - Step 6: Add focused tests before removing the old path.
- Non-regression invariants:
  - Display auto-switch never overrides an active Focus-owned profile.
  - Focus deactivation restores the display-associated profile, matching current product copy.
  - Manual profile apply and profile hotkeys continue to work while Focus is active.
  - If the user manually applies a different profile while Focus is active, Focus still owns the higher-priority mode and deactivation still restores the display profile.
  - Applying, renaming, duplicating, exporting, importing, or deleting profiles does not serialize transient Focus runtime state into profile data.
  - Deleting the currently requested Focus profile clears the mirror and leaves the app in a valid fallback state.
  - Search, Quick Access, Panel, Archive, discovery, and activation flows remain independent from Focus bootstrap.
- Boundaries:
  - `FocusFilterIntent` defines parameters/entities and writes mirror state.
  - `FocusFilterService` resolves runtime state and publishes typed events.
  - `ProfileManager` applies/reverts profiles.
  - `CommandRouter`, `DiscoveryRuntime`, and `ActivationService` must not gain new Focus-specific bootstrap logic.
- Validation:
  - Launch with no configured Focus Filter produces no system-noise-triggering app query path.
  - Launch with no `FocusFilterRequestedProfileID` falls back cleanly to display-based profile resolution.
  - Launch with a valid `FocusFilterRequestedProfileID` reapplies the requested profile without App Intents bootstrap probing.
  - Focus activation applies the requested profile.
  - Focus deactivation clears Focus-owned state and restores the display profile.
  - Diagnostic logs contain no error-level entry for the normal unconfigured Focus case.
  - Manual profile hotkeys still apply profiles correctly.
  - Display auto-switch still applies the correct profile when Focus is inactive.
  - Deleting an active Focus-requested profile clears the request key and prevents stale reapply attempts.
  - Repeated startup launches with no configured Focus Filter do not emit repeated `DNDErrorDomain 1007` system entries from Thaw.

### AppKit ownership boundary
- `MenuChromeController` is the only object allowed to own `NSStatusItem`, `NSPanel`, `NSMenu`, and `NSWindow`-adjacent chrome objects.
- `PanelService` decides *when* and *what* to show; `MenuChromeController` owns *how* AppKit objects are created and retained.
- `CommandRouter` translates external inputs into typed commands and forwards them to runtime services.
- `AppDelegate` remains thin:
  - URL registration
  - process lifecycle
  - handoff into `AppGraph`
- `MenuBarManager` does not survive the final architecture. Its remaining responsibilities split into:
  - `MenuChromeController`
  - `PanelService`
  - `CommandRouter`
  - `DisplayService`
  - layout/profile specific services

### SwiftUI/view architecture boundary
- SwiftUI views consume:
  - immutable snapshot-derived view state
  - explicit bindings for local UI state
  - command closures or view-model adapter methods
- SwiftUI views must not:
  - call AX APIs
  - read `NSWorkspace` directly
  - trigger discovery refreshes directly
  - mutate persistence directly
- Search, layout editor, and Thaw compact bar must each have a dedicated adapter model with:
  - stable identity for rows/items
  - no hidden async work in `body`
  - no ad hoc service lookups through `EnvironmentObject` for low-level runtime services
- All service-to-view updates cross a single `@MainActor` publication boundary from snapshot to adapter.

## Phased Implementation

### Phase 0: Foundations and observability
- Create a unit-test target and an integration-test target.
- Add a migration fixture bundle used only by tests.
- Introduce typed logging categories:
  - startup
  - permission
  - discovery
  - identity
  - activation
  - layout
  - profiles
  - focus
  - panel
- Introduce runtime metrics:
  - discovery duration
  - activation duration
  - identity churn count
  - invalidation count by cause
  - layout mutation count
  - confidence promotion/demotion count
  - ambiguous candidate count
- Freeze legacy code to build-safety only.
- Freeze external behavior contracts so migration can be tested against a known baseline:
  - existing hotkeys
  - existing `thaw://` URLs
  - existing profile files on disk
- Define and document the calibration corpus and the redaction policy before any identity rewrite begins.

### Phase 1: App graph and single bootstrap authority
- Add `AppGraph`.
- Reduce `AppState` to a session/UI model and thin container if still needed temporarily.
- Replace bootstrap ownership with:
  - `PermissionService`
  - `WorkspaceEventSource`
  - `DisplayService`
  - `MigrationCoordinator`
  - `DiscoveryService`
  - `IdentityRegistry`
  - `ActivationService`
  - `LayoutService`
  - `ProfilesService`
  - `FocusFilterService`
  - `PanelService`
- Introduce `CommandRouter`.
- Introduce `MenuChromeController`.
- Introduce view-model adapters for:
  - Thaw compact bar
  - panel content
  - search
  - layout editor
- Remove startup gating from legacy permission state.
- Move all boot-time migration work under `MigrationCoordinator`.
- Make this phase a blocker for all later feature work. No further runtime refactor is allowed until:
  - legacy permission gating is dead
  - `AppDelegate` no longer routes commands directly to legacy managers
  - runtime ownership of panels/status item is explicit
  - display ownership is explicit
  - `toggleApplicationMenus` no longer has product ownership, only compatibility ownership
  - no boot migration logic remains outside `MigrationCoordinator`

### Phase 2: Canonical identity registry
- Implement `IdentityRegistry` persistence and versioned schema.
- Add confidence-based matching.
- Add migration from V2 identity storage to canonical IDs.
- Move all layout persistence to canonical IDs only.
- Remove transfer/rekey behavior from the layout layer.
- Introduce dormant-assignment handling explicitly in the persistence schema.
- Add migration readers for existing V2 layout/profile payloads.
- Implement shadow mode for the new registry.
- Add scoring reports and identity churn diagnostics.
- Do not allow Phase 2 exit until calibration exit criteria are met.

### Phase 3: Incremental discovery
- Implement actor-based `DiscoveryService`.
- Model invalidations as `DiscoveryInvalidation`, not strings.
- Add AX observers per owning app when available.
- Add app-scoped refresh scheduling.
- Publish immutable snapshots only.
- Rewire search, layout UI, and Thaw bar/panel to consume snapshots.
- Split AX observation from AX action execution:
  - discovery-facing observer layer
  - activation-facing action layer
- Remove `@MainActor` as the default home of discovery work. Only UI publication stays on the main actor.
- Discovery must depend on `DisplayService` instead of ad hoc display helpers or fresh display runtime instances.
- Rewire views so no SwiftUI surface reads low-level runtime services directly.

### Phase 4: Transactional activation
- Implement `ActivationService`.
- Serialize activations.
- Replace direct AX activation paths in UI with `ActivationCommand`.
- Introduce explicit confirmation windows and typed outcomes.
- Ensure panel presentation is `prepare -> show -> interact -> dismiss`.
- Remove refresh-after-show as the normal rendering path.
- Require `PanelService` and `ActivationService` to share a typed interaction contract so panel state cannot mutate from ad hoc UI callbacks.
- Activation follow-up invalidations must be app-scoped or item-scoped, never global by default.

### Phase 5: Virtual layout and profiles on the new substrate
- Replace V2 group semantics with final user-facing semantics:
  - `Quick Access`
  - `Panel`
  - `Archive`
- Implement `LayoutService`.
- Implement `ProfileLayoutV3`.
- Move profile application onto the new layout substrate.
- Move focus-filter handling into `FocusFilterService`.
- Rework the layout editor to operate only on canonical IDs and virtual groups.
- Add explicit migration completion criteria:
  - V2 profile file decodes successfully
  - V3 profile file re-encodes without loss
  - second startup performs no further migration work
- Rework public text, menu labels, and settings copy to final terminology in this phase.
- Add explicit UI/product removal of application-menus controls in this phase.

### Phase 6: Runtime cutover
- Make V3 the only active path for:
  - discovery
  - activation
  - layout
  - profiles
  - search
  - Thaw bar/panel presentation
  - permissions
  - focus filters
- Remove legacy managers from startup and active use.
- If no longer needed, retire `MenuBarItemService`.
- Move all URL/hotkey/menu command handling to `CommandRouter`.
- Keep legacy URL hosts and legacy hotkey raw values mapped and tested, but remove legacy semantic names from user-visible UI.
- Keep identity calibration metrics enabled for one stabilization release after cutover.

### Phase 7: Dead code removal
- Delete legacy runtime code physically:
  - `MenuBarItemManager` path
  - `HIDEventManager` path
  - private CGS shims
  - cursor transport helpers
  - hidden spacer/control-item physical section logic
  - synthetic drag/click logic
  - compatibility shells that only map old section semantics
- delete application-menus implementation paths and settings that no longer fit the product contract
- Run a final architecture review to ensure no dead path remains.
- Update developer docs and architecture docs.
- Remove V2 migration readers only after the one-release compatibility window ends.
- Remove identity shadow-mode instrumentation once stabilization criteria are met.

## File and Subsystem Migration Guidance

### Current code that should become the new backbone
- `/Users/maz/Documents/GitHub/Thaw/Thaw/Main/AppState.swift`
  - reduce to session/UI state and remove service orchestration over time
- `/Users/maz/Documents/GitHub/Thaw/Thaw/Main/AppDelegate.swift`
  - rewire startup to a single permission/bootstrap authority
- `/Users/maz/Documents/GitHub/Thaw/Thaw/Utilities/Migration.swift`
  - replace with `MigrationCoordinator` and fixture-driven migration tests
- `/Users/maz/Documents/GitHub/Thaw/Thaw/RuntimeV2/StartupCoordinator.swift`
  - either replace with a final coordinator or fold into `AppGraph`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/RuntimeV2/DiscoveryRuntime.swift`
  - replace with `DiscoveryService`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/RuntimeV2/AXRuntime.swift`
  - split into discovery-facing AX observation and activation-facing AX execution
- `/Users/maz/Documents/GitHub/Thaw/Thaw/RuntimeV2/VirtualLayoutStore.swift`
  - replace with `LayoutService`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/RuntimeV2/PanelRuntime.swift`
  - keep as the basis for final `PanelService`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/RuntimeV2/DisplayRuntime.swift`
  - evolve into final `DisplayService`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/Search/MenuBarSearchPanel.swift`
  - fold ownership into `MenuChromeController`; keep search content/view logic separate from panel ownership
- `/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/IceBar/IceBar.swift`
  - keep presentation/content pieces only; move panel lifetime ownership to `MenuChromeController`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/Search/MenuBarSearchModel.swift`
  - replace direct runtime coupling with a dedicated adapter model
- `/Users/maz/Documents/GitHub/Thaw/Thaw/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`
  - drive from a layout adapter built on immutable snapshots and command closures

### Current code that should be treated as legacy removal targets
- `/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/Events/HIDEventManager.swift`
- `/Users/maz/Documents/GitHub/Thaw/Shared/Bridging/Shims.swift`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/MenuBarSection.swift`
- `/Users/maz/Documents/GitHub/Thaw/Thaw/MenuBar/MenuBarManager.swift`
- any cursor transport helpers or synthetic-move code path
- any direct command routing from `AppDelegate` to legacy hotkey or section semantics
- application-menus visibility logic and associated settings/hotkey plumbing
- any boot-time migration path that bypasses `MigrationCoordinator`

## Testing Plan

### Unit tests
- `IdentityRegistryTests`
  - single extra per app
  - multiple extras from the same bundle
  - identical titles with different roles
  - relaunch with new PID
  - disappearance and reappearance during activation
  - ambiguous candidates remain isolated
  - confidence promotion after repeated stable observations
  - confidence downgrade only after repeated contradiction
  - no auto-bind when winner margin is below threshold
- `LayoutServiceTests`
  - first launch defaults
  - exact restoration
  - dormant item retention
  - clicking never changes group
  - migration from V2 layout state
- `ProfilesServiceTests`
  - apply profile
  - per-display override
  - archive/panel/shortcut invariants
- `FocusFilterServiceTests`
  - no current filter returns `notConfigured`
  - active filter binding
  - deactivation clears correctly
- `CommandRouterTests`
  - legacy URL host maps to final command
  - legacy hotkey semantic action maps to final command
  - user-visible labels never expose deprecated semantics
  - deprecated `toggleApplicationMenus` routes to explicit no-op behavior during the compatibility window
- `ViewAdapterTests`
  - snapshot transforms produce stable item ordering
  - no hidden service calls are needed to render the adapter state
  - command closures route through typed commands only
- `PersistenceMigrationTests`
  - V2-only state migrates to V3 once
  - V3 wins when both V2 and V3 exist
  - migration is idempotent
  - `.bak` is created only on first migration
  - atomic write failure does not corrupt existing V2/V3 state
  - dormant assignment survives unresolved provisional matching
  - migration bookkeeping prevents duplicate work on second startup

### Calibration tests
- Replay the redacted corpus through:
  - the current resolver
  - the new registry in shadow mode
- Produce comparison reports for:
  - identity churn
  - canonical reassignments
  - ambiguous items
  - provisional promotions
  - false auto-binds
- Require explicit threshold sign-off before the V3 identity registry becomes active.

### Integration tests
- Fake AX tree plus fake workspace events.
- Incremental discovery per app.
- AX activation success.
- Stale element then one re-resolution retry.
- Unsupported item.
- App relaunch with multiple extras.
- Permission lost then regained.
- Panel open on stable prepared snapshot.
- Layout persistence across app restart.
- Legacy `thaw://` URL invocation still performs the correct V3 action.
- Existing hotkey payloads stored on disk still resolve to the correct V3 action.
- Deprecated `toggleApplicationMenus` remains non-breaking during the compatibility window.
- Display changes do not reassign canonical IDs for stable items.

### UI tests
- First launch with no saved data:
  - `Quick Access` empty
  - `Panel` populated
- Drag-and-drop in layout editor.
- Click item in `Quick Access`.
- Click item in `Panel`.
- Search and activation.
- Profile creation and application.
- Per-display switch.
- Permission UI stays re-clickable until granted.
- Focus filter absent without user-facing error.
- Existing upgraded install:
  - old data loads
  - groups are preserved
  - no duplicate migration prompt or reset
- Settings and menus use final terminology only.
- Application-menus controls are absent from final V3 UI.
- Search, layout, and compact bar remain stable while runtime refreshes happen in the background.

### Manual validation matrix
- MacBook with notch.
- External display attached.
- Primary display change.
- App relaunch for:
  - Tabby
  - Bitwarden
  - OrbStack
  - MacVirt
  - AltTab
  - Joplin
- Rapid open/close of the Thaw panel.
- Repeated clicks on the same menu extra.
- Open item and reopen Thaw immediately afterward.
- Existing user install upgraded in place from current local architecture.
- Legacy `thaw://toggle-hidden` and `thaw://toggle-always-hidden` exercised from an external launcher.
- Repeated open/close/relaunch loops for the calibration corpus apps to confirm identity stability.

## Acceptance Criteria
- No production use of private CGS APIs.
- No cursor warp/hide/show behavior.
- No synthetic drag/click transport for third-party extras.
- No duplicated runtime paths for the same feature.
- No dual permission authority.
- No free-form string refresh reasons in the active runtime.
- No user-visible legacy terminology once V3 UI is shipped.
- Legacy URLs and hotkeys continue to work during the compatibility window.
- Deprecated `toggleApplicationMenus` cannot change runtime behavior in V3.
- No migration path runs outside `MigrationCoordinator`.
- No low-level runtime service is injected directly into SwiftUI view trees.
- No group changes as a side effect of activation.
- No late insertion into the panel after it is shown during normal operation.
- No permanent global recovery polling.
- No user-visible error when no Focus Filter is configured.
- Identity registry auto-bind has zero known identity steals on the calibration corpus.
- Identity churn stays below `0.5%` across replay and manual stabilization scenarios.
- Stable single-extra apps never change canonical ID across relaunch tests.
- `p95` warm panel open under `120ms`.
- `p95` incremental discovery under `100ms`.
- `p95` interactive activation under `300ms`.
- Clean build.
- Clean lint.
- Green automated test suite.
- Legacy code physically removed from the active repo state.

## Assumptions and Defaults
- Target OS is macOS 26+ only.
- The user-facing duplication between native menu bar and `Quick Access` is intentional and must be clearly explained in the UI.
- Focus Filter absence is normal, not an error.
- Migration mapping:
  - legacy `pinned` -> `shortcut`
  - legacy `hidden` -> `panel`
  - legacy `archive` -> `archive`
- Compatibility window:
  - keep V2 readers and legacy command aliases for one major release
  - remove them in the release after successful V3 stabilization
- `toggleApplicationMenus` does not survive as a real feature in the V3 product contract.
- The plan assumes the current local modifications already committed into the repo are the starting point and must be refactored forward, not reverted to upstream.

## References
- Apple `NSStatusItem`: https://developer.apple.com/documentation/appkit/nsstatusitem
- Apple `MenuBarExtra`: https://developer.apple.com/documentation/swiftui/menubarextra
- Apple `NSWorkspace.didActivateApplicationNotification`: https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification
- Apple `AXObserverCreate`: https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate
- Apple `AXUIElementPerformAction`: https://developer.apple.com/documentation/applicationservices/1459138-axuielementperformaction
- Apple `CGWindowListCopyWindowInfo`: https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo
- Apple `Defining a custom URL scheme for your app`: https://developer.apple.com/documentation/uikit/core_app/allowing_apps_and_websites_to_link_to_your_content/defining_a_custom_url_scheme_for_your_app
- Apple `Launch Services Keys / CFBundleURLTypes`: https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html
- Apple `Data.write(toFile:atomically:)`: https://developer.apple.com/documentation/foundation/nsdata/write%28tofile%3Aatomically%3A%29
- Apple `XCTest`: https://developer.apple.com/documentation/xctest/
- Apple WWDC 2022 `Meet Focus filters`: https://developer.apple.com/videos/play/wwdc2022/10121/

## Decision Rationale
- This plan intentionally narrows the product contract because public macOS APIs allow observation and partial activation of third-party menu extras, but do not provide a reliable public mechanism for perfect physical control of their native menu-bar placement.
- A perfect app is therefore best pursued as a stable launcher/organizer with explicit semantics, not as a best-effort native-bar manipulator.
