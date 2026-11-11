# Known limitations

- The new runtime has no approved public beta/stable release. Source pinning is
  available for integration work; public contracts may change with migration notes.
- QualiaKitBert v10-preview.1 is included only in the example package as an
  experimental English narrative model, not a qualified production model. It
  accepts 128 tokens including context, uses uncalibrated scores, and lacks
  independent human-reviewed accuracy and comfort evidence. See its
  [model card](../../Models/QualiaKitBert/MODEL_CARD.md).
- There is no qualified production narrative model. Apple sentiment and recovered
  RuBERT sentiment do not establish suspense, threat or a person's emotional state.
- Current private model and vocabulary redistribution remain blocked by rights
  review. Code's MIT license does not grant rights to weights or datasets.
- October 21 device acceptance covers one iPhone 17 Pro iteration. No preferred
  heartbeat profile was selected; system Reduce Motion and the general sustained
  stage were not recorded in the accepted quick run. Do not convert these omissions
  into passing evidence. CPU time and nominal thermal state are not energy usage.
- Fresh release-bound energy/thermal/model measurements, renderer device matrix,
  heartbeat review and the current flagship SwiftUI walkthrough remain pending.
- Independent external pilots and API freeze review remain pending. Repository
  examples and the author's app are not independent external adoption.
- Haptics depend on hardware, system settings, accessibility preferences and the
  user. A simulator, recording renderer or GIF cannot prove sensation or comfort.
- `QualiaCoreML` is exported by the root package in development tag `0.1.0-dev.1`.
  The legacy nested layout remains available for command-line SwiftPM. Xcode
  applications must migrate to the root package because Xcode 16.4 cannot resolve
  duplicate product names in the nested layout; imports and model assets stay the same.
- Diagnostics and pilot feedback have no upload transport. Hosts remain responsible
  for consent, retention, deletion and privacy review of their own integrations.

Model cost numbers are published only with model/device/OS/build identity and raw
artifacts. See [performance](../Performance.md) for historical observations; no
universal latency, memory, battery or quality guarantee is made.

For `0.1.0-dev.1`, the protected legacy RuBERT reference check on Xcode 27.1
exceeded the frozen tolerance for `edge-empty.currentSwiftTransform.value`: absolute
difference `0.000013231067961332575`, allowed `0.0`. This is recorded as a failed
check, not corrected by widening tolerance. The old committed passing attestation
describes the earlier source; the current source cannot satisfy the qualified
release gate until model verification is resolved. See the
[recorded result](../../Models/current/root-export-verification.json).
