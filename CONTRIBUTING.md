# Contributing

Branch from `main`. Small fixes can start as a PR; propose public API, model
mapping or policy changes in an issue first. Follow the [code of conduct](CODE_OF_CONDUCT.md)
and [governance](GOVERNANCE.md). Use synthetic examples, not private user text.

```sh
swift build
swift test
swift test --package-path Packages/QualiaCoreML
swift test --package-path Examples/DeveloperExperience
python3 Tools/DeveloperExperience/verify.py
./scripts/release-check
python3 -m unittest discover -s Tools/Release -p 'test_*.py'
```

Use existing Swift formatting. Release tooling also rejects trailing whitespace
and tabs in its Python/docs. Run strict concurrency for changed public targets.
The CI minimum and current toolchains must pass. Add meaningful regression tests,
update compiled examples and DocC, and explain limitations. API changes require
the compiler inventory/diff and a human review; do not replace a baseline to hide
a breaking change. See the [release workflow](docs/release/Evidence.md).

An analyzer contribution needs declared language/signal/context capabilities,
cancellation/error behavior and public consumer tests. Model contributions also
need a manifest and schema version, a model card with intended/prohibited uses,
source and dataset license evidence, asset hashes, benchmark and independent
evaluation. Validate the contribution record with
`python3 Tools/Release/model_contribution.py record.json`. Opaque weights alone
are not accepted. Real private assets stay out of Git and public CI. Narrative
claims additionally require annotation, held-out, hard-negative, context and
physical device evidence. No registry is added for hypothetical models.

A policy or pattern pack needs a version, pure deterministic behavior, independent
expected commands, bounded intensity/duration, ownership and stop tests. Comfort,
recognizability and energy claims need physical records. Keep golden fixture
updates separate and request explicit review of their provenance and tolerances.

Code is MIT. Identify third-party licenses explicitly; do not assume an upstream
repository license covers its datasets or weights. Security issues go through
[private disclosure](SECURITY.md), integration questions through [support](SUPPORT.md).
