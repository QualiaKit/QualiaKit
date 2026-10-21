# Sessions and context

Retain one QualiaSession actor per accepted narrative sequence. Construct it through
`configured`, `sentimentPreview`, or `horrorNarrative`; named factories express
requirements, not automatic analyzer selection. They run installation on MainActor
for renderer access. Session processing and analyzer work are asynchronous.

Use stable unique QualiaInputID values for accepted events. A newer process call
invalidates older work; cancellation-ignoring analyzers cannot commit stale output.
Calling code must still distinguish CancellationError from operational failure.
A duplicate accepted input throws rather than adding the same fragment twice.

The session owns retained context. Submit current text with empty external context;
the session rejects caller-supplied history to avoid competing ownership. Bounds
count historical fragments and total characters/UTF-8 bytes. Eviction retains a
newest contiguous suffix of complete fragments. Current text is never silently
sliced to fit; oversized current text throws. Model token truncation is a separate
adapter operation. Do not enable history for AppleSentimentAnalyzer.

## SwiftUI ownership

Construct the session once in a StateObject screen model, not inside `body`.
`qualiaReaction(eventID:input:session:onResult:)` deduplicates one accepted event;
its result callback runs on MainActor. `qualiaLiveReaction` is a debounced typing
adapter. Give typing a separate session so drafts cannot advance the accepted
story state. Its generated inputs require a language resolver allowing detection.
The modifiers do not own screen lifecycle.

Suspend when the scene becomes inactive/background; resume only after the previous
cleanup finishes; reset on leaving or replacing the screen. Disable input while a
lifecycle transition is in progress. Reset/suspend cancel in-flight work and stop
owned effects. Resume does not replay. If cleanup fails, retain the session and
surface the error; do not silently abandon possibly active playback.

The Xcode example demonstrates these explicit lifetimes. The
<doc:TestingYourIntegration> controls time deterministically.
Read <doc:PrivacyAndDataFlow> before retaining context and
<doc:Accessibility> before enabling continuous effects.
