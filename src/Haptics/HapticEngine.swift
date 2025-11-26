import Combine
import SwiftUI

@MainActor
public final class HapticEngine: ObservableObject {
    public static let shared = HapticEngine()

    private init() {
        prepareHaptics()
    }

    public func prepareHaptics() {
        HapticManager.shared.prepare()
    }

    public func play(for emotion: SenseEmotion) {
        HapticManager.shared.play(emotion)
    }

    public func updateHeartbeat(shouldPlay: Bool) {
        if shouldPlay {
            HapticManager.shared.startHeartbeat()
        } else {
            HapticManager.shared.stopHeartbeat()
        }
    }
}
