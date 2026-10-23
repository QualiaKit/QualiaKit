# Compatibility and traceability

| Surface | Build contract | Claim/evidence boundary |
| --- | --- | --- |
| QualiaKit / QualiaTesting | Swift 5.9+, iOS 16+, macOS 13+; CI Xcode 15.2 and 26.6 | macOS supports analysis/testing; do not promise iPhone haptics there |
| QualiaCoreML | Separate local package at Packages/QualiaCoreML; same minimum | Root repository URL does not expose this nested product; follow the [installation guide](../UsingCoreMLModels.md) |
| QualiaExample app | Xcode 26.6+ | SentimentPreview and scripted LivingStory build; physical flagship gate is per candidate |
| Physical history | iPhone 17 Pro / iOS 26.6, October 21, 2026 | Historical device iteration; not a general device/OS matrix |
| Legacy Qualia / QualiaBert | Retained source products and immutable old tags | Frozen current-model audit; new runtime is a different integration contract |

| Analyzer/model | Version and capabilities | Distribution / evaluation |
| --- | --- | --- |
| AppleSentimentAnalyzer | OS implementation; English valence, single paragraph | OS supplied, no model download; no narrative or historical-context claim |
| Current local RuBERT audit | `rub-sentiment-coreml-local-audit`, manifest schema 1; asset version/checksums in [immutable manifest](../../Models/current/manifest.json) | Russian sentiment; private weights/vocabulary; no redistribution grant |
| Core ML execution contract | Independently versioned [runtime schema](../../Models/Runtime/execution.schema.json) | Contract validation is not model quality qualification |
| LivingStory fixture | `example.scripted-story`, version 1 | Authored observations; no inference or semantic accuracy claim |

The old audit manifest preserves what was known at its capture date. Later source
identity recovery is recorded in [evaluation status](../../Evaluation/cards/current-status.md)
and the historical device reports; do not rewrite the audit to erase that chronology.
Model-card/license review is mandatory for any newly distributed asset.

Release candidates record the full Git revision/tree, SHA-256 of every tracked
file, model package/vocabulary identities and each policy/configuration source
hash. Source hashes are exact policy revisions, not an assertion that policy
semantics follow package SemVer. Human device records also name the configuration
and parameters used. API version, manifest schema, model version and policy
revision are independent. Do not infer one from another.
