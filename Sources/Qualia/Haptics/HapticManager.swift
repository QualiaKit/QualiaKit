public enum HapticManager {
    static let shared: HapticProvider = {
        #if os(iOS)
            return IOSHapticProvider()
        #else
            return NoOpHapticProvider()
        #endif
    }()
}
