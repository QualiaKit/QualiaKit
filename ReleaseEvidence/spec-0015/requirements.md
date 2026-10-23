# Requirement-to-evidence map

This maps implementation and pending release outcomes separately. Passing tooling
tests establish the gate's behavior, not the existence of real pilot/device data.

| Requirement | Implementation / release evidence |
| --- | --- |
| QK-REL-001 | CHANGELOG, compatibility/limitations docs; strict candidate requires versioned changelog |
| QK-REL-002 | HG-0015-002–005 required for every beta/stable candidate; physical/energy checks and rejection tests; actual records pending |
| QK-REL-003 | Compiler API baseline/current/diff, explicit hashed review/migration record; final candidate review pending |
| QK-REL-004 | Breaking API approval/migration validation and documented 0.x/legacy version policy |
| QK-REL-005 | Blocking minimum/current builds/tests/coverage/DocC/example workflow; protected real-model exact-SHA record required before release |
| QK-REL-006 | Git SHA/tree, complete tracked-file inventory, independent model/manifest/policy identities; referenced artifacts and atomic bundle checksums |
| QK-REL-007 | Model contribution validator, contribution guide and completeness/rights rejection tests; actual new model review remains human work |
| QK-REL-008 | SECURITY, SUPPORT, CONTRIBUTING, CODE_OF_CONDUCT, GOVERNANCE and templates; private reporting enabled |
| QK-REL-009 | Stable gate counts three distinct consented external teams; no real teams claimed |
| QK-REL-010 | Beta requires one external domain; stable two; no real external use cases claimed |
| QK-REL-011 | Stable contribution/integration proof or named expiring SHOULD waiver; proof pending |
| QK-REL-012 | No SDK telemetry added; external consented/public adoption ledger protocol |
| QK-REL-013 | Closed opt-in PilotFeedback schema; consumer tests assert exact keys and metadata redaction; separate text-curation protocol |
| QK-REL-014 | Narrative flag requires additional annotation/held-out/hard-negative/context/device record; no narrative capability claimed |
| QK-REL-015 | Exact-source workflow rebuilds DocC and public examples; current snapshot bound to source hashes |
| QK-REL-016 | Public API baseline, manifest schema and model/policy identities recorded independently |
| QK-REL-017 | No registry API introduced; contribution/governance policy documents prerequisite |
| QK-REL-018 | Only QK-REL-011 waiver allowed, with owner/reason/expiry; mandatory/physical waivers rejected |

AC-0015-001 and AC-0015-002 have synthetic passing/rejection tests in
`Tools/Release/test_release.py`; real beta/stable acceptance remains pending.
AC-0015-003 is exercised through the public Swift consumer in `PilotTests`.
`ReleaseAndAdoptionTests` executes the Python gate suite and asserts it has not
silently disappeared. Required commands are `swift build`,
`swift test --filter ReleaseAndAdoptionTests`, and `./scripts/release-check`.
