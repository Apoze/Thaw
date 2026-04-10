## Identity Calibration Corpus

Redacted corpus for V3 Phase 2 identity calibration.

This corpus is intentionally fixture-driven and kernel-independent:
- no live AX dependency
- no workspace dependency
- no writes outside per-test temporary persistence paths

`corpus-v1.json` schema:
- `version`: corpus schema version
- `scenarios[]`: ordered replay scenarios
- `scenarios[].frames[]`: sequential observations for one scenario
- `reloadRegistryBeforeFrame`: when `true`, the test recreates `IdentityRegistry` with the same persistence paths before replaying that frame
- `observations[]`: synthetic discovered candidates plus frozen legacy-reference outcome
- `expectedStableKeyBasis`: basis used by the frozen legacy resolver to derive the reference `identity.id`
- `expectedMetrics`: aggregate assertions for the scenario

Metric definitions:
- `identityChurnCount`: same logical label observed with a different canonical ID across frames
- `canonicalReassignmentCount`: one canonical ID observed for different logical labels in the replay harness
- `ambiguousObservationCount`: resolved observations with `.ambiguous` confidence
- `provisionalPromotionCount`: `.provisional -> .high` promotion transitions
- `falseAutoBindCount`: shadow runtime `identity.id` diverges from the frozen legacy reference
- `shadowObservationCount`: cumulative shadow-mode observations reported by `IdentityRegistry`

The replay harness executes two structured paths against the same corpus:
- a frozen legacy reference resolver derived from `expectedStableKeyBasis` and `expectedConfidence`
- `IdentityRegistry(mode: .shadow)`

The checked-in report snapshot is generated from that comparison and records both legacy-reference metrics and shadow metrics.
