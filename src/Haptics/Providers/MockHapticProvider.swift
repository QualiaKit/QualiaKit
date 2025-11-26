import Foundation

/// Public mock haptic provider for testing purposes.
/// Records all haptic events for verification in tests.
public final class MockHapticProvider: HapticProvider {

    // MARK: - Public Properties

    /// All emotions that have been played, in order
    public private(set) var playedEmotions: [SenseEmotion] = []

    /// Whether prepare() was called
    public private(set) var prepareCalled = false

    /// Whether heartbeat is currently playing
    public private(set) var isHeartbeatPlaying = false

    /// Number of times each emotion was played
    public var emotionCounts: [SenseEmotion: Int] {
        Dictionary(grouping: playedEmotions, by: { $0 })
            .mapValues { $0.count }
    }

    // MARK: - Thread Safety

    private let queue = DispatchQueue(label: "com.qualiakit.mock-haptic-provider")

    // MARK: - Public Methods

    public init() {}

    public func prepare() {
        queue.sync {
            prepareCalled = true
        }
    }

    public func play(_ emotion: SenseEmotion) {
        queue.sync {
            playedEmotions.append(emotion)
        }
    }

    public func startHeartbeat() {
        queue.sync {
            isHeartbeatPlaying = true
        }
    }

    public func stopHeartbeat() {
        queue.sync {
            isHeartbeatPlaying = false
        }
    }

    /// Reset all recorded events (useful between tests)
    public func reset() {
        queue.sync {
            playedEmotions.removeAll()
            prepareCalled = false
            isHeartbeatPlaying = false
        }
    }
}
