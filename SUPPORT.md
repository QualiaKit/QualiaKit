# Support

Use [GitHub issues](https://github.com/QualiaKit/QualiaKit/issues/new/choose) for
integration questions and reproducible bugs. For vulnerabilities, use the
[private security process](SECURITY.md). Discussions are not required or enabled.

The repository maintainer owns triage; the PR author supplies the reproduction.
Initial triage target is five business days and an active pilot gets a weekly
status update by mutual agreement. These are best-effort targets, with no paid
support or guaranteed fix date. If a target is missed, one issue follow-up is
appropriate. A second reviewer is recruited for model or tactile claims when
available; unreviewed claims remain pending.

Classify reports as runtime bug, model quality, policy/experience, unsupported
environment, or integration question. Include the exact commit, public product,
Swift/Xcode, OS/device, model and policy version, expected/observed result and a
synthetic minimal example. Never attach private text, a full session dump, a
licensed binary or credentials. Redacted diagnostics are opt-in and should still
be inspected before sharing.

Supported source-build and physical evidence scopes are separate in the
[compatibility matrix](docs/release/Compatibility.md). We do not promise haptics
on every Apple platform or support for arbitrary opaque models. Public API is
still evolving; pin a reviewed revision and read migration notes before updating.
