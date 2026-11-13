# QualiaCoreML

Optional adapters for app-owned Core ML models. Add the **root QualiaKit package**
once in Xcode and select both `QualiaKit` and `QualiaCoreML`. The nested package
is retained for SwiftPM compatibility; Xcode apps should use the root to avoid
duplicate product names. No trained weights are included or downloaded.

## Load a BERT classifier

```swift
import Foundation
import QualiaCoreML

func makeBertAnalyzer(modelDirectory: URL) async throws -> BertQualiaAnalyzer {
    try await BertQualiaAnalyzer(
        source: FileQualiaModelSource(directory: modelDirectory),
        configuration: .init(computeUnits: .cpuOnly)
    )
}
```

The directory must contain `manifest.json`, the vocabulary and the model assets.
For bundled resources, use `BundledQualiaModelSource(bundle:subdirectory:)`.
Pass the analyzer to `QualiaSession.configured` with a compatible policy, or call
`analyze` directly with a `QualiaInput` containing an explicit supported language.

## BERT manifest

[BertModelManifest.swift](Sources/QualiaCoreML/BertModelManifest.swift) defines the
version 1 decoding contract. The [synthetic single-text manifest](Tests/QualiaCoreMLTests/Resources/Bert/cased-single/manifest.json)
and [paired-text manifest](Tests/QualiaCoreMLTests/Resources/Bert/uncased-pair/manifest.json)
show complete working structures. Their tiny models test arithmetic, not language
understanding. Supply your own model's exact tensor names, tokenization settings,
training label order, semantic mappings and SHA-256 hashes.

| Area | Supported by `BertQualiaAnalyzer` |
| --- | --- |
| Model | BERT WordPiece sequence classifier exported to `.mlmodel` or `.mlpackage` |
| Vocabulary | UTF-8 `vocab.txt`, explicit special-token IDs, cased or uncased preprocessing |
| Inputs | Fixed `[N]` or `[1,N]`; Int32, Float32 or Double; N from 3 through 4096 |
| Roles | Token IDs, optional attention mask, segment IDs and position IDs |
| Templates | `[CLS] text [SEP]` or `[CLS] context [SEP] text [SEP]` |
| Overflow | Rejected, including special tokens and context; no silent truncation |
| Output | Floating tensor `[K]` or `[1,K]`, explicit ordered label-to-signal mapping |
| Transform | Exclusive softmax, independent sigmoid, or declared probabilities |
| Confidence | Unavailable (`nil`); scores are not calibrated confidence |

Tokenizer behavior must match training. Raw PyTorch weights require conversion
before runtime use. Bare encoders, masked-language heads, token classifiers,
question-answering heads, SentencePiece/BPE and dynamic shapes are unsupported.
Model language support and signal meaning come from the supplied manifest.
A narrative policy must match those signals and the available confidence;
never invent confidence to satisfy a policy gate.

## Dictionary-output adapter

`CoreMLQualiaAnalyzer` supports the older, deliberately narrow execution profile:
ASCII-whitespace tokenization, a single-text template, fixed input tensors, and
a named string class label plus a `Dictionary<String, Double>` of scores.
Use the [base manifest schema](../../Models/current/manifest.schema.json) together
with the [execution schema](../../Models/Runtime/execution.schema.json).
A [complete synthetic manifest](Tests/QualiaCoreMLTests/Resources/CoreML/exclusive-logits-v2/manifest.json)
is included with the tests. This adapter does not accept BERT manifests.

Its tokenizer optionally lowercases ASCII only, preserves other Unicode scalars,
truncates content to N−2, then appends SEP and right padding. Raw labels must map
to distinct semantic signals. Logits use stable softmax or sigmoid; declared
probabilities are validated without rescaling. Confidence remains `nil`.

## Asset and execution behavior

Initialization validates manifest compatibility, shapes, types, hashes and the
complete package inventory. Unsafe paths, symlinks, missing or altered assets
fail. Verified assets are copied to a private temporary directory before loading;
removing the original directory does not invalidate an existing analyzer.

Each analyzer serializes inference outside MainActor. Cancellation is checked
before and after synchronous Core ML prediction; a cancelled result is discarded.
Non-finite output, incompatible shapes, missing labels and invalid probabilities
throw typed errors. Exclusive probabilities must sum to one within 1e-5.
Diagnostics are opt-in and exclude source text and tensor values.

Use the [public consumer tests](../../Tests/Consumer/Tests/ConsumerTests) for
compile-checked factories. Run `swift test --package-path Packages/QualiaCoreML`
for runtime, tokenizer, lifecycle and asset-validation tests. Hardware cost and
model accuracy require separate evaluation using the actual deployment assets.
The code's MIT license grants no rights to external models or datasets.
