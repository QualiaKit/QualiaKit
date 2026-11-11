# Compatibility and traceability

| Surface | Build contract | Claim/evidence boundary |
| --- | --- | --- |
| QualiaKit / QualiaTesting | Swift tools 5.9 manifest, iOS 16+, macOS 13+; CI Xcode 16.4 and 26.6 | macOS supports analysis/testing; do not promise iPhone haptics there |
| QualiaCoreML | Optional root-package product; same minimum | Exact development tag `0.1.0-dev.1`; nested local package retained for compatibility. Follow the [installation guide](../UsingCoreMLModels.md) |
| QualiaExample app | Xcode 26.6+ | SentimentPreview and scripted LivingStory build; physical flagship gate is per candidate |
| Physical history | iPhone 17 Pro / iOS 26.6, October 21, 2026 | Historical device iteration; not a general device/OS matrix |
| Legacy Qualia / QualiaBert | Retained source products and immutable old tags | Frozen current-model audit; new runtime is a different integration contract |

The package manifests retain Swift tools version 5.9. Current CI validates Xcode
16.4 and 26.6; Swift 5.9 / Xcode 15.2 is no longer continuously verified after
[GitHub retired macOS 14 runners](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/).
Use a CI-validated toolchain for new integrations. Deployment targets remain
iOS 16 and macOS 13.

| Analyzer/model | Version and capabilities | Distribution / evaluation |
| --- | --- | --- |
| AppleSentimentAnalyzer | OS implementation; English valence, single paragraph | OS supplied, no model download; no narrative or historical-context claim |
| Current local RuBERT audit | `rub-sentiment-coreml-local-audit`, manifest schema 1; asset version/checksums in [immutable manifest](../../Models/current/manifest.json) | Russian sentiment; private weights/vocabulary; no redistribution grant |
| Core ML execution contract | Independently versioned [runtime schema](../../Models/Runtime/execution.schema.json) | Contract validation is not model quality qualification |
| LivingStory fixture | `example.scripted-story`, version 1 | Authored observations; no inference or semantic accuracy claim |

The old audit manifest preserves what was known at its capture date. Historical
research records are maintained separately from the library. Model-card/license
review is mandatory for any newly distributed asset.

Release candidates record the full Git revision/tree, SHA-256 of every tracked
file, model package/vocabulary identities and each policy/configuration source
hash. Source hashes are exact policy revisions, not an assertion that policy
semantics follow package SemVer. Human device records also name the configuration
and parameters used. API version, manifest schema, model version and policy
revision are independent. Do not infer one from another.
