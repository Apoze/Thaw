# V3 Manual Validation Record

Date: 2026-04-09

This record captures the live-machine validation work that was actually executed during lot `7.2`.

## Host Snapshot

- Host: `My Mac`
- Platform: `macOS 26.4`
- Hardware family: `MacBook Pro`
- Display inventory during this run:
  - built-in internal display present
  - no external display attached
- Corpus app availability during this run:
  - installed: `Tabby`, `Bitwarden`, `OrbStack`, `AltTab`, `Joplin`
  - not installed: `MacVirt`

## Executed Live Checks

### Launching the local Debug build

Executed:
- `open -a '/Users/maz/Library/Developer/Xcode/DerivedData/Thaw-hbqmdmkakizdlubvjdqoyehpsydl/Build/Products/Debug/Thaw.app'`

Observed:
- Thaw launched successfully.
- `System Events` observed the live Thaw process.
- The only persistent live window on this host state was:
  - `Autorisations`

Interpretation:
- The app is launchable on the local machine.
- This host is still permission-gated for the full runtime path, so surface checks that depend on the active runtime cannot be treated as fully discharged here.

### External-launcher URL exercise

Executed from an external launcher surface:
- `open 'thaw://toggle-hidden'`
- `open 'thaw://toggle-always-hidden'`
- `open 'thaw://panel'`
- `open 'thaw://archive'`

Observed after the compatibility fix:
- Thaw remained running.
- No `CommandRouter` warning was emitted for the legacy hosts.
- The visible live window remained `Autorisations`, which is consistent with the host remaining permission-gated.

Log verification:
- `/usr/bin/log show --start '2026-04-09 21:54:13' --predicate 'process == "Thaw"' --style compact | egrep 'CommandRouter|toggle-hidden|toggle-always-hidden|panel|archive'`
- Result after the compatibility fix and relaunch: no unrecognized-URL warning for the legacy hosts.

Interpretation:
- The compatibility-window external URL contract is live again for:
  - `thaw://toggle-hidden`
  - `thaw://toggle-always-hidden`
- The current V3 URL contract remains live for:
  - `thaw://panel`
  - `thaw://archive`
  - `thaw://surface`
  - `thaw://search`
  - `thaw://settings`

### Corpus-app host audit

Observed running-state summary during this run:
- `Tabby`: running, visible
- `Bitwarden`: running, visible
- `OrbStack`: running, visible
- `AltTab`: running, background-only
- `Joplin`: running, visible

Interpretation:
- The machine can later be used to validate five named corpus apps.
- `MacVirt` cannot be exercised on this host in its current state.
- The already-running apps were not forcibly quit/relaunched during this session, to avoid disrupting active local user state.

## Remaining Blockers On This Host

The following manual-matrix checks remain open because this host was not in the required state during this run:

- `External display attached`
  - Blocked: no external display connected.

- `Primary display change`
  - Blocked: single-display host state during this run.

- `Rapid open/close of the Thaw panel`
  - Blocked: Thaw remained in the permissions-gated host state.

- `Repeated clicks on the same menu extra`
  - Blocked: same permission-gated host state.

- `Open item and reopen Thaw immediately afterward`
  - Blocked: same permission-gated host state.

- `App relaunch for Tabby / Bitwarden / OrbStack / MacVirt / AltTab / Joplin`
  - Blocked:
    - `MacVirt` absent
    - the remaining named apps were already in active local use during this session

- `Existing user install upgraded in place from current local architecture`
  - Blocked: no controlled upgraded-install state was prepared for this run.

- `Repeated open/close/relaunch loops for the calibration corpus apps to confirm identity stability`
  - Blocked by the same host-state constraints:
    - permission-gated Thaw runtime
    - no prepared upgraded state
    - `MacVirt` absent
    - remaining apps already active on the local machine

## Result

This live run materially improved the `7.2` record:
- it confirmed the actual host state
- it exercised the external-launcher path on the real machine
- it exposed the legacy URL compatibility regression
- it verified the compatibility fix after rerunning the live URL exercise

It does not close the full manual matrix. The remaining blockers are host-state blockers, not open ambiguity about the active code path.
