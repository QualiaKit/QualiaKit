# Public API reference

The conceptual guides apply to QualiaKit, QualiaTesting and the optional
QualiaCoreML package. The root Qualia and QualiaBert legacy products remain outside
the 2.0 documentation audit; their checksum-pinned source is unchanged.

Build the API reference with the installed Xcode toolchain:

```sh
python3 Tools/DeveloperExperience/build_docs.py --output /private/tmp/qualia-docs
```

The builder exports public symbol graphs, checks every public symbol has a
reference route and a documented owning contract, and runs DocC with warnings as
errors. It generates per-type reference extensions from source documentation and
curated type and layer contracts. Coverage distinguishes source-commented symbols from
members inheriting an owning contract; it does not pretend every property has a
hand-written source comment. Synthesized conformances are excluded.

Each generated symbol page includes its exact compiler-derived declaration and
availability. Guides specify isolation, failures, capabilities and privacy for
each layer. The audit fails for an unrecognized public layer or missing conceptual
guide. New entry points must update their owning contract and relevant consumer
examples. DocC archives and the machine-readable audit are build artifacts.

- Sessions and preparation: [SessionsAndContext](SessionsAndContext.md)
- Analyzer contracts: [ChoosingAnAnalyzer](ChoosingAnAnalyzer.md)
- Model assets and tensor validation: [UsingCoreMLModels](UsingCoreMLModels.md)
- State and policy: [Architecture](Architecture.md), [CreatingReactionPolicies](CreatingReactionPolicies.md)
- Rendering and patterns: [BuildingHapticPatterns](BuildingHapticPatterns.md), [Accessibility](Accessibility.md)
- Diagnostics and redaction: [PrivacyAndDataFlow](PrivacyAndDataFlow.md)
- Public test tools: [TestingYourIntegration](TestingYourIntegration.md)

The packaged QualiaKit DocC catalog contains these conceptual guides. The build
adds all three modules' symbol reference pages into their respective archives.
