import QualiaKit

/// Exercises the public session with a shared deterministic clock and recording
/// renderer. Every harness owns independent state; no XCTest dependency.
@MainActor
public struct QualiaSessionHarness {
    public let clock: TestQualiaClock
    public let renderer: RecordingHapticRenderer
    public let session: QualiaSession

    public init(analyzer: any QualiaAnalyzing, configuration: QualiaSessionConfiguration,
                clock: TestQualiaClock = TestQualiaClock(),
                capabilities: HapticCapabilities = .full) async throws {
        self.clock = clock
        let renderer = RecordingHapticRenderer(capabilities: capabilities, now: { clock.now })
        self.renderer = renderer
        session = try await QualiaSession.configured(
            analyzer: analyzer, renderer: renderer, configuration: configuration, clock: clock
        )
    }

    public func advance(by duration: Duration) throws {
        try clock.advance(by: duration)
        renderer.expireEffects()
    }

    public func process(_ input: QualiaInput, advancingBy duration: Duration = .zero) async throws -> QualiaResponse {
        try advance(by: duration)
        return try await session.process(input)
    }

    public func reset() async throws { try await session.reset() }
}
