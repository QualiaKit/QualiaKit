public final class NoOpHapticProvider: HapticProvider {
    public func prepare() {}
    public func play(_ emotion: SenseEmotion) {}
    public func startHeartbeat() {}
    public func stopHeartbeat() {}
}
