import CoreGraphics

/// No-operation haptic provider for platforms without haptic support
public final class NoOpHapticProvider: HapticProvider {
    public func prepare() {}
    public func play(_ emotion: SenseEmotion, intensity: CGFloat) {}
    public func startHeartbeat() {}
    public func stopHeartbeat() {}
}
