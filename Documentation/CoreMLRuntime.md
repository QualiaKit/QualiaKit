# Manifest-driven Core ML runtime: stage 1 of spec 0004

`Packages/QualiaCoreML` is an opt-in local Swift package depending only on the `QualiaKit` domain. Its local fixture path runs actual Core ML inference and returns `QualiaObservation`. It does not replace `QualiaBert` or migrate the current Russian model.

```swift
import QualiaKit
import QualiaCoreML

let analyzer = try await CoreMLQualiaAnalyzer(
    source: FileQualiaModelSource(directory: installedContractDirectory),
    configuration: .init(computeUnits: .cpuOnly)
)
let input = try QualiaInput(
    id: QualiaInputID(rawValue: "paragraph-1"),
    text: "quiet storm rises",
    language: QualiaLanguage(rawValue: "en")
)
let observation = try await analyzer.analyze(input)
```

`installedContractDirectory` contains `manifest.json`, the declared vocabulary and model. `BundledQualiaModelSource(bundle:subdirectory:)` resolves the same contract relative to `bundle.resourceURL`. Official sources perform no network requests. Caller-provided sources must resolve local URLs; remote URLs and escaping relative asset paths are rejected.

For this preview, add the checked-out `Packages/QualiaCoreML` directory as a local package dependency and select its `QualiaCoreML` product. It depends on the root QualiaKit package via `../..`. The root package manifest is unchanged; the new product is not yet exported by the repository's root package URL.

## Decisions (2026-09-12)

### Q-0004-001 — Stage boundary

This stage implements the new runtime, schema extension, public synthetic models, independent reference fixtures, and CI. The current manifest, its unresolved evidence, mapping, golden corpus, protected assets and legacy runtime remain unchanged. Current-model migration and removal of `QualiaBert` require the approvals and parity in rollout steps 4–7. This stage does **not** complete all of spec 0004. No dependency on full completion of 0010 is introduced.

### Q-0004-002 — Compatible v1 extension and readiness

The base document remains [model-contract-v1](../Models/current/manifest.schema.json). Its field meanings are preserved: notably `outputs.kind` remains a status/value/evidence object, and `outputs.classLabel` is a **type**, not a feature name. An optional top-level `runtime` object adds the [execution profile](../Models/Runtime/execution.schema.json). Existing audit documents without it remain valid schema v1 documents.

The fixture verifier checks the full base JSON Schema, cross-field evidence consistency, then the extension schema. Swift exposes a **read-only decoding projection**, not a lossy manifest writer or general JSON Schema interpreter. Initialization separately checks the executable subset, verified task/tokenizer/output/mapping/provenance, an open consistent gate, assets and `MLModelDescription`. Unknown execution evidence or a missing execution extension fails before compilation; no assumptions are imported from the legacy wrapper. Extra documentation fields may be ignored. New required execution behavior needs a new execution profile version; incompatible changes to existing field structure/meaning need a new schema version.

Changing model/vocabulary/preprocessing/mapping/transform/fixtures requires a new corresponding contract version even when schema v1 remains compatible. `observation.analyzer.identifier` is the declared model identifier and `observation.analyzer.version` is the contract version, which pins the whole adapter. The analyzer and diagnostics also expose the declared model version.

### Q-0004-003 — Supported execution profile 1

| Area | Supported | Rejected in this stage |
|---|---|---|
| Model assets | Local `.mlmodel`; locally pinned `.mlmodelc` with verified source artifact | Network URLs, `.mlpackage`, unpinned compiled directories |
| Tokenizer | `qualia-ascii-whitespace-v1`, immutable UTF-8 line vocabulary | BERT/WordPiece/SentencePiece or guessed training equivalence |
| Template | Verified `singleText`, exact `[CLS] text [SEP]` | Pair/context and formatted templates |
| Tensors | Fixed `[N]` or `[1,N]`, `Int32`, `Float32`, `Double`; 3 ≤ N ≤ 4096 | Flexible shapes, other dtypes, implicit extra inputs |
| Roles | Exactly one token-ID feature; optional mask and single-text token-type features, all named in manifest | Guessed feature names, repeated/unknown roles |
| Outputs | Declared `Dictionary<String,Double>` scores and named String class label; explicit complete raw-label set | Score tensors, sequences, integer dictionary keys, extra declared outputs |
| Mapping | One verified raw class → one distinct semantic signal | Dimensions, aggregation, missing/duplicate/raw-label signal identifiers |
| Confidence | Explicit `unavailable` → `nil` | Implicit score/1; other policies until source and meaning are supported |

All declared input features are emitted. `inputs.*.required` describes Core ML optionality and must match `MLModelDescription`; it does not ask the builder to omit a tensor. `tokenTypeIDs` are zeros under this single-text contract. Both models with and without that feature are tested.

