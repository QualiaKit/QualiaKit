import CoreGraphics

/// No-operation haptic provider for platforms without haptic support
public final class NoOpHapticProvider: HapticProvider {
    public init() {}
    public func prepare() {}
    public func play(pattern: HapticPattern, baseIntensity: CGFloat) {}
    public func stopLooping() {}
}
