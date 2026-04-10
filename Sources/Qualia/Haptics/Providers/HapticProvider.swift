import CoreGraphics

/// Protocol for haptic feedback providers
///
/// Implement this protocol to create custom haptic providers for different platforms or testing.
public protocol HapticProvider {
    /// Prepares the haptic engine for playback
    func prepare()

    /// Play a haptic pattern with given intensity multiplier.
    ///
    /// - Parameters:
    ///   - pattern: The pattern to play
    ///   - baseIntensity: Intensity multiplier applied to every event in the pattern (0.0 - 1.0)
    func play(pattern: HapticPattern, baseIntensity: CGFloat)

    /// Stop any currently looping pattern.
    func stopLooping()
}
