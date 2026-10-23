# Evidence format and release automation

`./scripts/release-check` checks repository governance/privacy/link contracts. Its
success **does not mean release ready**. `--candidate` is the strict gate: missing
passes, stale source, checksum drift, absent pilots or pending device evidence fail.
No command creates tags, contacts pilots or publishes a release.

Freeze the source including its versioned changelog. Keep evidence in a separate
directory/`release-evidence` branch: records can refer to the final source SHA
without a self-referential commit hash. Do not commit them back into that source
commit. The evidence branch is reviewed and its commit recorded by CI.

```sh
./scripts/release-check --prepare /tmp/qualia-candidate/candidate.json --version 0.1.0-beta.1
python3 Tools/Release/api.py --output /tmp/qualia-candidate
```

Copy the **previous reviewed release** inventory to `api-baseline.json` in that
directory; for the first preview, the checked-in development baseline is the
starting point. Re-run `api.py --baseline <that file> --output <directory>`.
Fill the candidate's API file hashes and all evidence references. API extraction
uses compiler symbol graphs of owned public declarations and conformances; it is
not an ABI checker and does not replace review of conditional iOS API.

The generated candidate includes exact Git revision/tree, all tracked file hashes,
current private model/vocabulary identities, manifest schemas and policy hashes.
Its empty `records` and `pilots` are intentional blockers. Schema version is 1;
unknown top-level fields, duplicate JSON keys, traversal and symlink references
are rejected. All artifact paths are relative to the evidence directory.

Every entry in `records` references a JSON file as `{"path":"records/name.json",
"sha256":"<64 hex characters>"}`. That file has exactly:

```json
{
  "name": "docc-build",
  "status": "passed",
  "sourceRevision": "<40-character frozen source SHA>",
  "reviewer": "<human reviewer or CI producer>",
  "details": {
    "runURL": "<immutable CI run/job URL>",
    "toolchain": "<exact Swift/Xcode/SDK>",
    "command": "<executed command>",
    "conclusion": "success"
  },
  "artifacts": [{"path": "raw/docc-log.txt", "sha256": "<SHA-256>"}]
}
```

Required CI names and human detail fields are executable constants `CHECKS`,
`GATES`, `DETAILS` in [release.py](../../Tools/Release/release.py). Every record
needs nonempty raw artifacts. CI evidence must come from successful exact-SHA
runs, including the protected real-model parity run; public tests may skip private
assets and cannot stand in for that record. Physical records require
`physicalDevice: true`, measured numeric cost fields and method-bound energy.
Attach the complete DocC tar archive and compiled example/build logs, not just a
claim that they exist. The reviewer is responsible for authenticity and scope;
schema/hash validation cannot prove a human really held a device.

`api-review` details include `decision` (`compatible` or `breaking-approved`),
`baselineRevision`, `migrationNotes` (a path/hash reference), and `previousMajor`
for stable breaking releases. `privacy` includes affirmative no-hidden-telemetry,
feedback/manifest/data-flow reviews and security-channel verification.
`HG-0015-001` contains the owner rationale/checklist/support owner/unresolved risks.
Device detail fields correspond to the [checklist](Checklist.md).

`pilots` entries contain `team`, distinct domain `useCase`, `external: true`,
`consent` (`public` or `explicit`) and a `record` path/hash. The referenced record
is named `pilot` and binds the same source revision; its details include the
integration run URL, toolchain and reproduction command. Private team identities
may be stable consented aliases, with independence reviewed by the owner.
Case/whitespace duplicates do not count. `criticalDXIssues` must be empty.
Stable additionally requires `api-freeze` and `external-contribution` records.
Only `QK-REL-011` may have a waiver with `owner`, `reason`, ISO-date `expires` and
`requirement`; expiry is checked on validation day. `narrative: true` adds the
separate narrative qualification record; do not set it for scripted fixtures.

```sh
./scripts/release-check --candidate /tmp/qualia-candidate/candidate.json
./scripts/release-check --candidate /tmp/qualia-candidate/candidate.json --bundle /tmp/qualia-release
```

The bundle is built in a sibling temporary directory and renamed only after
validation/copy/archive succeeds. It contains exact-source `source.tar`, referenced
evidence only and `checksums.json`. Existing output is never overwritten; private
model assets are never copied from the working directory. Review raw evidence for
privacy/licensing before adding it. A file changing while packaging is a failure.

The **Release candidate** workflow supports a manual dry run with frozen source,
version and evidence commit. On version-tag pushes it validates against the
`release-evidence` branch. Store the candidate at `<version>/candidate.json` on
that branch. It re-runs public builds/tests/docs/examples and uploads a bundle,
never publishes. Tag runs are serialized per version and never cancelled by a
new branch commit. Protected/manual real-model and human records are mandatory
inputs. Configure required branch/tag checks and owner environment reviewers in
GitHub before publication; CI is a guard, not a substitute for those permissions.
