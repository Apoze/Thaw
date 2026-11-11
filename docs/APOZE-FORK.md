# Apoze fork based on Thaw 2.1.0

Branch: `fork/2.1.0-anchored-menus`. Bundle identifier: `io.github.apoze.thaw`.

Accessible status menus are mirrored beneath their Thaw Bar icon without moving the original icon. Commands are revalidated against the owning application before execution. The panel activates on opening so the first click can open a menu. Custom application panels retain their own positioning. Official Sparkle startup is disabled for this fork.

The user confirmed anchored menu placement, preserved bar visibility, improved latency and the first-click fix on macOS 26.6.2. Command delivery and complex submenus still need broader manual testing. Automated tests cover candidate matching, command identity and separator handling; they cannot establish live AppKit focus behavior. New-code coverage has not been measured, so the repository's 80% coverage requirement is not claimed as satisfied.

Validation: Xcode Debug builds passed. The seven ThawBarMenuPolicyTests passed. Strict lint on the new modules passed; repository-wide strict lint reports existing legacy_swiftui_aspect_ratio violations with SwiftLint 0.65.1. SwiftFormat was run, with changes to unrelated files restored. This private fork exceeds the recommended 500-line patch size because it combines identity changes, the focused menu presenter/bridge, tests and formatting of touched files.

Earlier applications and settings are retained locally as archives. Only /Applications/Thaw Apoze.app remains installed. The original development branch is preserved for history.

Move and capture follow-up (2026-11-11):

- Display enumeration retains the auto-hidden menu-bar lane. Capture validation rejects changed bounds, incomplete height and empty non-spacer images. Layout previews trim vertical transparent margins and center glyphs. The user confirmed the correct Nodelace glyph after restarting Nodelace, and confirmed that the floating bar no longer follows the pointer.
- The 19:15 and 19:20 local reports failed in visibility preparation before sending any move. The 19:21 journal showed the auto-hide animation being mistaken for a drag response. A display-scoped, reference-counted WindowServer visibility override now spans the complete move and its verification, without altering global auto-hide preferences. Geometry must be fully revealed and stable before events are posted. Vertical-only changes cannot acknowledge a horizontal move.
- The user confirmed working moves with this hold installed. The 19:29–19:30 journal nevertheless showed hidden-bound moves completing through the fallback release: on the external display, a held offscreen teleport was transiently clamped at global x=0. Release validation now uses the already-validated press frame only for the exact held source of a parked teleport; it still resolves both identities and validates the live destination. At-rest endpoint and cross-display guards are unchanged.
- SCK capture now requires full containment in CoreGraphics display coordinates, including after recent moves. Live refresh falls back to the existing capture helper if SCK fails. Previously, the recent-move path bypassed the visibility filter, causing futile per-icon captures as soon as the system bar retracted.

Validation before the final release/capture adjustment: 46 tests in five suites passed. Xcode coverage measured 93.1% for MenuBarMoveVisibility and 100% for the new horizontal-response predicate. No whole-fork coverage claim is made. Strict lint of touched files passed; full strict lint still reports 11 existing legacy_swiftui_aspect_ratio violations. SwiftFormat was executed; its unrelated changes and invalid actor-hoisting transformations were restored. Final targeted validation: 104 tests in eight suites passed, covering move visibility, display lanes, event coordinates, endpoint identity, layout settling, gestures, capture bounds and move policy. Final release/capture changes still need live confirmation after installation.

The private move reports and full runtime logs remain local and are not committed. The dynamically resolved visibility override follows the API used in https://github.com/FelixKratz/dotfiles/issues/71; its availability is checked at runtime and actual WindowServer geometry, rather than API availability alone, gates the move.
