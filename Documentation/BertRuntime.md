# App-supplied BERT classifiers

`BertQualiaAnalyzer` in `Packages/QualiaCoreML` is a reusable implementation of
`QualiaAnalyzing`. Applications supply model assets and a manifest. They do not
implement a different analyzer for each model, and do not publish their weights
with QualiaKit. The optional product is exported by the root package; integration tag
`0.1.0-dev.1` can be selected by exact version in Xcode/SwiftPM. The nested local
package remains for existing consumers; use one dependency layout at a time.

## Supported contract

The adapter executes **BERT WordPiece sequence classifiers exported to Core ML**.
Architecture depth, embedding width, number of labels and application name are
not hardcoded. Compatible classifiers can be swapped without modifying Swift
code. This does not make arbitrary architectures or task heads interchangeable.

| Area | Supported |
| --- | --- |
| Assets | Local `.mlmodel` or `.mlpackage`; full SHA-256 inventory for packages |
| Tokenizer | Standard BERT cleaning, optional Chinese separation, cased/uncased, explicit accent stripping, greedy WordPiece |
| Special tokens | External PAD, UNK, CLS, SEP and optional MASK IDs; recognized before normalization |
| Input | Fixed `[N]` or `[1,N]`, Int32/Float32/Double; batch one; N from 3 through 4096 |
| Roles | Required token IDs; optional attention mask, segment IDs and position IDs; configurable feature names |
| Templates | `[CLS] text [SEP]` or `[CLS] context [SEP] text [SEP]` |
| Context | Caller-supplied fragments joined by the manifest separator; paired template remains paired with empty context |
| Padding/overflow | Right padding; over-limit input fails, including all special tokens; no silent truncation |
| Output | One fixed floating tensor `[K]` or `[1,K]`, Float16/Float32/Double |
| Semantics | Explicit ordered label-to-signal mapping; exclusive softmax, independent sigmoid, or already-normalized probabilities |
| Confidence | `nil`; model scores are not a separately calibrated confidence or emotion intensity |

The tokenization settings must match training. Standard Hugging Face
[BERT tokenization and classification](https://huggingface.co/docs/transformers/model_doc/bert)
are the reference; the checked examples pin transformers 4.57.1 and tokenizers
0.22.2. Unicode behavior is tested on the supported Apple toolchain; a different
Unicode version is not a blanket guarantee for every possible string.

Raw `.safetensors`/PyTorch weights need conversion before use. A bare encoder,
masked-language head, token classifier or question-answering head cannot be
interpreted as a sequence classifier. SentencePiece, BPE, custom added-token
rules, custom post-processing, dynamic shapes and additional model inputs or
outputs are rejected by this first profile. Distinct language support or semantic
classes come from the supplied model and mapping, not from the adapter itself.

## Prepare an external model directory

Use Python with coremltools 8.3.0 and numpy 2.2.6. The preparation tool reads local
model metadata; it performs no downloads, training, model conversion or inference.

```sh
python3 Tools/BertModels/prepare.py \
  --model /private/models/classifier.mlpackage \
  --tokenizer /private/models/tokenizer \
  --labels /private/models/labels.json \
  --out /private/models/prepared-v1 \
  --identifier app.example.classifier --version 1 \
  --languages en --length 128 \
  --template contextThenText --classification independent
```

The tokenizer directory contains `tokenizer.json`, `special_tokens_map.json` and
`vocab.txt` saved by a compatible Hugging Face tokenizer. The tool verifies that
the vocabulary, normalizer, pre-tokenizer, special tokens and single/pair
post-processing agree with the supported profile. Unsupported rules are not
silently discarded. Accent stripping defaults are resolved explicitly.

`labels.json` is an ordered array such as
`[{"name":"LABEL_0","signal":"example.signal"}]`. There must be exactly one
entry per output position. Use the actual training label order and meaning; do
not infer emotions from an arbitrary label number. `--probabilities` selects
already-normalized output rather than logits. `--input-roles` accepts a JSON
object for custom names, e.g. `{"pieces":"tokenIDs","mask":"attentionMask"}`.
Otherwise only conventional BERT input names are accepted. `--context-separator`
defaults to newline. Existing destinations are refused; create a new version.

The output contains `manifest.json`, `vocab.txt` and the pinned model asset. Load
that directory through `FileQualiaModelSource`, or copy those files into the
application's resources and use `BundledQualiaModelSource`. They are not library
resources. Construct `BertQualiaAnalyzer(source:)`, then pass it to
`QualiaSession.configured` or call `analyze` directly. Session policy requirements
must match the actual signals, context support and confidence the model supplies.
See the compile-checked example in `Examples/DeveloperExperience/Sources/QualiaExamples/BertModel.swift`.

## Runtime behavior

Initialization validates the manifest, hashes and complete package inventory.
Unsafe relative paths, symlinks, altered assets and extra package files fail.
Verified model bytes are copied to a private temporary directory, compiled and
loaded there. An initialized analyzer remains usable if the original files are
removed; a new analyzer revalidates the original assets.

One actor owns each model and executes synchronous inference serially, outside
MainActor. Cancellation is checked around preparation and prediction; synchronous
Core ML inference cannot be interrupted midway, so a cancelled result is discarded.
The worker's temporary files are removed when it is released. Diagnostics expose
durations, counts and hashed identity, without text or tensor values.

Malformed outputs, non-finite values and incompatible shapes throw. Exclusive
probabilities must sum to one within 1e-5; independent scores are not renormalized.
Returned observations preserve request identity and explicitly supplied language.
Missing language and unsupported language/context are errors, not neutral scenes.

## Verification

Three public synthetic arithmetic models exercise cased single text, uncased
pairs, different input names/shapes/dtypes, segment omission, position IDs,
exclusive and independent output, and both `.mlmodel` and `.mlpackage` loading.
They contain no trained weights, private vocabulary or application scenes.
Their token IDs/masks/segments come from the pinned Hugging Face tokenizer;
their expected scores come from separate analytical arithmetic.

```sh
swift test --package-path Packages/QualiaCoreML
swift build --package-path Packages/QualiaCoreML --target QualiaCoreML \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Public tests also cover cancellation, concurrent callers, source removal,
overflow, malformed contracts and corrupted package inventories. A separate
optional acceptance test reads `QUALIA_BERT_PRIVATE_DIRECTORY` and an external
`validation.json`; public CI skips it and does not need private assets. Runtime
compatibility does not qualify a model's semantic accuracy or device performance.
