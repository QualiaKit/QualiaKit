# Release tools

Python 3.9+ standard library; no network access or publication in the validators.
See [the protocol](../../docs/release/Evidence.md) for preparing evidence in a
separate branch and [the status](../../ReleaseEvidence/spec-0015/STATUS.md) for
what remains pending. Test fixtures in `test_release.py` are synthetic only.

`api-baseline.json` is a generated development baseline of the public source at
`9c516cc8e316f9355bd8899b1f9682268fdd7e47` (merged spec 0014), extracted using the
local Swift 6.4 / Xcode 27.1 toolchain. The source hash covers the three current
products and manifests. The new spec 0015 code does not change those declarations.
Export again with `api.py`; compare on the same toolchain where possible and
explain SDK-only differences. The snapshot includes owned declarations and their
relationships; no inherited SDK members, ABI guarantee or iOS-only audit is
implied. Do not automatically replace it on every PR. Future releases compare
against the previous reviewed release snapshot saved in its evidence bundle.

For a model contribution, `model_contribution.py` requires exactly these top-level
fields: `schemaVersion: 1`, `id`, `version`, `manifestSchemaVersion`,
`sourceRevision`, nonempty `intendedUses` and `prohibitedUses`,
`redistributionApproved: true`, `reviewer`, `narrative` (boolean), and `artifacts`.
The artifact map contains path/SHA-256 references named `manifest`, `modelCard`,
`modelLicense`, `datasetLicense`, `assetInventory`, `benchmark` and `evaluation`.
Narrative scope adds `annotation`, `heldOut`, `hardNegatives`, `context`, `device`.
These checks establish completeness and integrity, not legal or scientific truth;
a named reviewer must examine the contents and run the adapter's manifest schema
and inference/fixture tests before acceptance. Do not distribute private assets
just to satisfy a checklist.
