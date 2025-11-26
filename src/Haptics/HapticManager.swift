public enum HapticManager {
    static let shared: HapticProvider = {
        #if canImport(UIKit) && os(iOS)
            return IOSHapticProvider()
        #else
            return NoOpHapticProvider()
        #endif
    }()
}
