# Governance

QualiaKit currently has one accountable repository maintainer and product owner:
[@antontuz](https://github.com/antontuz). This records responsibility, not a claim
that an independent review already occurred. Contributors own their patches;
maintainers own integration, security triage and release decisions.

Runtime/API review checks ownership, cancellation, privacy and compatibility.
Model review checks provenance, license, manifest, independent evaluation and
device cost. Haptics review checks physical behavior, comfort, lifecycle and
accessibility. The maintainer assigns a named qualified reviewer in each evidence
record; vacant roles or missing physical review keep a release blocked.

Small fixes can start as PRs. Public contract, model mapping and policy changes
need a written rationale and regression evidence. Golden changes get a dedicated
review with before/after evidence; they must not silently redefine success.
Unresolved disagreements stay documented in the PR; the maintainer decides with
reasons. The owner signs the final checklist only after the required reviews.

New maintainers are appointed after sustained, reviewed contributions and an
explicit public decision about scope and permissions. Conflicts of interest are
declared; the author does not count as an independent external pilot. Three
independent teams and two distinct external domains must inform API freeze.

Before 1.0, breaking changes require migration notes. After 1.0, incompatible
changes require a major version; deprecations normally span at least two minor
releases and 90 days. A security exception requires a documented migration and
owner rationale. Model manifest schemas remain independently versioned. No
registry API is planned until two real interchangeable models justify it.

Release/tag protection and environment reviewer settings are repository-owner
configuration, not properties a YAML file can enforce. Verify them and record
the result before a tag. Never bypass a pending physical gate to meet a date.
