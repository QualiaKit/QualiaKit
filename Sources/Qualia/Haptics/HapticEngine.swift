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

    private init() {
        Task { @MainActor in
            prepareHaptics()
        }
    }

    @MainActor
    public func prepareHaptics() {
        HapticManager.shared.prepare()
    }

    /// Plays haptic feedback for the given emotion
    ///
    /// - Parameters:
    ///   - emotion: The emotion to play haptic feedback for
    ///   - intensity: Optional intensity override. If not provided, uses `baseIntensity`
    @MainActor
    public func play(for emotion: SenseEmotion, intensity: CGFloat? = nil) {
        let finalIntensity = intensity ?? baseIntensity
        HapticManager.shared.play(emotion, intensity: finalIntensity)
    }

    @MainActor
    public func updateHeartbeat(shouldPlay: Bool) {
        if shouldPlay {
            HapticManager.shared.startHeartbeat()
        } else {
            HapticManager.shared.stopHeartbeat()
        }
    }
}
