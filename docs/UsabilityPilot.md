# External quick-start pilot

Status: pending external participant. Automated consumer builds verify API access
and exact command behavior; they do not establish a five-minute human integration.
This is the remaining HG-0014-001 / QK-DX-014 evidence before the 1.0 API freeze.

Use a developer who has not read this implementation. Give them the README, a
fresh app project, the selected package revision and a compatible iPhone for a
physical effect (or explicitly select a command-only path). Let them choose the
preview or narrative setup; do not silently provide model assets for a path that
requires them. Observe without explaining internal source.

Record the following in a new dated pilot record, keeping personal details minimal:

| Field | Required observation |
| --- | --- |
| Revision and selected path | Exact commit and README/guide version |
| Participant profile | iOS/Swift experience, prior QualiaKit familiarity, source exposure |
| Environment | Toolchain, OS, physical device or explicit command-only renderer |
| Elapsed time | Package setup start to first documented response/effect; pauses explained |
| Blockers | Instructions or errors that prevented progress and assistance supplied |
| First result | What appeared or was felt; analyzer and policy the participant identified |
| Notes and decision | Confusing terms, missing recovery steps, reviewer's pass/fail and rationale |

Do not count an author, assistant, simulator sensation or fabricated timings as
this pilot. Record failure as useful feedback and revise the quick start before
repeating with a new fresh participant. Preserve earlier attempts. This pending
pilot does not prevent preparing and reviewing the implementation PR.
