import CoreGraphics
import Foundation

/// Configuration for QualiaClient behavior
///
/// Use this to control haptic feedback, heartbeat patterns, and other QualiaKit features.
///
/// ## Example Usage
/// ```swift
/// // Standard mode with automatic haptics
/// let config = QualiaConfiguration.standard
///
/// // Silent mode for testing
/// let config = QualiaConfiguration.silent
///
/// // Custom configuration
/// let config = QualiaConfiguration(
///     autoPlayHaptics: true,
///     enableHeartbeat: false,
///     hapticIntensity: 0.7
/// )
/// ```
public struct QualiaConfiguration {
    /// Automatically play haptics when using `analyzeAndFeel()`
    ///
    /// When `true`, calling `analyzeAndFeel()` will automatically trigger haptic feedback.
    /// When `false`, you must call `feel()` explicitly to trigger haptics.
    public var autoPlayHaptics: Bool

    /// Enable heartbeat pattern for intense emotions
    ///
    /// When `true`, the heartbeat haptic pattern will play continuously when `.intense` emotion is detected.
    public var enableHeartbeat: Bool

    /// Haptic intensity multiplier (0.0 - 1.0)
    ///
    /// Controls the strength of haptic feedback. Default is `1.0` (full intensity).
    /// For accessibility or reduced sensory input, use lower values like `0.5`.
    public var hapticIntensity: CGFloat

    /// Delay before playing haptics (in seconds)
    ///
    /// Useful for synchronizing haptics with other UI elements or animations.
    /// Default is `0.0` (immediate playback).
    public var hapticDelay: TimeInterval

    /// Creates a new configuration with the specified parameters
    ///
    /// - Parameters:
    ///   - autoPlayHaptics: Whether to automatically play haptics in `analyzeAndFeel()`. Default: `true`
    ///   - enableHeartbeat: Whether to enable heartbeat pattern for intense emotions. Default: `true`
    ///   - hapticIntensity: Haptic intensity multiplier (0.0 - 1.0). Default: `1.0`
    ///   - hapticDelay: Delay before playing haptics in seconds. Default: `0.0`
    public init(
        autoPlayHaptics: Bool = true,
        enableHeartbeat: Bool = true,
        hapticIntensity: CGFloat = 1.0,
        hapticDelay: TimeInterval = 0.0
    ) {
        self.autoPlayHaptics = autoPlayHaptics
        self.enableHeartbeat = enableHeartbeat
        self.hapticIntensity = hapticIntensity
        self.hapticDelay = hapticDelay
    }

    // MARK: - Presets

    /// Standard configuration with auto-haptics enabled
    ///
    /// Best for typical app usage where haptic feedback enhances the user experience.
    public static let standard = QualiaConfiguration()

    /// Silent mode - no automatic haptics
    ///
    /// Use when you want full manual control over haptic feedback,
    /// or when haptics should be disabled (e.g., accessibility preferences).
    public static let silent = QualiaConfiguration(autoPlayHaptics: false, enableHeartbeat: false)

    /// Testing mode - analysis only
    ///
    /// Optimized for unit tests where haptic feedback is not needed.
    /// Identical to `.silent` but semantically indicates testing intent.
    public static let testing = QualiaConfiguration(autoPlayHaptics: false, enableHeartbeat: false)

    /// Accessibility mode - reduced haptic intensity
    ///
    /// Provides gentler haptic feedback for users who prefer or require
    /// reduced sensory input.
    public static let accessibility = QualiaConfiguration(hapticIntensity: 0.5)
}
