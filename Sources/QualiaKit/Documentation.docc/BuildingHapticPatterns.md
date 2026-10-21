# Building haptic patterns

HapticPattern is an immutable validated descriptor, not a Core Haptics object.
Transient events model taps; continuous events have an explicit duration.
Intensity and sharpness use finite HapticValue values in `0...1`. Events must be
ordered and fit inside the pattern duration. Parameter curves need ordered
control points and compatible hardware.

Use `.accent` for independent one-shot `play` commands. A looping `.ambient`
pattern has a stable HapticEffectID and uses `start`, `replace` and `stop`. Bound
physical playback with `playbackDuration`; policy-driven replacements must not
silently extend an effect's original deadline. HeartbeatPatternFactory already
implements the built-in rhythm; consumer examples should not copy its algorithm.

An owned effect ID uses the session owner's scope. Never issue global stop commands
from a session policy. When multiple sessions share a renderer, select arbitration
explicitly. Reset stops that owner's ambient and one-shot playback, including
players retained after an incomplete rollback.

The custom-policy example contains a minimal validated accent. Its initializer
throws for invalid descriptors instead of hiding configuration failure. At runtime,
check the response's execution failure even when analysis succeeded. Hardware
capabilities include haptics, continuous playback and parameter curves; support is
not proof of identical sensation. Physical iPhone tests and holder feedback remain
necessary. See <doc:Accessibility> and <doc:Performance>.
