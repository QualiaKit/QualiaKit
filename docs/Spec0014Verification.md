# Spec 0014 implementation evidence

This record covers developer documentation and public examples. It does not
replace the external onboarding gate or requalify any semantic model.
The implementation depends on the spec 0013 public testing tools.

## Requirement mapping

| Requirement | Implementation and evidence |
| --- | --- |
| QK-DX-001 | README and Getting Started use the public sentiment factory. The external package compiles that exact source. A scripted exact-command test provides a deterministic first-result check; human first-effect timing remains pending. |
| QK-DX-002 | DocC builds for QualiaKit, QualiaTesting and QualiaCoreML audit every exported public symbol route, with source comments and curated type/layer reference extensions. See [API reference](APIReference.md) for scope and coverage interpretation. |
| QK-DX-003 | Example review: authored observations drive the real reducer/policy; no copied classifier, threshold mapping or heartbeat generator. |
| QK-DX-004 | External QualiaSessionHarness test verifies exact start, replacement, accent and owned stop descriptors. |
| QK-DX-005 | Eight Markdown snippets are source-bound to compiling consumer targets; CI checks drift and compiles on minimum/current package toolchains. |
| QK-DX-006 | README, Getting Started and analyzer guide explicitly distinguish English valence, authored narrative fixtures and real narrative inference. |
| QK-DX-007 | Conceptual and generated reference pages cover isolation, failure handling, platform availability, capability validation and privacy. Compiler declarations preserve exact actor/platform annotations. |
| QK-DX-008 | QualiaDecisionReport formats only structured redacted events, bounds retained lines and reports omissions. Tests inject sensitive host metadata and verify that it cannot appear in output. |
| QK-DX-009 | LivingStory's two authored observations exercise the real session, scene reducer, narrative policy and renderer; exact command equality verifies start/update/accent/reset-stop. The app serializes host lifecycle operations across tabs and scene changes. |
| QK-DX-010 | AnnotatedSceneAnalyzer and AuthoredAccentPolicy compile and execute in a separate Swift package using public imports. |
| QK-DX-011 | The testing guide embeds the independent literal-command test; no Core Haptics import or physical device is needed. |
| QK-DX-012 | README, pattern, testing, accessibility and performance guides distinguish command evidence from physical sensation. |
| QK-DX-013 | Getting Started links directly to privacy, model assets/licenses and accessibility. |
| QK-DX-014 | [External pilot record](UsabilityPilot.md) is prepared and explicitly pending before API freeze. |

## Local verification, 2026-10-21

Toolchain: Xcode 27.1 / Apple Swift 6.4 on an Apple Silicon Mac.

| Check | Result |
| --- | --- |
| VC-0014-001: `swift build` | Passed |
| VC-0014-002: `swift test --filter DeveloperExperienceTests` | 3 passed |
| Full root `swift test` | 327 executed, 14 explicitly skipped, 0 failures; skipped physical/private-model checks are not passes |
| External `swift test --package-path Examples/DeveloperExperience` | 4 passed, including exact LivingStory ordering and custom analyzer/policy |
| External `qualia-walkthrough` executable | Ran and printed the bounded redacted report |
| Xcode example | Debug and Release simulator builds passed; no physical sensation claim |
| Documentation verification | Source snippets, packaged catalog and local Markdown targets checked |
| DocC | All three products compiled with warnings treated as errors; public route audit: 763 QualiaKit, 101 QualiaTesting, 178 QualiaCoreML symbols |
| Existing GIF | Preserved byte-for-byte and embedded in README; SHA-256 `911012e2eb28f780143864aceeaa64045e9aaf0045c0fd472718eca1cc5cd823` |

The developer-experience workflow repeats consumer checks on Xcode 15.2 and
26.6, and builds the modern Xcode project and DocC archives on 26.6. The app's
project format requires the current toolchain; the public consumer package is
also checked against the minimum supported Swift toolchain. CI artifacts include
the compiler-derived coverage audit and browsable documentation archives.

AC-0014-002 (device-free exact command testing) and AC-0014-003 (honest preview
capabilities) have automated and documentation evidence. AC-0014-001's unfamiliar
developer / first-effect timing and HG-0014-001 remain **pending**. An author or
assistant run cannot establish those human observations. This implementation is
ready for review, with the external pilot required before the 1.0 API freeze.
