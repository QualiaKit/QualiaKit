import Combine
import SwiftUI

/// Thread-safe haptic engine for managing haptic feedback
///
/// All haptic operations are dispatched to the main thread internally,
/// so this class is safe to access from any context.
public final class HapticEngine: ObservableObject, Sendable {
    public static let shared = HapticEngine()

    /// Base intensity multiplier for all haptic feedback (0.0 - 1.0)
    ///
    /// This property is managed by `QualiaClient` based on configuration.
    /// You can also set it manually if needed.
    @MainActor
    public var baseIntensity: CGFloat = 1.0

    /// Patterns registered by the client for specific emotions.
    @MainActor
    private var patterns: [SenseEmotion: HapticPattern] = [:]

    private init() {
        Task { @MainActor in
            HapticManager.shared.prepare()
        }
    }

    @MainActor
    public func prepareHaptics() {
        HapticManager.shared.prepare()
    }

    /// Register a custom haptic pattern for an emotion.
    ///
    /// Call this during app initialization. Once registered, the pattern will
    /// be played whenever `play(for:)` is called for the matching emotion.
    @MainActor
    public func register(pattern: HapticPattern, for emotion: SenseEmotion) {
        patterns[emotion] = pattern
    }

    /// Plays haptic feedback for the given emotion
    ///
    /// Looks up a client-registered pattern first; falls back to a built-in
    /// default pattern if none has been registered for the emotion.
    ///
    /// - Parameters:
    ///   - emotion: The emotion to play haptic feedback for
    ///   - intensity: Optional intensity override. If not provided, uses `baseIntensity`
    @MainActor
    public func play(for emotion: SenseEmotion, intensity: CGFloat? = nil) {
        let finalIntensity = intensity ?? baseIntensity
        let pattern = patterns[emotion] ?? Self.defaultPattern(for: emotion)
        HapticManager.shared.play(pattern: pattern, baseIntensity: finalIntensity)
    }

    /// Stops any currently looping haptic pattern.
    @MainActor
    public func stopLooping() {
        HapticManager.shared.stopLooping()
    }

    // MARK: - Default Patterns
    //
    // Used when the client has not registered a custom pattern for an emotion.

    private static func defaultPattern(for emotion: SenseEmotion) -> HapticPattern {
        switch emotion {
        case .neutral:
            return HapticPattern(events: [
                HapticEvent(delay: 0.0, intensity: 0.2, sharpness: 0.3)
            ])
        case .positive:
            return HapticPattern(events: [
                HapticEvent(delay: 0.0, intensity: 0.7, sharpness: 0.8),
                HapticEvent(delay: 0.1, intensity: 0.4, sharpness: 0.6),
            ])
        case .negative:
            return HapticPattern(events: [
                HapticEvent(delay: 0.0, intensity: 0.9, sharpness: 1.0)
            ])
        case .intense:
            return HapticPattern(
                events: [
                    HapticEvent(delay: 0.00, intensity: 0.6, sharpness: 1.0),
                    HapticEvent(delay: 0.15, intensity: 0.4, sharpness: 0.8),
                ],
                looping: true,
                loopDuration: 1.5
            )
        case .mysterious:
            return HapticPattern(events: [
                HapticEvent(delay: 0.0, intensity: 0.4, sharpness: 0.2, isTransient: false)
            ])
        }
    }
}
