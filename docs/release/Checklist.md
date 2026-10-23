# Release owner checklist

Copy this checklist into the evidence branch for one frozen source revision.
Unfilled fields are pending, never passing. No tag is created by implementation CI.

- [ ] Choose an unused SemVer and record legacy/new-runtime migration decision.
- [ ] Freeze clean source SHA/tree; add the versioned changelog and migration notes
  **before** freezing. Regenerate every record if code changes afterward.
- [ ] Pass minimum/current builds, strict concurrency, unit/fixture/protected-model
  parity, package resolution, examples, DocC, coverage and formatting checks.
- [ ] Review compiler API diff against the previous reviewed baseline; attach both
  inventories, diff and migration notes. Approve breaks explicitly; stable breaks
  need a new major version. Review iOS conditional API as well as macOS export.
- [ ] Verify privacy data flow, example manifest, feedback schema, current private
  security channel, support owner and tag/environment protection configuration.
- [ ] Bind model/manifest/policy identities and all raw artifacts by checksum.
- [ ] Complete author-app pilot/shadow comparison; obtain one external use case
  for beta or three independent teams/two domains for stable.
- [ ] Resolve repeated critical DX issues; complete stable API freeze if applicable.
- [ ] Pass every applicable model/narrative qualification track.

## Physical gates — fresh candidate, no simulator substitution

**HG-0015-002, model cost:** record physical iPhone and OS, build configuration,
model/component/vocabulary hashes and compute policy. Measure model bytes, cold
load, sample count, tokenization and inference p50/p95, peak memory and runtime
overhead. Describe warm-up, repetitions, sustained duration and background load.
Record measured energy (joules, mWh or battery percentage-point delta with method
and duration) and thermal observations; CPU time alone is insufficient. Keep raw
Instruments/export artifacts and their hashes. Reviewer interprets noise/limits.

**HG-0015-003, renderer:** provide device/OS matrix and ordered scenario notes for
accent over ambient loop, interruption, engine reset, background/return, rapid
replacement and long loops. Include energy/thermal observations and all failures.
Do not count expected planned commands as successful physical playback.

**HG-0015-004, heartbeat:** name reviewers, configuration version and candidate
parameters, scripted inputs, recognizability/comfort, calibration decision and
stop behavior. Include tactile judgments and device matrix; preserve rejected
profiles. Re-run with the documented accessibility settings.

**HG-0015-005, flagship:** run the current SwiftUI example on supported physical
iPhone. Bind source and example revision/build configuration; follow documented
SentimentPreview/LivingStory steps. Record effect, inactivity/background/reset,
unsupported/disabled haptics and accessibility behavior, including Reduce Motion.

**HG-0015-001, approval:** only after the above, the product owner records identity,
checklist, pilot/support/privacy/device references, unresolved risks and rationale.
An “accepted with exceptions” iteration is not a universal passing release gate.

- [ ] Run strict candidate validation and archive its output and bundle checksum.
- [ ] Review candidate evidence branch commit and workflow results.
- [ ] Owner authorizes publication; create an immutable tag at the exact source
  SHA, attach the validated bundle/DocC and publish limitations/migration notes.
- [ ] Announce only substantiated scope; monitor public/consented issues, without SDK telemetry.
