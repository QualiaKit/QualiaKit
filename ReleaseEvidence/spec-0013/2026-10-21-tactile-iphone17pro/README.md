# Tactile feedback on iPhone 17 Pro — 2026-10-21

**Current iteration accepted by the user on 2026-10-21.** After being informed of
the three unrecorded/omitted items below, the user said: “ну.. давай считать что все
окей”. `acceptance.json` records that decision against the original report hash.
No further device runs are required for this iteration's acceptance. Raw results
and the strict measurement summary remain unchanged; omitted checks are accepted
exceptions, not newly measured passes.

The device holder completed the A/B/C comparison and supplied the exported report,
adding: “все проверил, вот отчет, мне все нравится”. `user-report.json` preserves
that attachment byte-for-byte. `build.json` matches its embedded source identity.
The run began at 13:47:07 Moscow time on iPhone 17 Pro (`iPhone18,1`), iOS 26.6
(23G71), with the signed Release build.

This is the later snapshot of run `30ECE646-3524-4E4C-87F4-9418AE02FCBB`, following
the [restoration verification](../2026-10-21-restoration/README.md). Its baseline
and public Core ML results are unchanged; all sixteen original command records
remain an exact prefix of the thirty-four commands in this snapshot. There are
no recorded errors or failed renderer commands. Earlier snapshots are retained.

| Variant | Intensity scale | Initial rhythm | Acceleration | Accent | Comfort |
| --- | ---: | --- | --- | --- | --- |
| A / baseline | 0.5 | Distinct | Distinct | Distinct | Comfortable |
| B / medium | 0.75 | Distinct | Distinct | Distinct | Comfortable |
| C / strong | 1.0 | Distinct | Distinct | Distinct | Comfortable |

All eleven automatic technical checks passed. Actual scene-deactivation cleanup
also passed, and the holder recorded that vibration stopped without replay after
returning. Thus the report contains twelve passed technical-check flags. These
are observations from one holder and device using scripted narrative signals.

The initial v1 observation that A's calm rhythm was indistinguishable remains
historical evidence. The later v2 assessment rates A as distinct and comfortable;
it does not retroactively change the earlier result or establish why the two
observations differ. No production default or preferred variant was changed.

## Measurement gaps accepted for this iteration

`summary.json` retains three complete-suite blockers:

- This is a quick run; the general suite's five-minute sustained stage was omitted.
- `preferred-profile` remains `pending`. All three variants were liked, but no
  preference was selected or inferred from that statement.
- `reduce-motion` remains `pending`, with no system Reduce Motion check flag.
  The holder's general confirmation is retained separately in `user-feedback.json`;
  it does not invent the missing technical observation.

The separate [RuBERT five-minute run](../2026-10-21-rubert-iphone17pro/README.md)
remains real-model performance evidence, with a different workload and run. It is
not merged into this report. This tactile result does not establish narrative
semantic accuracy, watt/joule usage, a broader device matrix or population-level
experience quality. Spec 0013 is not marked fully validated by this attachment.
