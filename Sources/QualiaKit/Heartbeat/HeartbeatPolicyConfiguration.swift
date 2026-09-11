/// Provisional, versioned evaluation defaults. Release calibration is tracked
/// by HG-0015-004; these values have not been validated for device comfort.
public struct HeartbeatPolicyConfiguration: Hashable, Sendable {
    public static let version = "heartbeat-candidate-v1"
    public let startThreshold: Float
    public let stopThreshold: Float
    public let minimumSignalConfidence: Float
    public let minimumUpdateInterval: Duration
    public let maximumDuration: Duration
    public let cooldown: Duration
    public let resolvingDuration: Duration
    public let minimumBPM: Double
    public let maximumBPM: Double
    public let minimumBPMDelta: Double
    public let minimumIntensityDelta: Float
    public let userIntensityScale: Float

    public init(
        startThreshold: Float = 0.85,
        stopThreshold: Float = 0.50,
        minimumSignalConfidence: Float = 0.70,
        minimumUpdateInterval: Duration = .milliseconds(500),
        maximumDuration: Duration = .seconds(12),
        cooldown: Duration = .seconds(2),
        resolvingDuration: Duration = .milliseconds(300),
        minimumBPM: Double = 64,
        maximumBPM: Double = 108,
        minimumBPMDelta: Double = 4,
        minimumIntensityDelta: Float = 0.05,
        userIntensityScale: Float = 1
    ) throws {
        guard [startThreshold, stopThreshold, minimumSignalConfidence].allSatisfy({
            $0.isFinite && (0...1).contains($0)
        }), startThreshold > stopThreshold else {
            throw QualiaReactionConfigurationError.invalidThresholds
        }
        guard minimumBPM.isFinite, maximumBPM.isFinite,
              (55...120).contains(minimumBPM), (55...120).contains(maximumBPM),
              minimumBPM <= maximumBPM, minimumBPMDelta.isFinite, minimumBPMDelta > 0,
              minimumIntensityDelta.isFinite, (0...1).contains(minimumIntensityDelta),
              minimumIntensityDelta > 0 else {
            throw QualiaReactionConfigurationError.invalidRange
        }
        guard minimumUpdateInterval > .zero, maximumDuration > .zero,
              cooldown >= .zero, resolvingDuration > .zero,
              resolvingDuration <= maximumDuration else {
            throw QualiaReactionConfigurationError.invalidDuration
        }
        guard userIntensityScale.isFinite, (0...1).contains(userIntensityScale) else {
            throw QualiaReactionConfigurationError.invalidIntensityScale
        }
        self.startThreshold = startThreshold
        self.stopThreshold = stopThreshold
        self.minimumSignalConfidence = minimumSignalConfidence
        self.minimumUpdateInterval = minimumUpdateInterval
        self.maximumDuration = maximumDuration
        self.cooldown = cooldown
        self.resolvingDuration = resolvingDuration
        self.minimumBPM = minimumBPM
        self.maximumBPM = maximumBPM
        self.minimumBPMDelta = minimumBPMDelta
        self.minimumIntensityDelta = minimumIntensityDelta
        self.userIntensityScale = userIntensityScale
    }

    public static let `default`: Self = {
        do { return try Self() } catch { preconditionFailure("Invalid heartbeat defaults: \(error)") }
    }()
}

/// Session-owned lifecycle, separate from both scene state and the renderer.
/// A renderer failure latches suppression until an explicit lifecycle reset;
/// fresh observations alone cannot retry vibration.
struct HeartbeatState: Hashable, Sendable {
    enum Phase: String, Hashable, Sendable {
        case idle, running, resolving, cooldown, failed
    }
    var phase: Phase = .idle
    var startedAt: Duration = .zero
    var lastUpdate: Duration = .zero
    var deadline: Duration = .zero
    var cooldownUntil: Duration = .zero
    var parameters: HeartbeatParameters?
}
