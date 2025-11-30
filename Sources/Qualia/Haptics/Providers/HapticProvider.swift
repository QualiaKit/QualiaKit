import CoreGraphics

/// Protocol for haptic feedback providers
///
/// Implement this protocol to create custom haptic providers for different platforms or testing.
public protocol HapticProvider {
    /// Prepares the haptic engine for playback
    func prepare()

    /// Plays haptic feedback for the given emotion
    ///
    /// - Parameters:
    ///   - emotion: The emotion to play haptic feedback for
    ///   - intensity: Intensity multiplier (0.0 - 1.0)
    func play(_ emotion: SenseEmotion, intensity: CGFloat)

    /// Starts continuous heartbeat haptic pattern
    func startHeartbeat()

    /// Stops continuous heartbeat haptic pattern
    func stopHeartbeat()
}
