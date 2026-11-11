# Apoze fork based on Thaw 2.1.0

Branch: `fork/2.1.0-anchored-menus`. Bundle identifier: `io.github.apoze.thaw`.

Accessible status menus are mirrored beneath their Thaw Bar icon without moving the original icon. Commands are revalidated against the owning application before execution. The panel activates on opening so the first click can open a menu. Custom application panels retain their own positioning. Official Sparkle startup is disabled for this fork.

The user confirmed anchored menu placement, preserved bar visibility, improved latency and the first-click fix on macOS 26.6.2. Command delivery and complex submenus still need broader manual testing. Automated tests cover candidate matching, command identity and separator handling; they cannot establish live AppKit focus behavior. New-code coverage has not been measured, so the repository's 80% coverage requirement is not claimed as satisfied.

Validation: Xcode Debug builds passed. The seven ThawBarMenuPolicyTests passed. Strict lint on the new modules passed; repository-wide strict lint reports existing legacy_swiftui_aspect_ratio violations with SwiftLint 0.65.1. SwiftFormat was run, with changes to unrelated files restored. This private fork exceeds the recommended 500-line patch size because it combines identity changes, the focused menu presenter/bridge, tests and formatting of touched files.

Earlier applications and settings are retained locally as archives. Only /Applications/Thaw Apoze.app remains installed. The original development branch is preserved for history.
