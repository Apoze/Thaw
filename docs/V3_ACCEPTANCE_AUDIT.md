# V3 Acceptance Audit

Date: 2026-04-09

This audit records the `7.2` acceptance-gate review against [`PLANS.md`](/Users/maz/Documents/GitHub/Thaw/PLANS.md). It separates:
- criteria proven by code/tests/greps
- criteria satisfied on the active path but still relying on architecture review
- criteria not yet proven, or currently blocked

`PLANS.md` remains the source of truth. This file is an execution artifact for the final gate.

## Validation Executed

Executed on 2026-04-09:
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -scheme Thaw -configuration Debug build`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -scheme Thaw -configuration Debug test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Thaw -configuration Debug test -only-testing:ThawIntegrationTests/IdentityCalibrationReplayTests -only-testing:ThawTests/IdentityRegistryTests`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Thaw -configuration Debug test -only-testing:ThawIntegrationTests/RuntimePerformanceAcceptanceTests/testServiceLevelP95BenchmarksStayUnderPlanThresholds`

Supporting greps:
- `rg -n "MenuBarItemManager|HIDEventManager|MenuBarSection|MenuBarManager" Thaw Shared | rg -v "DiagnosticLogger\\.swift"`
- `rg -n "\\bControlItem\\b|show\\(section:|currentSection" Thaw | rg -v "ControlItemImage(Set)?\\.swift"`
- `rg -n "\\bCGS\\b|cursor transport|synthetic drag|synthetic move" Thaw Shared`
- `rg -n "MenuBarSection|ControlItem\\.swift|MenuBarItemService|MenuBarItemManager|HIDEventManager|MenuBarManager" Thaw.xcodeproj/project.pbxproj Thaw.xcodeproj/xcshareddata/xcschemes`
- `rg -n "refresh\\(reason:|toggleApplicationMenus|MenuBarItemManager|HIDEventManager|ThawFocusFilter\\.current" Thaw Shared`

Manual grep review note:
- the coarse forbidden-symbol grep still returns one `ThawFocusFilter.current` hit in [`FocusFilterService.swift`](/Users/maz/Documents/GitHub/Thaw/Thaw/Settings/Models/FocusFilterService.swift); this was manually reviewed and remains limited to the explicit resync boundary, not the default bootstrap path

## Criteria Status

### Proven

- `No production use of private CGS APIs.`
  Proven by grep. No active `CGS` usage remains under `Thaw` or `Shared`.

- `No cursor warp/hide/show behavior.`
  Proven by grep. No active cursor transport helpers remain.

- `No synthetic drag/click transport for third-party extras.`
  Proven by grep. No synthetic transport path remains in the active repo state.

- `No free-form string refresh reasons in the active runtime.`
  Proven by grep and tests, especially `DiscoveryInvalidationTests`.

- `Deprecated toggleApplicationMenus cannot change runtime behavior in V3.`
  Proven by command-routing coverage and the absence of an active runtime implementation.

- `No migration path runs outside MigrationCoordinator.`
  Proven by code review, grep on startup wiring, `MigrationCoordinatorTests`, `StartupMigrationRunnerTests`, and `AppGraphBootstrapTests`.

- `No group changes as a side effect of activation.`
  Proven by activation/panel tests and the separation between `ActivationService` and `LayoutService`.

- `No late insertion into the panel after it is shown during normal operation.`
  Proven on the automated path by `PanelServiceTests` and `PanelActivationIntegrationTests`, which lock the `prepare -> show -> interact -> dismiss` contract.

- `No user-visible error when no Focus Filter is configured.`
  Proven by `FocusFilterServiceTests` and by the current bootstrap design.

- `Identity registry auto-bind has zero known identity steals on the calibration corpus.`
  Proven by `docs/identity-calibration-report-v1.json`, which records `falseAutoBindCount = 0`.

- `Stable single-extra apps never change canonical ID across relaunch tests.`
  Proven by the `ax-stable-relaunch` calibration scenario and `IdentityRegistryTests`.

- `p95 warm panel open under 120ms.`
  Proven by `ThawIntegrationTests/RuntimePerformanceAcceptanceTests.swift` and `docs/runtime-performance-acceptance-report-v1.json`, which records `warmPanelOpen.millisecondsP95 = 6.367541`.

- `p95 incremental discovery under 100ms.`
  Proven by `ThawIntegrationTests/RuntimePerformanceAcceptanceTests.swift` and `docs/runtime-performance-acceptance-report-v1.json`, which records `incrementalDiscovery.millisecondsP95 = 0.140667`.

- `p95 interactive activation under 300ms.`
  Proven by `ThawIntegrationTests/RuntimePerformanceAcceptanceTests.swift` and `docs/runtime-performance-acceptance-report-v1.json`, which records `interactiveActivation.millisecondsP95 = 0.048124999999999994`.

- `Clean build.`
  Proven by the full debug build run on 2026-04-09.

- `Clean lint.`
  Proven by `swiftlint lint --strict` on 2026-04-09.

- `Green automated test suite.`
  Proven by the full debug test run on 2026-04-09.

- `Legacy code physically removed from the active repo state.`
  Proven by repo greps and the removal of `MenuBarSection`, `ControlItem`, `MenuBarItemService`, `HIDEventManager`, and related project references from the active path.

### Satisfied On The Active Path, Still Backed By Review

- `No duplicated runtime paths for the same feature.`
  The active bootstrap, discovery, activation, layout, profiles, and focus paths are singular by architecture review and source-boundary tests. This is not backed by a dedicated “duplicate path detector” test.

- `No dual permission authority.`
  The active authority is `PermissionService`. A `typealias PermissionCoordinator = PermissionService` shell remains, but it does not introduce a second runtime authority.

- `No low-level runtime service is injected directly into SwiftUI view trees.`
  Source-boundary tests cover the main V3 adapters and views. The active view trees are graph/adaptor driven, but this remains partly an architectural review statement.

- `No permanent global recovery polling.`
  The active discovery path uses typed invalidations and AX observers with bounded recovery. This is covered by `AXObservationServiceTests` and `DiscoveryServiceTests`, but the absence of long-running polling is still partly a code-review conclusion.

- `No user-visible legacy terminology once V3 UI is shipped.`
  The active SwiftUI/UI path uses `Quick Access`, `Panel`, and `Archive`. `README.md` was updated on 2026-04-09 to align with V3 terminology. Inactive localization tombstones for old wording still exist in `Localizable.xcstrings`, but they were not found on active source call sites during this gate.

### Not Yet Proven / Blocked

- `Legacy URLs and hotkeys continue to work during the compatibility window.`
  Proven by `CommandRouterTests`, `StartupBaselineIntegrationTests`, and the live-machine rerun recorded in [`V3_MANUAL_VALIDATION_2026-04-09.md`](/Users/maz/Documents/GitHub/Thaw/docs/V3_MANUAL_VALIDATION_2026-04-09.md). The compatibility hosts `thaw://toggle-hidden` and `thaw://toggle-always-hidden` were restored and no longer emit `CommandRouter` warnings on the live rerun.

