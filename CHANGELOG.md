# Changelog

## Unreleased

No additional changes recorded.

## 0.1.0-dev.1 — 2026-10-28

Development snapshot for application integration, not a qualified beta or stable
release. Use an exact version requirement because higher legacy tags exist.

- Export `QualiaCoreML` from the root repository package, alongside `QualiaKit`,
  so applications can resolve both products from one tagged dependency.
- Add a reusable `BertQualiaAnalyzer` for compatible Core ML BERT sequence
  classifiers, with external tokenizer assets, context and label mappings.
- Keep private models and research outside Git; public fixtures contain only
  synthetic arithmetic. Model quality and physical iPhone 11 cost remain unqualified.
- Update public examples to use the root product. Preserve the previous legacy
  model build attestation and record the Xcode 27.1 verification failure without
  changing golden outputs or calibration; full release parity remains pending.

### New runtime preview

- Stateful `QualiaKit`, public `QualiaTesting` doubles, and the separate local
  `QualiaCoreML` adapter support explicit language, bounded context, cancellation,
  owned haptic playback and redacted diagnostics.
- Compiled SentimentPreview and scripted LivingStory examples, SwiftUI lifecycle
  guidance and compiler-derived DocC cover the public integration path.
- Release tooling adds exact-source evidence checks, API inventories, atomic
  bundles, governance and an opt-in pilot feedback/shadow comparison example.

### Migration and release status

This is a **development snapshot**, not a new stable version. “Runtime 2.0” is an architecture
name. Existing repository tags `1.0.0` through `3.0.0` belong to the older API and
remain immutable. The proposed new-runtime version is `0.1.0-beta.1`, pending
owner approval and all beta gates. Pin `0.1.0-dev.1` exactly; do not use a broad
version range that can resolve to an old tag. See [version policy](docs/release/README.md).

The old `Qualia`/`QualiaBert` products remain available, but their call sites are
not source-compatible with the session API. Follow the
[migration guide](docs/MigrationBefore1_0.md): create one retained session, submit
accepted fragments with unique IDs, explicit language and bounded context, handle
typed failures, and await suspend/reset at lifecycle boundaries. Legacy model
transforms and golden fixtures remain frozen. No production narrative model is
bundled. Model weights and vocabulary remain outside the source distribution.

## Legacy history

Earlier releases are recorded in the repository's immutable tags and
[GitHub release history](https://github.com/QualiaKit/QualiaKit/releases).
This changelog does not retroactively reinterpret those versions as the new runtime.
