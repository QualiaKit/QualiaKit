# Using Core ML models

QualiaCoreML is a separate Swift package at `Packages/QualiaCoreML`. In a checkout,
add that directory as a local package and select its QualiaCoreML product alongside
QualiaKit. The root remote package does not expose this optional product. A nested
package cannot be selected merely by adding the repository URL a second time.
The external consumer package demonstrates the actual local dependency layout.

Supply a reviewed manifest, tokenizer assets and model files in an app resource
directory. The manifest must match tensor names/shapes/types, tokenizer behavior,
outputs, capabilities and the SHA-256 inventory. Files stay local; the runtime
validates and snapshots them before compilation/loading. It does not download a
model, execute conversion scripts or guess label semantics.

<!-- snippet: Examples/DeveloperExperience/Sources/QualiaExamples/ModelSession.swift#model-session -->
```swift
import Foundation
import QualiaKit
import QualiaCoreML

@MainActor
public func makeNarrativeSession(bundle: Bundle, subdirectory: String) async throws -> QualiaSession {
    let analyzer = try await CoreMLQualiaAnalyzer(source: BundledQualiaModelSource(
        bundle: bundle, subdirectory: subdirectory
    ))
    return try await QualiaSession.horrorNarrative(
        analyzer: analyzer, renderer: CoreHapticRenderer(),
        language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
        context: .init(maximumFragments: 0, maximumCharacters: 4_000)
    )
}
```

The directory argument is relative to the bundle's resources. Construction can
fail for a missing asset, unsafe path, checksum mismatch, incompatible manifest
or unsupported model contract. The session factory then validates narrative
capabilities and hardware. The function is compile-tested without a private model;
a real narrative setup additionally requires reviewed model assets. The example
uses no retained generic history; increase it only when the analyzer accepts context.

No production narrative model is distributed here. The recovered RuBERT model is
Russian sentiment with an empirical label interpretation; it is not qualified as
a suspense/threat analyzer and is not a drop-in asset for this narrative factory.
The tiny public Core ML fixture validates runtime arithmetic, not language quality.

Record model origin, license and redistribution rights separately from the code's
MIT license. Do not commit private weights or vocabulary. Consult the existing
[manifest contract](https://github.com/QualiaKit/QualiaKit/blob/main/Documentation/CoreMLRuntime.md)
and [model card](https://github.com/QualiaKit/QualiaKit/blob/main/Models/current/MODEL_CARD.md).
<doc:PrivacyAndDataFlow> covers text and asset boundaries;
<doc:Performance> explains which measurements are comparable.
