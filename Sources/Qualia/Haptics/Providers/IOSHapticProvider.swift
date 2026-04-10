import Combine
import CoreHaptics
import SwiftUI

#if os(iOS)
    import UIKit

    public final class IOSHapticProvider: HapticProvider {
        private var hapticEngine: CHHapticEngine?
        private var loopingPlayer: CHHapticAdvancedPatternPlayer?

        // Fallback generator for devices without CoreHaptics
        private let impactMedium = UIImpactFeedbackGenerator(style: .medium)

        public init() {}

        public func prepare() {
            impactMedium.prepare()
            setupEngine()
        }

        public func play(pattern: HapticPattern, baseIntensity: CGFloat) {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
                  let engine = hapticEngine else {
                // Fallback: a single medium impact
                impactMedium.impactOccurred(intensity: baseIntensity)
                return
            }

            do {
                // Stop any previous looping pattern
                try loopingPlayer?.stop(atTime: CHHapticTimeImmediate)
                loopingPlayer = nil

                let chEvents: [CHHapticEvent] = pattern.events.map { event in
                    let finalIntensity = event.intensity * Float(baseIntensity)
                    return CHHapticEvent(
                        eventType: event.isTransient ? .hapticTransient : .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: finalIntensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
                        ],
                        relativeTime: event.delay,
                        duration: event.isTransient ? 0 : (pattern.loopDuration ?? 1.0)
                    )
                }

                let chPattern = try CHHapticPattern(events: chEvents, parameters: [])

                if pattern.looping {
                    let player = try engine.makeAdvancedPlayer(with: chPattern)
                    player.loopEnabled = true
                    player.loopEnd = pattern.loopDuration ?? 1.5
                    try player.start(atTime: CHHapticTimeImmediate)
                    loopingPlayer = player
                } else {
                    let player = try engine.makePlayer(with: chPattern)
                    try player.start(atTime: CHHapticTimeImmediate)
                }
            } catch {
                print("QualiaKit: Haptic playback failed — \(error.localizedDescription)")
            }
        }

        public func stopLooping() {
            do {
                try loopingPlayer?.stop(atTime: CHHapticTimeImmediate)
            } catch {
                print("QualiaKit: Failed to stop looping pattern — \(error.localizedDescription)")
            }
            loopingPlayer = nil
        }

        // MARK: - Private Methods

        private func setupEngine() {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            do {
                hapticEngine = try CHHapticEngine()
                hapticEngine?.resetHandler = { [weak self] in
                    try? self?.hapticEngine?.start()
                }
                hapticEngine?.stoppedHandler = { reason in
                    print("QualiaKit: Haptic engine stopped — \(reason.rawValue)")
                }
                try hapticEngine?.start()
            } catch {
                print("QualiaKit: Failed to initialize haptic engine — \(error.localizedDescription)")
            }
        }
    }
#endif
