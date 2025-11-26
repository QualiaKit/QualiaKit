import Combine
import CoreHaptics
import SwiftUI

public final class IOSHapticProvider: HapticProvider {
    private let notification = UINotificationFeedbackGenerator()
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    private var hapticEngine: CHHapticEngine?
    private var heartbeatPlayer: CHHapticAdvancedPatternPlayer?

    public func prepare() {
        notification.prepare()
        heavy.prepare()
        setupHapticEngine()
    }

    public func play(_ emotion: SenseEmotion) {
        switch emotion {
        case .positive: notification.notificationOccurred(.success)
        case .negative: rigid.impactOccurred()
        case .intense: heavy.impactOccurred(intensity: 1.0)
        case .mysterious: soft.impactOccurred(intensity: 0.8)
        case .neutral: light.impactOccurred()
        }
    }

    public func startHeartbeat() {
        guard heartbeatPlayer == nil else { return }

        do {
            let pattern = try createHeartbeatPattern()
            heartbeatPlayer = try hapticEngine?.makeAdvancedPlayer(with: pattern)
            heartbeatPlayer?.loopEnabled = true
            heartbeatPlayer?.loopEnd = 1.5
            try heartbeatPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to start heartbeat: \(error.localizedDescription)")
        }
    }

    public func stopHeartbeat() {
        do {
            try heartbeatPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to stop heartbeat: \(error.localizedDescription)")
        }
        heartbeatPlayer = nil
    }

    // MARK: - Private Methods

    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Failed to initialize haptic engine: \(error.localizedDescription)")
        }
    }

    private func createHeartbeatPattern() throws -> CHHapticPattern {
        let firstPulse = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
            ],
            relativeTime: 0.0
        )

        let secondPulse = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
            ],
            relativeTime: 0.15
        )

        return try CHHapticPattern(events: [firstPulse, secondPulse], parameters: [])
    }
}
