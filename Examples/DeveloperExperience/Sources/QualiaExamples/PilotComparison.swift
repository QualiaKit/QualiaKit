import QualiaKit
import QualiaTesting

/// The host serializes accepted inputs/lifecycle calls. Only primary can vibrate.
/// Shadow results are command counts, never evidence of physical success.
@MainActor
public final class PilotComparison {
    public struct Result: Sendable {
        public let primaryCommandCount: Int
        public let shadowCommandCount: Int
    }

    private let primary: QualiaSession
    private let shadow: QualiaSession
    private let shadowRenderer: RecordingHapticRenderer

    public init(primary: QualiaSession, shadowAnalyzer: any QualiaAnalyzing,
                shadowConfiguration: QualiaSessionConfiguration) async throws {
        self.primary = primary
        let renderer = RecordingHapticRenderer()
        self.shadowRenderer = renderer
        self.shadow = try await QualiaSession.configured(
            analyzer: shadowAnalyzer, renderer: renderer, configuration: shadowConfiguration
        )
    }

    public func process(_ acceptedInput: QualiaInput) async throws -> Result {
        defer { shadowRenderer.resetHistory() }
        let actual = try await primary.process(acceptedInput)
        if let failure = actual.execution.failure { throw failure }
        let compared = try await shadow.process(acceptedInput)
        if let failure = compared.execution.failure { throw failure }
        return Result(primaryCommandCount: actual.reaction.hapticCommands.count,
                      shadowCommandCount: compared.reaction.hapticCommands.count)
    }

    /// Both cleanup attempts run even if one fails. The first failure is visible.
    public func suspend() async throws {
        var failure: (any Error)?
        do { try await primary.suspend() } catch { failure = error }
        do { try await shadow.suspend() } catch { if failure == nil { failure = error } }
        shadowRenderer.resetHistory()
        if let failure { throw failure }
    }

    public func resume() async throws {
        try await primary.resume()
        do { try await shadow.resume() }
        catch {
            let resumeError = error
            // Keep both inactive if resumption cannot complete.
            try await suspend()
            throw resumeError
        }
    }

    public func reset() async throws {
        var failure: (any Error)?
        do { try await primary.reset() } catch { failure = error }
        do { try await shadow.reset() } catch { if failure == nil { failure = error } }
        shadowRenderer.resetHistory()
        if let failure { throw failure }
    }
}