- `Identity churn stays below 0.5% across replay and manual stabilization scenarios.`
  Replay stabilization is now discharged by `acceptanceSummary`, but the live manual stabilization scenarios from the final matrix have still not been executed and recorded.

## Manual Validation Matrix

Partially executed during this gate. The live-machine record for this run is in [`V3_MANUAL_VALIDATION_2026-04-09.md`](/Users/maz/Documents/GitHub/Thaw/docs/V3_MANUAL_VALIDATION_2026-04-09.md).

Executed on this machine on 2026-04-09:
- Built app launched from the local Debug product on the built-in MacBook display.
- Thaw remained in a permission-gated host state; `System Events` observed the live window `Autorisations`, so runtime-dependent panel/archive/discovery checks were blocked by the machine permission state.
- Legacy external-launcher URLs were exercised, found broken, fixed, rebuilt, and then re-exercised successfully on the live machine.
- Current `thaw://settings` routing was exercised and kept the settings/permissions windows reachable.
- Corpus-app availability on this machine was checked: `Tabby`, `Bitwarden`, `OrbStack`, `AltTab`, and `Joplin` are installed; `MacVirt` is not.
- Display inventory was checked: only the built-in internal display is attached; no external display was present for the external-display and primary-display-change checks.

Still open or blocked after the live run:
- notch-specific validation on a real MacBook display remains unproven from terminal-only observation
- external-display attach/detach and primary-display change
- relaunch loops on the named third-party apps, because `MacVirt` is absent and Thaw was not in a permission-granted runtime state
- rapid open/close of the Thaw panel
- repeated clicks on the same menu extra
- open item and reopen Thaw immediately afterward
- upgraded install validation on an existing local user state
- repeated open/close/relaunch loops for the calibration-corpus apps on a live machine

Automated coverage still discharges parts of this matrix, but the live matrix is not closable until the machine is in the required state to finish the remaining blocked scenarios.

## Result

`7.2` is not yet `done`.

The codebase is in a strong V3 state on the active path, and the automated validation gate is green, but final acceptance remains blocked by:
- the machine is not in the required state to finish the remaining live checks (`Accessibility` flow still open, no external display attached, `MacVirt` absent, no upgraded-install scenario prepared)
- the remaining live manual validation matrix, including the manual stabilization loops for identity

## Recommended Next Actions

1. Prepare a machine that satisfies the live-matrix prerequisites: required permissions granted, external display attached, `MacVirt` available if it remains in scope, and an upgraded-install state to validate in place.
2. Re-run the live manual matrix, including the calibration-corpus stabilization loops.
3. Re-run this acceptance audit and only then consider closing `7.2`.
