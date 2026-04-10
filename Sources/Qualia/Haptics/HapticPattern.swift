import Foundation

/// A single haptic impulse within a pattern.
public struct HapticEvent {
    /// Delay from pattern start in seconds.
    public let delay: TimeInterval
    /// Raw intensity (0.0–1.0). Final intensity = this × client multiplier.
    public let intensity: Float
    /// Sharpness (0.0 = soft thud, 1.0 = sharp click).
    public let sharpness: Float
    /// true = transient (impact), false = continuous (rumble).
    public let isTransient: Bool

    public init(
        delay: TimeInterval,
        intensity: Float,
        sharpness: Float = 0.5,
        isTransient: Bool = true
    ) {
        self.delay = delay
        self.intensity = intensity
        self.sharpness = sharpness
        self.isTransient = isTransient
    }
}

/// A sequence of haptic events that describes a complete tactile sensation.
public struct HapticPattern {
    public let events: [HapticEvent]
    /// Whether the pattern should loop continuously.
    public let looping: Bool
    /// Loop duration in seconds (required when looping = true).
    public let loopDuration: TimeInterval?

    public init(
        events: [HapticEvent],
        looping: Bool = false,
        loopDuration: TimeInterval? = nil
    ) {
        self.events = events
        self.looping = looping
        self.loopDuration = loopDuration
    }
}
