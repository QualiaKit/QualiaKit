# Report restoration — 2026-10-21

The user supplied `8B76AC85-B639-41F0-81E4-5BCEF8F76048.json` from the physical
iPhone 17 Pro. `user-interrupted-run.json` preserves those bytes unchanged;
`interrupted-build.json` is the matching previously installed build attestation.
The report began at 10:31:15 UTC and contains three baseline repetitions, public
arithmetic Core ML measurements and eleven passed technical-check flags. Its
automatic status is interrupted, with no sustained result or human assessments.
It is not a RuBERT run and cannot replace the separate successful
[RuBERT evidence](../2026-10-21-rubert-iphone17pro/README.md).

The report contains no inactive-scene metadata. The restoration error says only
that the app found an unfinished run after a process restart; it does not diagnose
a crash, memory termination, user dismissal or scene transition. The cause of that
termination remains unknown. The last saved haptic check had passed, but the old
report has no explicit run mode/phase, so a precise termination point is not proven.

## Confirmed persistence bug and repair

On launch, `DeviceEvaluationModel.start()` decoded the saved report then called
`save()`. That method replaced the decoded command trace with the newly created
renderer’s empty records. The attached file therefore has no command trace even
though its haptic checks had saved passed flags. Missing raw commands cannot be
reconstructed from those flags.

The fix restores the trace into the renderer before the next snapshot; this copies
history without executing effects. New general runs also persist their quick/full
mode and stage before entering that stage. The summary tool now treats an empty
renderer trace as an explicit blocker.

`check_restoration.py` reproduced the command-loss assertion on the previous
simulator build. On the fixed build, all six launches passed: two each for a
running automatic report, a completed report with ratings, and a running Russian
report. Command history, completed ratings, run identity and the per-run archive
survived; interrupted states changed once, without duplicate errors. These fixtures
are synthetic software checks, not physical haptic evidence. Disposable simulators
were removed. All 26 evaluation-tool unit tests passed, including rejection of a
missing trace in an otherwise complete report.

`fixed-build.json` and `simulator-build.json` bind the new builds. The only changed
compiled input since `interrupted-build.json` is `DeviceEvaluationModel.swift`;
the RuBERT model manifest and assets are identical. Both Release builds succeeded.
The fixed build was installed on iPhoneee. The first quick launch was refused
because the device was locked. After the user unlocked it, the quick run completed
with all eleven technical checks passed and no errors. `quick-run.json` contains
all sixteen successful renderer commands. The app was then terminated and opened
without automation arguments; `reopened-run.json` is semantically identical to the
entire preceding report, including its run ID, command trace and completed status.
The app remains idle and ready for tactile ratings. `quick-summary.json` retains
the missing sustained and human-check blockers instead of declaring suite success.

Next physical step: rate A/B/C, actual background behavior and Reduce Motion in
the open app. A quick run omits
the general suite’s sustained stage and does not qualify as a complete device
suite. The reason the supplied general run ended still requires separate evidence.
