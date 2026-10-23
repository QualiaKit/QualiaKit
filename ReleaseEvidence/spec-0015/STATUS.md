# Spec 0015 evidence status

This directory tracks release infrastructure, **not release approval**. No beta
version or tag has been created. The proposed `0.1.0-beta.1` remains unapproved.

| Evidence | State |
| --- | --- |
| Governance, privacy-safe pilot sample, API inventory, release validation/bundling | Implemented; verify the PR checks |
| Private vulnerability reporting | Enabled and verified through GitHub API on October 23, 2026; recheck at release |
| Author-app migration and real shadow pilot | Pending real app integration record |
| Independent external pilots | Pending; zero claimed |
| Exact release source / protected real-model parity | Pending frozen candidate |
| HG-0015-001 owner release approval | Pending |
| HG-0015-002 model/energy/thermal physical benchmark | Pending candidate-bound evidence; CPU time is insufficient |
| HG-0015-003 renderer matrix and long-loop energy | Pending candidate-bound evidence |
| HG-0015-004 heartbeat calibration/comfort | Historical iteration accepted; fresh candidate review pending |
| HG-0015-005 flagship SwiftUI/accessibility walkthrough | Pending current candidate |
| Stable API freeze / three teams / two external domains | Pending |
| Narrative qualification | Not included or claimed; required if scope changes |

The user's [October 21 acceptance](../spec-0013/2026-10-21-tactile-iphone17pro/acceptance.json)
remains unchanged, including its scope and three recorded exceptions. The
[evaluation card](../../Evaluation/cards/current-status.md) describes model and
tactile boundaries. These are supporting history, never automatically converted
into passing records for a new source SHA.

Implementation can be reviewed and merged while release gates remain pending.
Spec 0015's adoption/release outcome is not complete until the real pilots and
human gates exist. See the [checklist](../../docs/release/Checklist.md) for the
remaining owner/device work and [evidence format](../../docs/release/Evidence.md)
for reproducible validation.
