# QualiaKitBert v10-preview.1

An experimental English narrative classifier for trying QualiaKit on a real
iPhone. It predicts eleven content signals; the example uses suspense and threat
to drive a bounded heartbeat. It does not measure a reader's feelings.

## Try it

Clone the repository, open `Examples/QualiaExample/QualiaExample.xcodeproj`,
select your signing team and run on a compatible iPhone. QualiaKitBert is the first
tab. Choose Quiet, Suspense or Safe again, then tap **Analyze and feel**, or edit
the text. **Continue story with previous scenes** retains up to two prior accepted
fragments. **Stop** stops playback and clears context.

The runtime resources are in
[`Examples/DeveloperExperience/Sources/QualiaExamples/Resources/QualiaKitBert`](../../Examples/DeveloperExperience/Sources/QualiaExamples/Resources/QualiaKitBert).
Only the example package bundles them; the root library products remain free of
model resources. To use the model in your own application, copy the complete
resource directory including its notices and load it with `BertQualiaAnalyzer`
and `BundledQualiaModelSource`. Follow the [integration guide](../../docs/UsingCoreMLModels.md).

## Contract and behavior

| Property | Value |
| --- | --- |
| Runtime identity | `qualiakit.bert` / `v10-preview.1` |
| Language | English; the demo rejects unsupported or undetermined language |
| Base | `prajjwal1/bert-tiny`, 2 layers, hidden size 128 |
| Parameters | 4,387,339 |
| Inputs | Int32 `input_ids`, `attention_mask`, `token_type_ids`, each `[1, 128]` |
| Template | `[CLS] context [SEP] current fragment [SEP]` |
| Tokenizer | Pinned uncased BERT WordPiece, 30,522 vocabulary entries |
| Context | Up to two previous fragments in the example; 128 tokens total including special tokens |
| Overflow | Rejected; never silently truncated |
| Output | Eleven logits, independent sigmoid scores |
| Labels | threat, suspense, violence, fear, anger, joy, tenderness, sadness, mystery, relief, surprise |
| Meaning of scores | Uncalibrated classifier scores, not measured intensity or confidence |

The demo's heartbeat starts at tension 0.5 and resolves at 0.25. The existing
policy computes tension from suspense and weighted threat, with scene smoothing.
It explicitly sets `minimumSignalConfidence: 0`; no confidence is fabricated.
It uses half intensity by default and a six-second physical playback deadline.
Haptics can be disabled, Reduce Motion suppresses continuous playback, and leaving
the screen or backgrounding stops the effect. Resume requires fresh input.
Other model labels are shown for inspection but do not create invented haptic
signals. The model has no impact/shock output and this example produces no
impact/shock accents.

## Origin, training and license

The base checkpoint is pinned to
[`6f75de8b60a9f8a2fdf7b69cbd86d9e64bcb3837`](https://huggingface.co/prajjwal1/bert-tiny/blob/6f75de8b60a9f8a2fdf7b69cbd86d9e64bcb3837/README.md).
Its upstream card declares MIT and identifies Google Research BERT as the original
checkpoint source. The example includes MIT terms, upstream attribution and the
original BERT Apache 2.0 license in its
[notices](../../Examples/DeveloperExperience/Sources/QualiaExamples/Resources/QualiaKitBert/NOTICE).
QualiaKit's fine-tuning and packaging are distributed under the accompanying MIT
license; preserve the upstream notices when redistributing the model.

Local source records describe project-authored fictional scenes with no copied
third-party fiction passages. The selected v10 training used 1,013 texts: 41 with
prior user batch approval and 972 with assistant-proposed labels. Validation used
252 synthetic texts, separated by story group. Model selection used macro-F1,
then micro-F1, then loss; the label decision threshold was fixed at 0.5.
Development repeatedly examined related diagnostics; those results are not an
independent final test. The complete private research workspace and training
texts are not part of this resource contribution.

The public model is the selected v10 Core ML export with a renamed runtime
identity. Trained weights and vocabulary are unchanged. The conversion uses
reduced precision for embedding tables and retains FP32 elsewhere.
[Provenance and file hashes](provenance.json) bind the public manifest, assets,
source weights, tokenizer and base checkpoint. This is unrelated to the legacy
Russian sentiment model, which remains excluded from redistribution.

## Evaluation and limits

The historical v10 synthetic validation reported micro-F1 0.913. That is agreement
with synthetic labels, not a percentage of correctly understood stories. The
historical conversion check found no changed binary decisions over 2,668
predictions; it establishes conversion parity on those inputs, not semantic
accuracy or equivalence for all future inputs.

The new public diagnostic set contains six assistant-authored scenes. The user
delegated labeling to the assistant, so these labels have **no independent human
review**. The model, labels and 0.5 threshold were fixed before running these
probes, with no retraining or threshold tuning. On the recorded Mac run, all six
suspense decisions matched those labels. This small result does not establish
general accuracy. Exact scores and timings are in [the Mac report](mac-diagnostics.json).

Reproduce the diagnostics without private files:

```sh
swift test --package-path Examples/DeveloperExperience
swift run --package-path Examples/DeveloperExperience qualia-walkthrough --bert
```

For a physical-device check, launch the Debug example with
`--qualiakit-bert-check`. It writes `Documents/qualiakit-bert-device.json` with
fixed-scene scores, model identity, load/inference timings, process memory
snapshots and technical playback checks. Process memory is not model-only memory
or peak memory; timings from one device do not guarantee other devices' behavior.
The check does not assess tactile comfort, battery consumption or semantic accuracy.

A physical iPhone 17 Pro (iOS 26.6 / 23G71, Debug build, CPU-only inference)
completed the fixed probes and technical playback check on November 11, 2026.
Initial preparation including compilation/loading took **174.6 ms**; the median
of 30 subsequent predictions was **0.56 ms**. Whole-process memory was **30.8 MiB**
at the sample taken with the session loaded (not model-only or peak memory).
The renderer reported an active heartbeat, suspension cleared active effects,
resume stayed silent, and the standalone quiet scene produced no active effect.
These are technical observations. In a subsequent normal-demo trial, one device
holder confirmed that the rhythm was felt, comfortable, and stopped with the
Stop button. This [holder assessment](human-assessment.json) applies only to this
trial; it is not a broader comfort study. The automatic report retains its
original `humanComfort: not-assessed` field because feedback was collected later.
See the [raw device report](device-diagnostics.json) and
[build identity](device-build.json). Actual background/foreground transitions,
system Reduce Motion, battery and other device models remain unmeasured for this
build.

Independent human-reviewed stories, broader device coverage, broader comfort
assessment and energy measurements remain open. Unsupported domains, irony, subtle or long context,
negation and unfamiliar wording can produce errors. There is no learned abstain
class. Intended use is experimentation with short English fictional scenes.
Do not use scores for diagnosis, mental-state inference, people scoring or
consequential decisions about people.

Normal demo text is held only in memory. Inference is local, and the example has
no model download, account, analytics or upload path. The explicit diagnostic
mode saves only the fixed public probes' results.
