# Actual RuBERT on iPhone 17 Pro — 2026-10-21

Physical device: iPhone 17 Pro (`iPhone18,1`), iOS 26.6 (23G71). Local signed
Release build; no model weights or vocabulary are included in this evidence.
The source was identified by matching all 201 retained float16 parameter tensors
and the vocabulary; see [source recovery](../../../Documentation/RussianModelEvaluation.md).

## Completed five-minute run

`full-run.json`, `full-build.json` and `full-summary.json` bind the raw measurements
to the exact measured app source and model-asset manifest. No runtime errors or
scene interruptions occurred in this run. There were 35 source-parity probes per
compute mode, followed by three text lengths, each with five warmups and 30
samples. All input tensors have fixed length 128; the longest input is truncated.

| Measurement | CPU-only | Core ML all |
| --- | ---: | ---: |
| Source argmax agreement | 35/35 | 35/35 |
| Exact tokenizer matches | 35/35 | 35/35 |
| Maximum raw-logit difference from source | 0.0378504 | 0.0167110 |
| Maximum softmax difference from source | 0.0145973 | 0.0056843 |
| Short input p95, ms | 9.118 | 4.614 |
| Medium input p95, ms | 9.295 | 4.867 |
| Long/truncated input p95, ms | 10.118 | 5.718 |
| Initialization incl. inventory/tokenizer/load, ms | 587.5 | 3268.6 |
| Process physical footprint sampled after baseline, MiB | 45.5 | 275.9 |

The `all` mode ran for **300.020 seconds**, completing **2,867 actual analyses**
at up to 10 Hz with one request in flight. Sustained end-to-end p95 was
**14.361 ms**, sampled peak process physical footprint **275.876 MiB**, and
process CPU delta **13.695 seconds**. Every thermal sample was `nominal` (0).
The warmed tight-loop baseline and spaced sustained workload are distinct tests;
their percentiles should not be treated as the same workload. CPU-only footprint
is a process accounting value and does not include all mapped weight bytes as
resident private memory; the compiled source model is about 339 MiB on disk.

`all` permits Core ML to choose compute backends. These data do not prove which
accelerator executed each operation, measure watts/joules/battery drain, establish
population UX quality or qualify the model for narrative suspense/threat/impact.
The 35 diagnostic cases are not an independently annotated accuracy dataset.

## Final packaging check

A later packaging-only adjustment makes the optional resource phase work when the
normal Release build does not define `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, and
declares its output for Xcode's script sandbox. The full-run and final-build source
inventories differ only in the Xcode project file; all Swift sources and private
model/reference assets are identical. The normal simulator build passed and its
product contains no private Russian model. `final-build.json` describes the
installed final build. A separate quick run checks its actual device inference;
its raw report and summary are stored alongside the full run rather than rewriting
or rebinding the older evidence. The quick run intentionally omits sustained load.

`interrupted-pilot.json` is excluded from results. It records an inactive-scene
transition during the first automatic launch; the user reported leaving the app
open. Automation was then changed to wait for one second of active state before
starting. The pilot has no retained complete build attestation and is diagnostic
history only.

## Reproduce the summary

```sh
python3 Tools/DeviceEvaluation/summarize_russian.py \
  ReleaseEvidence/spec-0013/2026-10-21-rubert-iphone17pro/full-run.json \
  --build ReleaseEvidence/spec-0013/2026-10-21-rubert-iphone17pro/full-build.json \
  --reference Evaluation/reports/rusentiment-source-v1/reference.json \
  --output /private/tmp/new-rubert-summary.json
```

Outputs are measurements, not an aggregate acceptance score. Labels remain
empirically inferred; especially `LABEL_3 = skip` has weaker evidence and no
confirmed author mapping. Historical protected contracts and original haptic
v1 evidence remain unchanged.

Final installed quick run: both modes again matched all 35 source argmax labels
and input tensor sets. `all` p95 across the three lengths was 4.436–5.555 ms;
CPU-only 9.289–10.243 ms. No errors. See `quick-run.json` and `quick-summary.json`.
