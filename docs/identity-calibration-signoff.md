# Identity Calibration Sign-Off

Status: engineering sign-off recorded on 2026-04-09

This artifact documents the calibration contract for `PLANS.md` Phase 2, lot `2.2`.

Reviewer:
- Architecture/implementation review completed by Codex orchestration on 2026-04-09

Decision:
- Current `IdentityRegistryThresholds` are accepted for the existing redacted corpus.
- No threshold retune is required before proceeding to later V3 lots.
- Final product cutover remains gated by `Phase 6`; this artifact records the engineering threshold review, not the final runtime cutover approval.

## Scope

Calibration assets introduced for this lot:
- `ThawTests/Fixtures/identity-corpus/corpus-v1.json`
- `ThawIntegrationTests/IdentityCalibrationReplayTests.swift`

The corpus is redacted and deterministic. It exercises identity behavior without live AX or workspace dependencies.
The checked-in report snapshot at `docs/identity-calibration-report-v1.json` is derived from the replay harness in `ThawIntegrationTests/Support/IdentityCalibrationReplaySupport.swift` and is validated against that replay in tests. The report records `legacyReferenceMetrics`, `shadowMetrics`, `totalLegacyReferenceMetrics`, `totalShadowMetrics`, and explicit parity counters so it reflects the structured comparison directly.
It also records an `acceptanceSummary` that partitions the corpus into:
- stabilization scenarios used for the acceptance churn/auto-bind thresholds
- intentional probe scenarios retained for churn/reassignment evidence

This partition is additive, not substitutive:
- full-corpus totals remain the canonical aggregate record
- stabilization metrics isolate the acceptance signal defined by `PLANS.md`
- probe metrics remain visible so deliberate negative scenarios are still audited and cannot be hidden by the acceptance slice

## Corpus Coverage

Current replay scenarios:
- `ax-stable-relaunch`
  Covers exact-match stability across relaunch, PID change, persistence reload, and slot movement.
- `multiple-extras-same-bundle`
  Covers same-bundle isolation and canonical stability when visible ordering changes.
- `non-ax-promotion`
  Covers repeated stable observations and `.provisional -> .high` promotion.
- `ambiguous-identical-nonax`
  Covers first-sighting ambiguity for visually identical non-AX items.
- `same-label-churn`
  Covers a same-label scenario that forces a new canonical ID when the prior record cannot be reused.
- `canonical-reassignment`
  Covers one canonical ID observed under two different redacted labels.

## Metrics

The replay harness asserts:
- `identityChurnCount`
  Same logical label resolves to a different canonical ID across frames.
- `canonicalReassignmentCount`
  One canonical ID is observed for more than one logical label in the corpus harness.
- `ambiguousObservationCount`
  Number of replay observations resolved as `.ambiguous`.
- `provisionalPromotionCount`
  Number of `.provisional -> .high` promotions across stable observations.
- `falseAutoBindCount`
  Resolver output diverges from the frozen legacy reference identity.
- `shadowObservationCount`
  Cumulative `IdentityRegistry` shadow observations during replay.

## Reviewed Thresholds

Thresholds reviewed against the current corpus on 2026-04-09:
- `autoBindMaximumScore = 72`
- `provisionalMaximumScore = 180`
- `minimumWinnerMargin = 24`
- `displayMismatchPenalty = 120`
- `axIdentifierMismatchPenalty = 240`
- `slotMismatchPenalty = 36`
- `frameDistanceTolerance = 18`
- `provisionalPromotionObservationCount = 3`

Result:
- no corpus scenario required a threshold change
- no false auto-bind was accepted
- churn, reassignment, ambiguity, and promotion metrics matched the replay expectations

## Evidence Reviewed

Corpus scenarios reviewed:
- `ax-stable-relaunch`
- `multiple-extras-same-bundle`
- `non-ax-promotion`
- `ambiguous-identical-nonax`
- `same-label-churn`
- `canonical-reassignment`

Expected aggregate outcomes across the corpus:
- exact relaunch stability preserved for AX-backed items
- same-bundle collisions remain isolated without canonical drift
- non-AX promotion occurs only after repeated stable observations
- identical first-sighting non-AX items remain ambiguous
- churn is surfaced when prior identity cannot be safely reused
- canonical reassignment reporting triggers when one canonical identity spans two logical labels

Acceptance summary:
- stabilization scenarios exclude the deliberate `churnProbe` and `reassignmentProbe` categories
- stabilization churn is evaluated against:
  - `ax-stable-relaunch`
  - `multiple-extras-same-bundle`
  - `non-ax-promotion`
  - `ambiguous-identical-nonax`
- probe metrics are evaluated and retained separately for:
  - `same-label-churn`
  - `canonical-reassignment`
- stabilization metrics plus probe metrics sum back to the full-corpus totals in the checked-in report

## Calibration Harness Scope

This lot intentionally ships a calibration harness, not a product runtime manager. The harness executes:
- a frozen legacy reference resolver over the corpus observations
- `IdentityRegistry(paths:mode: .shadow)` over the same frames
- a structured comparison and checked-in report snapshot derived from that replay

This is the intended Phase 2 artifact. It is sufficient to close threshold calibration for the redacted corpus without introducing a second runtime path into the product.

## Exit Criteria For Phase 2 Sign-Off

Do not treat Phase 2 as cutover-approved until all of the following are true:
- the calibration replay suite is green
- corpus coverage is considered representative for relaunch, same-bundle collisions, ambiguous non-AX cases, and promotion behavior
- churn and reassignment counts are explicitly reviewed
- threshold changes are recorded against corpus evidence, not intuition
- a product/architecture reviewer signs the cutover decision explicitly

## Review Checklist

- Corpus reviewed for redaction and determinism
- Scenario set reviewed against `PLANS.md` calibration requirements
- Replay expectations reviewed after any threshold or registry matching changes
- Current threshold values recorded alongside the replay evidence
- No sign-off granted on green tests alone; reviewer must acknowledge residual blind spots

## Suggested Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Thaw -configuration Debug -only-testing:ThawIntegrationTests/IdentityCalibrationReplayTests test
```

## Residual Blind Spots

Still not covered by this lot alone:
- live AX tree noise and observer timing
- real-world corpus breadth beyond the redacted fixtures in `corpus-v1.json`
