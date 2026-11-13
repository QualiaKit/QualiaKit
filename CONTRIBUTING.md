# Contributing

Branch from `main` and keep changes focused. For public API, model mapping or
policy changes, explain the intended behavior before implementation. Follow the
[code of conduct](CODE_OF_CONDUCT.md) and [governance](GOVERNANCE.md).

Run the library and example-model tests, then the independent public consumer:

```sh
swift build
swift test
swift test --package-path Tests/Consumer
swift test --package-path Packages/QualiaCoreML
python3 Tests/CoreMLFixtures/verify.py
python3 Tests/TestingFixtures/generate.py
python3 -m unittest discover -s Tests/ModelContract -p 'test_*.py'
xcodebuild build -project Examples/QualiaExample/QualiaExample.xcodeproj \
  -scheme QualiaExample -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

CI runs on Xcode 16.4 and 26.6. Keep strict concurrency checks passing. Tests for
the actual example screen model run with a recording renderer, without a device.
The `Tests/Consumer` package checks public imports without `@testable` access.
See [test fixtures](Tests/README.md) for generators and protected model checks.

Add regression tests for behavior changes and update README or source comments
when the API changes. Preserve meaningful error handling, cancellation, owned
playback cleanup and accessibility. Use synthetic text in tests and bug reports.

Golden outputs, tolerances and model assets require a separate reviewed change;
do not regenerate them merely to make a test pass. A model contribution needs
provenance, license, an explicit manifest, independent expected outputs and
measurements on its supported devices. A policy change needs bounded effects and
ownership/stop tests. Software tests alone cannot establish tactile comfort.

Research, old device reports and retired release procedures are outside the
library checkout. The library and its tests must not depend on the author's archive.
Do not publish a release or make model-quality claims based only on a passing build.
