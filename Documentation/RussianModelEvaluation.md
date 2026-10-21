# Recovered Russian model and local iPhone evaluation

The user's source attribution was checked on 2026-10-21. The protected
`RuBSentimentModel.mlpackage` contains the retained parameters of
[`sismetanin/rubert-ru-sentiment-rusentiment`](https://huggingface.co/sismetanin/rubert-ru-sentiment-rusentiment),
Hugging Face revision `f3d755e39a6af467a4e90b9a1c486ea1d2aa3852`.
Its cached safetensors conversion is revision
`4f372c1e9b1ae936109ff94eceab8479e0b3fbfb`, SHA-256
`c6183eff4f5697f82470e0ae338a5e6f28dc1f0220757bc08b42ce8a7776b228`.
The [source conversion PR](https://huggingface.co/sismetanin/rubert-ru-sentiment-rusentiment/discussions/1)
describes this safetensors variant. Network metadata retrieval timed out during
this audit; source attribution uses the existing named/revisioned local HF cache,
its content-addressed file hash, the user's statement and exact parameter matching.

## What was verified

- All 201 retained parameter tensors match the source checkpoint **byte for byte
  after conversion to float16**, including the five-class head. Position embeddings
  are folded to the first 128 positions; the unused source position-ID buffer is
  not a learned parameter. This verifies the retained weights, not a byte-identical
  source/converted graph or proof of historical conversion-command execution.
- The vocabulary is byte-identical (119,547 entries, SHA-256
  `78106a3d3ae8600d1ba573b967b9bb731d2c2282957cbc6e26ab20935c3da02b`).
- The graph ends in classifier linear → float16-to-float32 cast → `classify`, with
  the original `LABEL_0` … `LABEL_4` order. Despite the name `classLabel_probs`,
  values are **logits**. The lab applies stable softmax exactly once.
- CPU Core ML and source PyTorch have the same argmax on all 35 diagnostic cases.
  Maximum logit difference is 0.045662879943847656, maximum softmax difference
  0.004459761735099321. These are observed cross-framework differences, not a
  universal acceptance tolerance or a rerun of the historical pinned audit.
- The new lab tokenizer matches the source Hugging Face **slow BertTokenizer**
  configuration exactly on those 35 cases and ten additional Unicode cases.
  It lowercases, strips accents after canonical decomposition, preserves punctuation
  as tokens, handles CJK/special tokens, uses scalar-based WordPiece (100-character
  word limit), and truncates/pads to 128. The legacy tokenizer drops punctuation;
  its immutable implementation and evidence are unchanged.

Evidence: [identity and per-tensor hashes](../Evaluation/reports/rusentiment-source-v1/identity.json),
[source predictions and exact input tensors](../Evaluation/reports/rusentiment-source-v1/reference.json),
[comparison](../Evaluation/reports/rusentiment-source-v1/comparison.json).

## Label recovery is experimental

The source model card identifies the task as sentiment classification of Russian
VK posts. [RuSentiment annotation guidelines](https://github.com/text-machine-lab/rusentiment)
define negative, neutral, positive, speech act and skip categories. The checkpoint
config preserves only numeric label names. The author's
[label-order issue #5](https://github.com/sismetanin/sentiment-analysis-in-russian/issues/5)
remains open with no answer at inspection time. No author-confirmed numeric map
was found, so the historical semantic admission gate is not silently opened.

| Raw output | Empirical interpretation | Diagnostic evidence |
| --- | --- | --- |
| LABEL_0 | negative | 5/5 negative probes |
| LABEL_1 | neutral | 5/5 neutral probes |
| LABEL_2 | positive | 5/5 positive probes |
| LABEL_3 | likely skip / unclear content | 1/5 skip probes; also an overlong unknown word; weaker evidence |
| LABEL_4 | speech act | 5/5 greetings/congratulations/thanks probes |

The probes were written by the assistant before observing outputs; they are not
independent human labels or held-out accuracy data. Every result, including
counterexamples, is retained. The poetry and other skip probes often produce
neutral. A negated sentence produces positive; two suspenseful passages produce
neutral. These failures matter when deciding whether the model is useful for
book reactions. None of these outputs is renamed suspense, threat or impact.
Softmax is not calibrated confidence. The lab displays the provisional captions
alongside the original raw labels and explicitly labels the interpretation.

## Device lab

The dedicated Russian controls run actual local inference. They coexist with the
previous scripted haptic checks and public arithmetic fixture. They do not replace
`QualiaBert`, introduce a production semantic adapter or change heartbeat defaults.

- **Проанализировать текст**: type Russian text; show all five softmax values,
  actual token count, truncation and latency. Text is not sent over a network or
  added to exported reports. Inputs over 65,536 UTF-8 bytes fail explicitly.
- **Проверить модель и скорость**: separate `cpuOnly` and `all` model instances;
  verify all 35 tokenizations against the source, retain source/output differences,
  then measure three text lengths with five warmups and 30 samples per length.
  Timings separate tokenization, tensor preparation, prediction and softmax.
- **Замеры и 5 минут нагрузки**: the same checks followed by 300 seconds of real
  RuBERT inference with `all`, one request at a time, at most 10 Hz. CPU, process
  memory and thermal state are sampled every five seconds.

`all` allows Core ML to choose CPU/GPU/ANE; it does not prove execution on any
specific accelerator. All inputs have fixed tensor length 128, so extra text is
truncated. Initialization includes local inventory hashing, tokenizer construction
and loading the precompiled model; source compilation happens on the Mac and is
not misreported as on-device loading. Memory/CPU include the whole app. These are
not watts/joules or a battery-drain study. Cancellation discards the current result;
synchronous Core ML prediction cannot be interrupted midway.

Automation waits for one second of active application state before starting.
Each Russian run has a new report ID and a separate `russianStatus`. It cannot pass
the full haptic/manual gate just because model measurements finish. Original v1/v2
reports remain archived. Raw reports bind to both app-source and private-asset
manifests. An interrupted process is marked interrupted on restart.

## Reproduction

Use an isolated Python environment matching
[the captured environment](../Evaluation/reports/rusentiment-source-v1/python-environment.txt).
The audit uses local source snapshots and never executes a downloaded pickle or
custom model code. It loads safetensors into the standard Transformers BERT class.

```sh
python Tools/RuSentimentAudit/audit.py \
  --snapshot /path/to/hf/snapshot/f3d755e39a6af467a4e90b9a1c486ea1d2aa3852 \
  --safetensors /path/to/hf/snapshot/4f372c1e9b1ae936109ff94eceab8479e0b3fbfb/model.safetensors \
  --model RuBSentimentModel.mlpackage --output /private/tmp/new-rubert-audit

python3 Tools/RuSentimentAudit/prepare_device.py \
  --audit /private/tmp/new-rubert-audit --output LocalArtifacts/new-rubert-device
python3 Tools/DeviceEvaluation/run.py build \
  --build-dir /private/tmp/qualia-rubert-device-build \
  --russian-assets LocalArtifacts/new-rubert-device
python3 Tools/DeviceEvaluation/run.py install --device DEVICE_ID \
  --build-dir /private/tmp/qualia-rubert-device-build
python3 Tools/DeviceEvaluation/run.py run --device DEVICE_ID --russian
python3 Tools/DeviceEvaluation/run.py collect --device DEVICE_ID --output /private/tmp/new-rubert-run.json
python3 Tools/DeviceEvaluation/summarize_russian.py /private/tmp/new-rubert-run.json \
  --build /private/tmp/qualia-rubert-device-build/device-build.json \
  --reference /private/tmp/new-rubert-audit/reference.json --output /private/tmp/new-rubert-summary.json
```

`--russian --quick` skips sustained load and reports that omission. The dedicated
summarizer verifies raw distributions, reference predictions, softmax, deltas and
build binding; it reports measured differences without inventing a calibrated
universal numerical tolerance or semantic accuracy score.

Private model/compiled files remain under ignored `LocalArtifacts/`. Only an
explicit `--russian-assets` build copies them into the signed local lab app before
code signing. A build without that flag removes any stale private asset bundle
from its product. No model weights or vocabulary are added to Git or public CI.
This local test integration does not establish redistribution permission.