Tokenizer rules: split only at scalar U+0020 or U+0009…U+000D; optionally lowercase only ASCII A…Z; preserve all other Unicode scalars and punctuation. There is no Unicode normalization. Vocabulary lookup, duplicate detection and special-token validation compare exact UTF-8 bytes; canonically equivalent spellings can have distinct IDs. Vocabulary line index is the token ID; one trailing newline is allowed, empty/duplicate entries and CRLF are rejected. Unknown words use the declared UNK ID. Add the declared CLS/SEP IDs, truncate content on the right to N−2, preserve terminal SEP, and pad on the right to N. Mask is 1 for content/special tokens and 0 for padding. The contract is a deliberately small reference tokenizer, not a claim of training parity for any production model.

### Q-0004-004 — Transforms and confidence

| Verified output kind | Classification | Transform |
|---|---|---|
| logits | exclusive | stable softmax |
| logits | independent | stable sigmoid |
| mutually-exclusive-probabilities | exclusive | none |
| independent-probabilities | independent | none |

Every class must occur exactly once. NaN, Infinity, out-of-range probabilities, unknown or missing labels fail. Exclusive distributions must sum to 1 within 1e-5; this check never rescales values. Only the final conversion into the domain's `Float` can round them. Confidence remains `nil` for every signal; these fixtures do not satisfy a heartbeat policy's confidence gate by inventing certainty.

### Q-0004-005 — Isolation, cancellation and asset lifetime

One actor owns one `MLModel` and all Core ML feature objects. Loading, tokenization, preparation, the **synchronous** `prediction(from:options:)`, validation and mapping run outside MainActor. The isolated load/analyze methods have no `await`; at most one prediction executes at a time per analyzer instance. This invariant is tested with concurrent calls through the actual public API, per-request output checks and instrumentation around real Core ML prediction. Merely wrapping an async API in an actor would not establish the same invariant; see [Swift concurrency documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/).

Cancellation is checked before preparation, before prediction, after prediction and before return, including initialization. Synchronous Core ML inference cannot be interrupted midway; cancellation discards its result afterward and remains `CancellationError`. Queued canceled calls do not prepare input or predict. No `MLMultiArray` is shared or reused between calls.

Verified source bytes are copied into a private snapshot before compilation/loading. Compiled output is retained until the worker is released, so deleting or changing original installed files does not affect an already initialized analyzer. New initialization rechecks the installed assets. Errors expose fixed typed reasons rather than paths, text, tokens or underlying framework errors.

### Q-0004-006 — Compiled identity is local

For `.mlmodel`, SHA-256 identifies the source file bytes and must agree with `model.componentSha256`. For `.mlmodelc`, `runtime.model.files` is the **complete relative-path → file SHA-256 inventory** of this local compiled directory. Missing/changed/extra files and symlinks fail. There is no universal compiled-directory digest.

`runtime.compiledFrom` is mandatory: it names a separately checksum-verified source `.mlmodel`, the compiler identity and evidence of the build relationship. This relation is a declared local build record, **not cryptographic proof that the compiler produced those bytes**. Compiled inventories must be regenerated for a different compiler/install artifact; portability across Xcode/OS versions remains open. Public CI compiles source fixtures locally instead of committing `.mlmodelc`.

### Q-0004-007 — Preserve the audited root build contract

Spec 0001's checksum closure includes the **whole root `Package.swift`** and the original CI workflow. Therefore adding even an unrelated root target invalidates that audit evidence. Stage 1 lives in `Packages/QualiaCoreML`, with its own manifest/test target and additive CI workflow. It consumes only public `QualiaKit` domain interfaces. The root package, original tests/workflow and all current-model evidence remain byte-identical. Publishing a root-exported product or changing the audited build contract needs an explicit evidence-maintenance decision in a later stage; no audit checks are disabled or rewritten here.

## Evidence and remaining work

The [fixture model card](../Tools/CoreMLFixtures/MODEL_CARD.md) explains provenance and limitations. Normal CI runs `CoreMLRuntimeTests` without protected assets or skips, checks fixture schemas/identities/references, builds `QualiaCoreML` with strict concurrency and builds its iOS Simulator scheme.

```sh
swift build --package-path Packages/QualiaCoreML
swift test --package-path Packages/QualiaCoreML --filter CoreMLRuntimeTests
python3 Tools/CoreMLFixtures/verify.py
swift build --package-path Packages/QualiaCoreML --target QualiaCoreML -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Diagnostics report model/contract versions, source kind, compute units, phase durations and token/truncation counts. They contain no text or token IDs. CPU-only is the explicit default; callers can select CPU+GPU or all compute units, with parity measured separately for each real deployment.

Remaining spec work includes the approved current-model adapter and exact protected-model parity; additional tokenizer/template/output/mapping profiles; production model cards, performance/memory/energy measurements on physical devices; and application migration/removal of the legacy runtime. These are not implied by passing synthetic fixture tests.
