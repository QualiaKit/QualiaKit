# Release status

The current integration version is **`0.1.0-dev.1`**, a development snapshot.
No new-runtime public beta or stable release is approved; public contracts may
change with migration notes.

In Xcode, add `https://github.com/QualiaKit/QualiaKit.git`, choose **Exact Version**
`0.1.0-dev.1`, and select `QualiaKit` and optionally `QualiaCoreML` from that package.
Use a reviewed commit when testing changes newer than that snapshot.

The QualiaKitBert experimental model/demo is available in the source preview,
not in tag `0.1.0-dev.1`. Its `v10-preview.1` is a model identity, not a Swift
package release version. Use the same source revision for the example and runtime.

Older higher-numbered tags, up to `3.0.0`, belong to the legacy `Qualia` and
`QualiaBert` products. Avoid a broad version range when integrating the new runtime.
“2.0” in architecture and diagnostics names the runtime generation, not an
approved package release. Existing tags are immutable.

Model weights and vocabularies are supplied by the application and licensed
separately. No production narrative model is bundled or qualified by this release.

- [Compatibility](Compatibility.md)
- [Known limitations](Limitations.md)
- [Model integration](../UsingCoreMLModels.md)
- [Migration](../MigrationBefore1_0.md)
