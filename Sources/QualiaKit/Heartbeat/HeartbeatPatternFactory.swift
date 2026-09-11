/// Validated physical parameters for one double-beat cycle. These evaluation
/// bounds are not a claim about the reader's pulse or physiological accuracy.
public struct HeartbeatParameters: Hashable, Sendable {
    public let beatsPerMinute: Double
    public let intensity: HapticValue
    public let sharpness: HapticValue
    public let secondBeatRatio: Double

    public init(
        beatsPerMinute: Double,
        intensity: HapticValue,
        sharpness: HapticValue,
        secondBeatRatio: Double = 0.25
    ) throws {
        guard beatsPerMinute.isFinite, (55...120).contains(beatsPerMinute),
              secondBeatRatio.isFinite, (0.18...0.35).contains(secondBeatRatio) else {
            throw HapticError.invalidHapticPattern
        }
        self.beatsPerMinute = beatsPerMinute
        self.intensity = intensity
        self.sharpness = sharpness
        self.secondBeatRatio = secondBeatRatio
    }
}

/// Pure, deterministic lub/dub factory. Playback is always finite, including
/// when no later scene transition arrives. Replacement must use the remaining
/// duration of the original segment, rather than renew it implicitly.
public struct HeartbeatPatternFactory: Sendable {
    public init() {}

    public func makePattern(
        parameters: HeartbeatParameters,
        maximumDuration: Duration = .seconds(12)
    ) throws -> HapticPattern {
        let cycle = Duration.seconds(60 / parameters.beatsPerMinute)
        return try HapticPattern(
            duration: cycle,
            events: [
                .transient(at: .zero, intensity: parameters.intensity, sharpness: parameters.sharpness),
                .transient(
                    at: .seconds(60 / parameters.beatsPerMinute * parameters.secondBeatRatio),
                    intensity: HapticValue(parameters.intensity.rawValue * 0.7),
                    sharpness: parameters.sharpness
                ),
            ],
            looping: .loop(period: cycle),
            playbackDuration: maximumDuration
        )
    }
}
