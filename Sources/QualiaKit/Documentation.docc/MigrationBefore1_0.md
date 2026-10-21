# Migration before 1.0

The model-agnostic 2.0 API is under development. Pin a reviewed revision and read
changes before updating. This guide is a concise mapping from the older Qualia and
QualiaBert products; it is not a compatibility shim or an unreleased API promise.

| Earlier integration | Current integration |
| --- | --- |
| Global client maps text/emotion to vibration | A retained QualiaSession connects explicit analyzer, reducer, policy and renderer |
| Sentiment enum implies a narrative meaning | Typed dimensions/signals with declared capabilities and separate evaluation |
| Singleton haptic manager | Injected MainActor renderer with per-session ownership |
| Errors become neutral-like feedback | Typed thrown errors and explicit renderer outcome in the response |
| Typing mutates the story | Separate draft session and accepted-event IDs |
| Implicit teardown | Await reset/suspend/resume at screen/scene boundaries |

The actual factories are `sentimentPreview`, `horrorNarrative`, and `configured`.
There is no `QualiaSession.horror` alias. Bundled Core ML assets use
`BundledQualiaModelSource(bundle:subdirectory:manifestName:)`, not a guessed modelURL
initializer. The current Russian sentiment assets retain their frozen contract;
this documentation does not migrate their tokenizer or grant redistribution rights.

Start with <doc:GettingStarted>, replace heuristic copies with
public extension protocols, and add the <doc:TestingYourIntegration>.
Review <doc:PrivacyAndDataFlow> and <doc:Accessibility> before
turning effects on in a host application.
