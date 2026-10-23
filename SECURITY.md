# Security policy

Report vulnerabilities privately using
[GitHub private vulnerability reporting](https://github.com/QualiaKit/QualiaKit/security/advisories/new).
Do not publish exploit details, private text, model weights, credentials or user
identifiers in an issue. Include a minimal synthetic reproduction, affected
commit/version, platform and impact. If GitHub cannot accept the report, wait for
the private channel to become available; do not fall back to a public issue.

The repository maintainer triages reports and coordinates a fix and disclosure
with the reporter. Initial acknowledgement target: five business days; updates
target: every ten business days while actively investigating. These are
best-effort targets for a volunteer project, not contractual response guarantees.
Disclosure follows a reviewed fix and reporter coordination, not an automatic timer.

The current development branch is the supported security investigation target.
No new-runtime beta or stable release has been issued. Legacy tags are not
promised backports; maintainers assess them individually. After a new-runtime
release, the latest minor line receives fixes; this table must be updated before
each tag and the private channel verified in release evidence.

Trust boundaries include host analyzers/sinks, model installation, tensor/manifest
validation, lifecycle cleanup and private feedback. Core performs no network
transport. A model declaring on-device execution is not a sandbox. Code's MIT
license grants no model or dataset rights. See [privacy](docs/PrivacyAndDataFlow.md)
and [contribution requirements](CONTRIBUTING.md).
