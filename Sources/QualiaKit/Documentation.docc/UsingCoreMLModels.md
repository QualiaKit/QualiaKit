# Using Core ML models

QualiaCoreML is an optional product of the root QualiaKit package. Add
`https://github.com/QualiaKit/QualiaKit.git` in Xcode, choose **Exact Version**
`0.1.0-dev.1`, and select both `QualiaKit` and `QualiaCoreML` for the application.
For local development, add the repository root once. The legacy nested package
at `Packages/QualiaCoreML` remains available for existing local consumers; do not
add both layouts to the same application.

This development tag supports integration testing. It is not a qualified beta
or stable release; see [release status](https://github.com/QualiaKit/QualiaKit/blob/0.1.0-dev.1/docs/release/README.md).

## App-owned models

Using QualiaKit does not require publishing a model. An application can own its
weights, tokenizer and training data separately from the public package. For a
supported BERT classifier, use the library's `BertQualiaAnalyzer`; changing models
does not require a new application-specific Swift analyzer. Supply the analyzer through `QualiaAnalyzing` to
`QualiaSession.configured(analyzer:renderer:configuration:)`; the library receives
observations through that interface and has no dependency on the private assets.
The library adapter loads resources from the application's bundle or an explicit local
directory, not from QualiaKit's package resources. This keeps the public package
usable and testable without access to the application's model.

`BertQualiaAnalyzer` accepts standard BERT WordPiece sequence classifiers exported
to Core ML, with cased or uncased preprocessing, single text or context/text
pairs, configurable tensor names and ordered label mappings. The external
manifest selects the model, vocabulary, input shapes and output interpretation.

<!-- snippet: Examples/DeveloperExperience/Sources/QualiaExamples/BertModel.swift#bert-model -->
```swift
import Foundation
import QualiaCoreML

public func makeBertAnalyzer(modelDirectory: URL) async throws -> BertQualiaAnalyzer {
    try await BertQualiaAnalyzer(
        source: FileQualiaModelSource(directory: modelDirectory),
        configuration: .init(computeUnits: .cpuOnly)
    )
}
```

Pass this analyzer to `QualiaSession.configured` with a compatible policy, or
call `analyze` directly. For application bundle resources, use
`BundledQualiaModelSource` with the same manifest. The library has no model name,
private file path, trained weights or application label mapping built in.

[BERT model preparation and supported contracts](https://github.com/QualiaKit/QualiaKit/blob/0.1.0-dev.1/Documentation/BertRuntime.md)
describe the local preparation tool and tests. Core ML conversion happens before
runtime use; raw PyTorch weights, SentencePiece/BPE tokenizers, token tagging,
question answering and bare encoders do not share this classification contract.
An incompatible model fails explicitly. The original `CoreMLQualiaAnalyzer`
retains its existing ASCII/dictionary-output profile below.

## Supported Core ML profile

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
