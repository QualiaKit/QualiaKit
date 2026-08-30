# Current Russian Core ML baseline — archaeology model card

Contract: `current-russian-v1`
Fixture: `current-russian-fixture-v1`
Model identity: `rub-sentiment-coreml-local-audit@sha256-f7ac2156e756a2aa`

## Intended status

This is a checksum-bound recovery record for the unchanged local Core ML baseline. It is not an endorsement, a redistributable official model, or evidence that the model measures sentiment, narrative suspense, threat, shock, a person's emotion, or mental state. Runtime refactoring remains blocked by the manifest gate.

The model package and production vocabulary are protected external inputs. They must stay outside Git and public CI and are read only through `QUALIAKIT_TEST_MODEL_PATH` and `QUALIAKIT_TEST_VOCAB_PATH`.

## Verified asset and export facts

- The package contains fixed required Int32 tensors `input_ids`, `attention_mask`, and `token_type_ids`, each shaped `1 × 128`.
- It returns `classLabel` and `classLabel_probs`, with exactly `LABEL_0` through `LABEL_4`.
- Core ML metadata identifies an ML Program, specification version 6, Float16 storage, mixed compute precision, conversion date 2025-11-17, coremltools 9.0, Torch 2.9.1, and TorchScript source dialect.
- Graph inspection shows the last five-value classifier linear operation is cast directly into Core ML `classify`. There is no classifier softmax between them. The 12 graph softmax operations are encoder attention operations.
- Numeric fixtures show the dictionary values are finite and not normalized; their argmax selects `classLabel`. The current contract therefore classifies them as classifier logits/raw scores. Stable softmax is serialized separately.
- The audited vocabulary contains 119,547 unique nonblank records. Its SHA-256 is `78106a3d3ae8600d1ba573b967b9bb731d2c2282957cbc6e26ab20935c3da02b`; PAD=0, UNK=100, CLS=101, SEP=102, MASK=103.

Exact package component checksums are normative in `manifest.json`. A composite package identity is computed from those named component hashes; protected bytes are not copied into this repository.

## Reconstruction boundary

The independent tokenizer reproduces the current Swift implementation: Unicode lowercase, splitting on Unicode whitespace/newlines and punctuation, greedy WordPiece-like lookup using `##` after the first piece, whole-word UNK fallback, CLS/SEP insertion, truncation to 128 with a terminal SEP, and right padding. It proves current-runtime parity over the sanitized corpus. It does not prove that these rules or this tokenizer version were used during training.

The Core ML signature proves that `token_type_ids` is required by the converted asset. It does not prove a training pair/context template. Pair or bounded-context support therefore remains unknown and must not be declared.

## Unknown provenance, task, and semantics

No primary source checkpoint, upstream model identifier, training configuration, export script, dataset record, dataset domain, split, class balance, tokenizer package/version, input template, label schema, model license, data license, or redistribution grant is present in scope. Each remains an explicit structured unknown with a role owner and proof plan in the manifest.

All five label meanings—including `LABEL_4`—are unknown. Current code comments are not primary evidence. No label has a product-facing signal. The repository MIT license covers repository code and metadata only; it is not evidence for the external model, vocabulary, or training data.

Redistribution is blocked until Legal and the ML model owner produce checksum-bound primary license and ownership evidence. Local audit permission must not be generalized into publication permission.

## Current Swift mismatch inventory (documented, not corrected here)

The unchanged `BertTokenizer` and `BertModelWrapper` have these archaeology observations:

1. Tokenizer behavior is reconstructed from implementation, not a training tokenizer config; no Unicode normalization is applied beyond lowercase.
2. Comments call `LABEL_0`, `LABEL_1`, and `LABEL_2` negative, neutral, and positive without primary evidence. `LABEL_3` and `LABEL_4` have no asserted meanings.
3. `classLabel_probs` contains raw classifier scores, but the wrapper applies a second stable softmax before returning `softmax(LABEL_2) − softmax(LABEL_0)`.
4. Missing dictionary labels are substituted with `0.0`, which can hide an output-contract failure.
5. A missing or unexpected `classLabel_probs` shape returns `0.0`, producing neutral-like behavior instead of a typed model-contract error.
6. The wrapper supplies an all-zero `token_type_ids` tensor. This executes the current asset but does not prove training context/pair semantics.
7. The unchanged Swift runtime uses Core ML's default unrestricted compute policy. The reference verifier pins CPU-only execution because an isolated `.all` verification process exceeded the zero-delta calibration envelope; this avoids silently accepting scheduler-dependent output drift.

Golden fixtures serialize the current numeric transform for parity but mark final semantic mapping unknown. This task intentionally does not change runtime sources.

## Evaluation and limitations

The sanitized corpus is a regression corpus, not an accuracy dataset. It includes more than 100 Russian production-like and boundary cases: ё/е, dash and quote variants, ellipses, emoji, mixed scripts, casing, unknown words, negation, hard negatives, punctuation, whitespace, and truncation. It supports exact preprocessing and execution parity only.

There is no evidence for accuracy, calibration, supported domains, narrative semantics, subgroup behavior, robustness to adversarial text, or non-Russian behavior. Do not use this baseline for medical, psychological, employment, credit, safety, surveillance, people-scoring, or user-emotion claims.

## Reproducibility

`Tools/ModelContract/requirements.lock` pins the network-free executable environment, including CPU-only Core ML execution. `reference_inference.py --verify` validates all protected and repository artifact checksums before inference, regenerates the fixture in a temporary location, compares every discrete field exactly, compares floating fields with the manifest-declared per-output absolute tolerances, and never overwrites golden data. Comparator regression scenarios prove that a discrete mismatch fails, a float delta exactly at tolerance passes, and a just-over-tolerance delta fails.

Calibration uses the complete corpus in at least ten fresh sequential OS processes. A later set of at least five fresh processes must remain inside the fixed maximum observed calibration delta. Raw process values, recomputed distributions, environment, compute policy, backend, and holdout decisions are stored in `Tests/Golden/current/current-russian-fixture-v1/calibration-v1.json`.

A separate earlier cross-implementation run (`20260828T085409.950178Z`) disproved an absolute `1e-5` reference-to-Core-ML tolerance: 572 non-zero raw-score differences had min `0.000030517578125`, p50 `0.0068359375`, p95 `0.0234375`, p99 `0.0341796875`, and max `0.04296875`. Only that aggregate evidence is available, so `0.04296875` is retained as the observed lower bound for any future source-framework/Core-ML comparison and is not fabricated into per-label fresh-process samples. The pinned CPU-only same-asset calibration in this contract is a separate comparison; its tolerance must not be reused for a cross-implementation or unrestricted-compute comparison.

## Owners and release gate

- Contract and fixture maintenance: QualiaKit maintainers.
- Source model, training, labels, tokenizer, and dataset proof: ML model owner.
- License and redistribution proof: Legal owner.
- Physical-device performance evidence: release owner, through consolidated release gate `HG-0015-002`.

The runtime-refactor gate is blocked while any of label semantics, output kind, training-tokenizer parity, or provenance is unresolved. Output kind is resolved for the converted Core ML asset; the other three conditions remain unresolved.
