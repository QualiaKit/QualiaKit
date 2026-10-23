# Pilot and adoption protocol

No external pilot is currently claimed. The author's app and repository demos
do not satisfy independence. Target a reading/accessibility prototype and a game
or visual-novel integration as distinct domains; these are recruitment targets,
not measured use cases. Beta requires one external domain; stable requires three
independent teams and at least two external domains.

The maintainer owns recruitment, obtains explicit participation/publication
consent and agrees a weekly contact cadence. Do not automatically message users
or mine private repositories. Record team alias, independence, app/domain,
consent scope, frozen source/model/policy/effect versions and integration proof.
Measure time from installation to first physical effect, setup failures, repeated
questions, API pain points and resolution. Review API freeze after those findings.

## Author-app integration and shadow trial

Use accepted fragments only, a host-declared room language and bounded history.
Keep UI draft typing separate. Migrate a real app through the public integration
path, then compare old and candidate policies on the same accepted event stream.
Only the primary session owns the physical renderer; the shadow session uses an
internally constructed recording renderer. Never install two physical renderers
or count the shadow's simulated success as device evidence.

The compiled consumer [PilotComparison](../../Examples/DeveloperExperience/Sources/QualiaExamples/PilotComparison.swift)
demonstrates this boundary and lifecycle cleanup. The host must serialize accepted
events and lifecycle calls, surface failures, and stop both sessions on exit.
The sample is integration infrastructure, not proof the author's production app
has completed a pilot. Record the real app commit and walkthrough separately.

## Explicit feedback, no raw text

The [PilotFeedback](../../Examples/DeveloperExperience/Sources/QualiaExamples/PilotFeedback.swift)
sample creates an event only after explicit consent. Its closed schema contains
appropriate/inappropriate/uncertain judgment, a disable choice, and fingerprints
of installation metadata (runtime/model/policy/effect identifiers and versions).
No input IDs, raw text, context, user/session/device identifiers, arbitrary notes,
scores or automatic transport are included. Metadata must come from installation,
never user content; hashing text is not anonymization or consent.

Hosts choose whether to keep an event in memory, show a local export or send it
under a separate reviewed consent flow. Agree retention/deletion with participants;
the default sample stores and sends nothing. Do not serialize a full response or
analyzer error as feedback. Curated text requires a separate explicit workflow,
legal basis, sanitization and provenance outside the feedback event. Use synthetic
regressions whenever possible.

## Adoption review

Maintain a consented/public ledger of real dependent repositories/apps, independent
teams, shipped use cases, adapters/policy/pattern contributions, time to first
effect, support questions/resolution time, version adoption and opt-in aggregate
disable/false-reaction judgments. Estimated end users need a cited public or
consented source; no SDK installs counter, tracking ID or background ping exists.
Stars/downloads are weak signals and not independent integrations. Sparse data
and author-selection bias must accompany summaries. Before stable, close repeated
critical DX issues and attach the ledger/interview conclusions to API freeze.
