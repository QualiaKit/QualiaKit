# Russian source recovery, 2026-10-21

`identity.json` verifies the pinned local Core ML package against the user's
identified source checkpoint. All 201 retained parameter tensors are exact after
float16 rounding. Source vocabulary matches byte for byte. `reference.json` is
independent Transformers CPU inference; `coreml.json` is CPU Core ML inference
through the unchanged independent audit helper. `comparison.json` retains every
case and empirical label hypotheses. `tokenizer-boundaries.json` adds ten Unicode
cases checked against the standalone Swift lab tokenizer (45 exact checks total).

These assistant-authored diagnostic probes are not a semantic accuracy dataset.
The old checksum-pinned model contract and audit remain unchanged. See
[method, limitations and reproduction](../../../Documentation/RussianModelEvaluation.md).

A first physical attempt was interrupted during an inactive scene transition.
The lab now waits for one second of active application state before an automated
run. It still cancels on scene deactivation once measurements have started. Phase
and progress are saved for diagnosis. The interrupted attempt is not counted as a
successful measurement.
