import CoreGraphics
import Foundation

/// Public mock haptic provider for testing purposes.
/// Records all haptic events for verification in tests.
public final class MockHapticProvider: HapticProvider {

    // MARK: - Public Properties

    /// All patterns that have been played, in order
    public private(set) var playedPatterns: [HapticPattern] = []

    /// All base intensities that have been used, in order (corresponds to playedPatterns)
    public private(set) var playedIntensities: [CGFloat] = []

    /// Whether prepare() was called
    public private(set) var prepareCalled = false

    /// Whether a looping pattern is currently playing
    public private(set) var isLooping: Bool = false

    // MARK: - Thread Safety

    private let queue = DispatchQueue(label: "com.qualiakit.mock-haptic-provider")

    // MARK: - Public Methods

    public init() {}

    public func prepare() {
        queue.sync {
            prepareCalled = true
        }
    }

    public func play(pattern: HapticPattern, baseIntensity: CGFloat) {
        queue.sync {
            playedPatterns.append(pattern)
            playedIntensities.append(baseIntensity)
            isLooping = pattern.looping
        }
    }

    public func stopLooping() {
        queue.sync {
            isLooping = false
        }
    }

    /// Reset all recorded events (useful between tests)
    public func reset() {
        queue.sync {
            playedPatterns.removeAll()
            playedIntensities.removeAll()
            prepareCalled = false
            isLooping = false
        }
    }
}
