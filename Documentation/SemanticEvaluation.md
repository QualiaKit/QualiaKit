# Semantic and experience evaluation tools

Runtime, semantic and experience results remain separate. The Russian model now
has verified matching source weights and an empirical, non-author-confirmed label
map; see [Russian model recovery](RussianModelEvaluation.md). Its historical audit
remains unchanged. The public Core ML models are arithmetic fixtures.
Neither can supply a narrative evaluation by relabelling their outputs. No real
narrative dataset or semantic score is invented by these tools.

## Semantic study

`Evaluation/scripts/study.py` uses only Python's standard library. Supply real
curated/licensed/sanitized data, independently collected annotations, adjudicated
binary labels and prediction exports from the **same identified candidate**.
The [study input contract](../Evaluation/schemas/study-v1.md) defines the fields.

```sh
python3 Evaluation/scripts/study.py freeze \
  --validation /path/validation.json --predictions /path/validation-predictions.json \
  --test /path/test.json --plan /path/selection-plan.json --out /path/new-study

# Run the candidate on the frozen held-out cases and export both modes.
python3 Evaluation/scripts/study.py evaluate --study /path/new-study \
  --test /path/test.json --predictions /path/test-predictions.json
```

Freeze selects each threshold using validation predictions and prespecified
false-positive/false-negative costs. Ties prefer fewer false reactions, then a
higher threshold. Held-out predictions cannot be supplied to threshold selection.
Duplicate case IDs, shared narrative groups and identical current texts across
validation/test are rejected. Each required signal×language×length slice needs
both positive and negative cases. Rights/provenance and at least two annotators
are mandatory. These metadata checks cannot authenticate annotator independence
or detect paraphrase leakage; a human must review the collection and split.

Evaluation computes precision/recall/F1, step-integrated PR area (average precision
with tied scores grouped), calibration error (ten equal-width probability bins),
Fleiss kappa over case×signal items, hard-negative false-reaction rate, and matched
micro-F1 with/without context using the same frozen thresholds. Undefined kappa
for constant ratings is rejected. Negative kappa is retained as a failed numeric
result; it is never clipped to zero. No aggregate quality score is produced.

A new study directory is required; freeze does not overwrite an existing study.
`selection.json` binds the plan, validation predictions and frozen protocol by
checksum. Evaluation checks the protocol and dataset hashes and reserves
`evaluation.lock` before computing results. A second or interrupted attempt in the
same study is rejected. Failed attempts remain visible. Files/JSON cannot prove
chronology across copied directories or prevent a person from recreating studies;
external review and dataset governance remain required.

The four generated reports are **unreviewed**, even when numerical limits pass.
`measurement.json` lists numeric outcomes and methods. Keep raw data/predictions
and reviewer decisions alongside them. After actual review, bind the reviewed
reports and candidate-specific physical performance report into the existing
[candidate format](../Evaluation/schemas/README.md) and run `evidence.py narrative`.
The tiny public fixture's device timings cannot substitute for the candidate's
performance. Admission still requires all five report kinds. Synthetic data in
unit tests is solely for tool verification, never release evidence.

## Experience study

The device lab collects per-variant perceptual feedback for one holder. A broader
static-versus-adaptive study uses `Evaluation/scripts/experience.py`, independently
of the semantic gate:

```sh
python3 Evaluation/scripts/experience.py /path/paired-study.json --output /path/new-summary.json
```

Input has `schemaVersion: 1`, exact `identity`, provenance/rights/sanitization/
removalPolicy, and a nonempty `sessions` array. Each row has a unique anonymous
`participantID`, `order` (`static-first` or `adaptive-first`), `preference`
(`static`, `adaptive`, `tie`), and `static`/`adaptive` objects. Each mode contains
integer `alignment`, `immersion`, `comfort` ratings from 1 through 5, nonnegative
integer `falseReactionComplaints`, boolean `disabled`, and positive `minutes`.
Do not use real names, device identifiers or production reading text as IDs.

The tool reports per-mode means, paired adaptive-minus-static rating differences,
complaints per hour, disable rates, preferences and presentation-order counts.
It does not infer significance, causal effects or population quality. The result
remains unreviewed; sample size, recruitment, order balance and the study protocol
need separate review. A single-device tactile check is not that broader study.
