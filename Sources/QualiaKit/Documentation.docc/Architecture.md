# Architecture

A QualiaSession owns one ordered sequence of accepted fragments. Its pipeline is:

```text
input → bounded context + explicit language resolution → analyzer
      → typed observation → temporal reducer → reaction policy
      → validated commands → injected renderer → structured response
```

An analyzer reports content properties and provenance. It never chooses haptic
IDs or reads physical hardware. A reducer receives a monotonic instant and
produces deterministic state. Continuous signals accumulate; impact events apply
to one transition. A missing score is distinct from zero. Confidence belongs to
observations, not accumulated scene state.

A pure policy maps the transition to a plan. It cannot call a renderer. A session
owns command ordering, safety preferences and physical reconciliation when a
command partially fails. The CoreHapticRenderer is MainActor-isolated. Ambient
and accent are independent channels; owned stop/reset does not stop other sessions.
A response distinguishes planned commands from attempted/successful execution.

Use QualiaKit for contracts, sessions, Apple preview and rendering; add QualiaTesting
for fixtures and deterministic command tests. The optional local QualiaCoreML
package supplies a manifest-checked model adapter. No framework types from your
story application are required by the runtime.

<doc:ChoosingAnAnalyzer> from its declared languages, outputs,
context behavior and execution mode. A valence-only analyzer cannot satisfy the
strict narrative factory. The scripted LivingStory example proves orchestration,
not narrative accuracy. <doc:PrivacyAndDataFlow> describes each boundary.
