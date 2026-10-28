# Release and adoption

The release infrastructure is implemented independently of release approval.
**Current state: development; no new-runtime public beta or 1.0 is approved.**
The October 21 iPhone acceptance remains valid for its recorded iteration and
exceptions. It does not approve a future release or fill omitted measurements.

## Development integration tag

At the owner's request, `0.1.0-dev.1` pins the source for application integration.
Select **Exact Version** in Xcode and the `QualiaKit` and optional `QualiaCoreML`
products from the same repository URL. This is an immutable development snapshot,
not an approved beta/stable release or a claim of narrative-model qualification.
The old higher-numbered tags remain legacy; do not use a broad version range.
No private model, vocabulary, training corpus or evaluation report is published.

The beta/stable evidence requirements below remain unchanged. This development
tag does not satisfy, waive or mark any pending physical, pilot or human gate as
passed. It has no qualified-release bundle. Applications can use the tagged code
for integration and testing while completing those independent checks.

## Qualified releases

The proposed first new-runtime version is **0.1.0-beta.1**, still an owner decision.
“2.0” in architecture/diagnostics identifies the runtime generation. Existing tags
up to `3.0.0` identify the legacy products and must not be moved or deleted.
For now, install by exact reviewed revision. If the owner chooses the proposed
beta line, use an exact version requirement, not an up-to-next-major range:

```swift
.package(url: "https://github.com/QualiaKit/QualiaKit.git", exact: "0.1.0-beta.1")
```

This example becomes usable only after that version exists. A different package
repository would avoid the historical version ordering; adopting it requires an
explicit migration decision. Never advertise `1.0` or `2.0` as the new runtime by
reusing legacy tags. Check remote tags before selecting any future version.

| Stage | Required evidence |
| --- | --- |
| Development | Deterministic checks; limitations explicit; no release claim |
| 0.x beta | Exact-source CI/parity, API review, docs/examples/privacy, author pilot, at least one consented independent external use case, all five release gates |
| 1.0 stable | All beta evidence; three independent external teams, at least two distinct external domains, API freeze informed by their feedback, no unresolved repeated critical DX issue |
| Narrative capability | Separate model annotation, held-out, hard-negative, context and physical evaluation; required whenever claimed, not inferred from sentiment |

All release stages retain model-specific cost and compatibility evidence.
External contribution/integration proof is expected before stable; only that
SHOULD requirement may have a named, reasoned, expiring waiver. Physical gates,
privacy, parity, API review and critical CI cannot be waived.

- [Compatibility and identities](Compatibility.md)
- [Known limitations](Limitations.md)
- [Owner checklist and device protocols](Checklist.md)
- [Evidence format, API diff and automation](Evidence.md)
- [Pilot protocol and adoption](Pilots.md)
- [Current evidence status](../../ReleaseEvidence/spec-0015/STATUS.md)
