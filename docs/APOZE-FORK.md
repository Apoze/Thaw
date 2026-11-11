# Apoze fork based on Thaw 2.1.0

Branch: `fork/2.1.0-anchored-menus`. Bundle identifier: `io.github.apoze.thaw`.

Accessible status menus are mirrored beneath their Thaw Bar icon without moving the original icon. Commands are revalidated against the owning application before execution. The panel activates on opening so the first click can open a menu. Custom application panels retain their own positioning. Official Sparkle startup is disabled for this fork.

The user confirmed anchored menu placement, preserved bar visibility, improved latency and the first-click fix on macOS 26.6.2. Command delivery and complex submenus still need broader manual testing. Automated tests cover candidate matching, command identity and separator handling; they cannot establish live AppKit focus behavior. New-code coverage has not been measured, so the repository's 80% coverage requirement is not claimed as satisfied.

Validation: Xcode Debug builds passed. The seven ThawBarMenuPolicyTests passed. Strict lint on the new modules passed; repository-wide strict lint reports existing legacy_swiftui_aspect_ratio violations with SwiftLint 0.65.1. SwiftFormat was run, with changes to unrelated files restored. This private fork exceeds the recommended 500-line patch size because it combines identity changes, the focused menu presenter/bridge, tests and formatting of touched files.

Earlier applications and settings are retained locally as archives. Only /Applications/Thaw Apoze.app remains installed. The original development branch is preserved for history.

Move follow-up: 17 display-lane and endpoint-identity tests pass. Live validation of automatic menu bar reveal is pending. SwiftFormat 0.64.6 incorrectly hoists actor annotations onto nonisolated extensions in MenuBarItem+Enumeration.swift; those transformations are reverted to the successfully tested declarations.

Follow-up: NSMenu visibility requests did not reliably reveal the automatically hidden bar on this Mac. The user-initiated move path now uses a bounded hover in the right-hand status area and preserves physical pointer movement. Layout previews trim vertical transparency before centering the glyph. Live verification of these two changes remains pending.

Capture follow-up: reject images with mismatched height or changed WindowServer geometry. Empty non-spacer captures no longer replace existing icons, and cached empty captures use the application-icon fallback. Move preparation requires four identical fully revealed endpoint samples. The supplied diagnostic report is retained locally, not published. End-to-end confirmation remains pending.

Icon presentation: visible-section refresh uses the offscreen helper while the menu bar is concealed. Empty composite slices are retried individually. For Nodelace, a single same-owner alternate display surface can supply its glyph when the primary surface is transparent. Pointer and dynamic placement are resolved once per Thaw Bar opening.

Latest live checks: native system glyphs were visually verified in the layout editor. The user confirmed that restarting Nodelace restored its correct status icon. The fixed opening anchor is installed; mouse-motion stability and repeated moves between sections still need live confirmation.
