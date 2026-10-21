# Evaluation evidence format v1

`scripts/evidence.py` is the executable, closed-field schema. Unknown/missing
fields, duplicate JSON keys, nonfinite numbers, unsupported versions, checksum
drift and incomplete evidence are errors. Only Python standard library is used.
All paths are relative to the candidate document's directory and must stay
inside it, including after resolving symlinks. No download or external lookup
occurs. Evidence requires review; JSON metadata cannot prove that a study was
performed or authenticate a reviewer.

## Narrative candidate

The candidate object has exactly `schemaVersion: 1`, `identity`, `protocol`, and
`evidence`. Identity has four nonempty strings: `model`, `policy`, `runtime`,
`build`. Use exact version or checksum identities, never a moving `latest` tag.
Every artifact reference is `{ "path": "report.json", "sha256": "<64 lowercase hex characters>" }`.

`protocol` references a frozen protocol. `evidence` has exactly five references:
`annotationAgreement`, `heldOutMetrics`, `hardNegatives`, `contextComparison`,
`devicePerformance`. A missing report blocks admission.

The protocol has these fields:

| Fields | Contract |
| --- | --- |
| `schemaVersion`, `identity` | Version 1; exact candidate identity |
| `status`, `selectedOn`, `frozenBeforeEvaluation` | `frozen`, `validation`, `true` |
| `validationDatasetSHA256`, `heldOutDatasetSHA256` | Distinct SHA-256 hashes of frozen datasets |
| `signals`, `languages`, `lengthBuckets` | Nonempty arrays of unique nonempty strings; define all required metric slices |
| `thresholds` | Every signal maps to a finite value in [0, 1], chosen on validation |
| `minimumAgreement`, `minimumF1`, `maximumHardNegativeRate`, `minimumContextF1Delta` | Prespecified bounds in [0, 1]; choose with effect-specific costs before evaluating held-out data |
| `maximumWarmP95Milliseconds` | Positive finite device latency limit |

Every report contains exactly `schemaVersion: 1`, `kind` (its evidence key),
`identity`, `protocolSHA256`, nonempty `reviewer`, `status: "passed"`, and `data`.
Changing the protocol invalidates all report bindings. Report data:

| Kind | Required data |
| --- | --- |
| `annotationAgreement` | Nonempty `method`, `agreement` in [0, 1], integer `annotators` ≥ 2 and `cases` ≥ 1. Agreement must meet the frozen minimum. |
| `heldOutMetrics` | `datasetSHA256` matches held-out, `thresholdDatasetSHA256` matches validation, `evaluations: 1`, `slices`. Every required signal × language × length bucket occurs once. Each slice contains `signal`, `language`, `lengthBucket`, positive integer `cases`, and [0, 1] values `precision`, `recall`, `f1`, `prAUC`, `calibrationError`. F1 must match precision/recall and meet the frozen minimum. Record PR-AUC and calibration estimation methods in the reviewed study. |
| `hardNegatives` | Positive integer `cases`, integer `falseReactions` from 0 through cases, positive integer `productionLikeCases` ≤ cases, and provenance fields below. False-reaction rate must meet the frozen maximum. |
| `contextComparison` | Held-out `datasetSHA256`, positive integer `cases`, `withoutContextF1` and `withContextF1` in [0, 1]. Difference must meet the prespecified minimum. |
| `devicePerformance` | `physicalDevice: true`, nonempty `device`, `os`, `configuration: "release"`, positive integer `concurrency`, `samples`, `peakMemoryBytes`, `modelBytes`, finite nonnegative `tokenizationP95Milliseconds`, `coldLoadMilliseconds`, `warmP50Milliseconds`, `warmP95Milliseconds`, `statePolicyP95Milliseconds`, `dispatchP95Milliseconds`, nonempty `sustainedEnergyThermal`. Warm p50 ≤ p95 ≤ frozen limit. |

Keep raw measurements, dataset rights, methodology, reviewer decisions and split
freeze timestamps beside the reviewed reports. The v1 validator admits reports;
it does not compute metrics, train a model, or verify claimed study chronology.
The [study tools](../../Documentation/SemanticEvaluation.md) now calculate these
metrics from raw inputs and reserve an evaluation attempt; their outputs remain
unreviewed. Protocol and dataset changes require a new study/version. Do not repeatedly
evaluate the same held-out set while tuning thresholds.

## Regression corpus

Exactly `schemaVersion: 1`, nonempty `version`, and nonempty `cases`. Each case
has unique nonempty `id`, `test` (test identifier), and four provenance fields:
nonempty `provenance`, `rights`, `removalPolicy`, plus `sanitization` set to
`synthetic`, `sanitized`, or `licensed-public`. Confirmed production failures
must be curated and sanitized before entry; automatic ingestion is prohibited.

## Physical record

See `ReleaseEvidence/physical-device-template.json`. Copy under
`ReleaseEvidence/<release-version>/`, fill exact candidate identities, device,
OS, ISO calendar date, reviewer and notes, and mark each tested checklist item
`passed`. `physicalDevice` must be `true` and `status` must be `passed`. The empty
template intentionally fails validation. Each release needs its agreed device
matrix and separate experience-study report; one valid record does not prove
matrix completeness or approve a release by itself.
