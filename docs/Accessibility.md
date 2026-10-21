# Accessibility

Offer an immediate haptics off control, intensity scaling, a continuous-effects
switch and a maximum continuous duration. Apply QualiaHapticPreferences through
the session; do not bypass safety with direct global renderer calls. Disabling
feedback stops owned effects. Zero intensity produces no physical playback.

Read the system Reduce Motion setting in your host and map it to
`continuousEffectsEnabled: false`. The runtime does not infer a host UI preference.
Separate accent feedback can remain enabled according to the app's controls.
The example combines its continuous-effects toggle with SwiftUI's Reduce Motion
environment value. Keep status/error text accessible to VoiceOver and do not use
vibration as the only way to convey meaning.

Continuous playback has a physical deadline independent of new input. Background
or inactive scenes must suspend the session; returning resumes admission without
replaying the last effect. Explicit reset stops effects on leaving a screen.
Handle cleanup errors visibly so a failed stop is not mistaken for completion.

Hardware capability flags and simulator traces cannot establish comfort. Test on
physical devices with the intended holders and stop when uncomfortable. The current
iPhone 17 Pro holder rated A/B/C distinct and comfortable; that is one-device,
one-holder evidence, not a universal calibration. Never describe heartbeat feedback
as measuring the user's pulse, fear or health. See [Privacy](PrivacyAndDataFlow.md).
