import Foundation

/// A bounded, local explanation of redacted runtime events.
///
/// This value never inspects input, observations, policy facts, or adapter error
/// descriptions. Identities and language remain fingerprints, and observations
/// expose counts rather than scores. It performs no logging or transport.
/// Available on iOS 16 and macOS 13; construction is synchronous and actor-neutral.
public struct QualiaDecisionReport: Sendable {
    /// Ordered descriptions of the most recent events, including session/generation correlation.
    public let lines: [String]
    /// Events excluded by this report's bound; a recording sink may have dropped others earlier.
    public let omittedEventCount: Int
    /// A plain-text rendering suitable for an explicitly enabled local debug view.
    public var text: String { lines.joined(separator: "\n") }

    /// Formats up to `maximumEvents` from the end of a diagnostic snapshot.
    ///
    /// - Parameters:
    ///   - events: A snapshot of structured events, never raw text or response objects.
    ///   - maximumEvents: A bound in `1...4096`; defaults to 200.
    /// - Throws: `QualiaError.invalidConfiguration` for an invalid bound.
    /// - Note: Output wording is intended for people, not as a persisted parsing schema.
    public init(events: [QualiaDiagnosticEvent], maximumEvents: Int = 200) throws {
        guard (1...4096).contains(maximumEvents) else {
            throw QualiaError.invalidConfiguration(reason: .configuration)
        }
        omittedEventCount = max(0, events.count - maximumEvents)
        lines = events.suffix(maximumEvents).map(Self.describe)
    }

    private static func fingerprint(_ value: QualiaDiagnosticFingerprint) -> String {
        value.bytes.map { String(format: "%02x", $0) }.joined()
    }
    private static func identity(_ value: QualiaDiagnosticIdentity?) -> String {
        guard let value else { return "not declared" }
        return "sha256:\(fingerprint(value.identifier))@\(fingerprint(value.version))"
    }
    private static func milliseconds(_ value: Duration) -> String {
        let parts = value.components
        return String(format: "%.3f ms", locale: Locale(identifier: "en_US_POSIX"),
                      Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15)
    }
    private static func describe(_ event: QualiaDiagnosticEvent) -> String {
        switch event {
        case let .correlated(session, generation, event):
            return "[\(session.uuidString) #\(generation)] " + describe(event)
        case let .fallbackSelected(cause, analyzer): return "Fallback: \(cause); analyzer \(identity(analyzer))"
        case let .model(stage, model, contract, duration, count, truncated):
            return "Model \(stage): \(identity(model)); contract sha256:\(fingerprint(contract)); \(milliseconds(duration)); tokens \(count.map(String.init) ?? "unknown"); truncated \(truncated.map(String.init) ?? "unknown")"
        case let .lifecycle(value): return "Lifecycle: \(value)"
        case let .started(generation): return "Started #\(generation)"
        case let .failed(generation, stage): return "Failed #\(generation): \(stage)"
        case let .discarded(generation, stage): return "Discarded stale #\(generation): \(stage)"
        case let .cancelled(generation, stage): return "Cancelled #\(generation): \(stage)"
        case let .completed(generation, revision, commands, failure):
            return "Completed #\(generation): revision \(revision), attempted commands \(commands), renderer \(failure.map { String(describing: $0) } ?? "ok")"
        case let .preparation(value): return preparation(value)
        }
    }
    private static func describe(_ event: QualiaDiagnosticEvent.CorrelatedEvent) -> String {
        switch event {
        case let .installed(analyzer, policy, runtime):
            return "Installed: analyzer \(identity(analyzer)); policy \(identity(policy)); runtime \(identity(runtime))"
        case let .analyzer(value): return "Analyzer: \(identity(value))"
        case let .language(value): return "Language: sha256:\(fingerprint(value))"
        case let .observation(count, valence): return "Observation: \(count) signals, valence \(valence ? "present" : "absent"); scores omitted"
        case let .transition(previous, current): return "State revision: \(previous) → \(current)"
        case let .policy(value, rule, count): return "Policy: \(identity(value)); rule sha256:\(fingerprint(rule)); planned commands \(count)"
        case let .command(kind, failure): return "Command: \(kind); \(failure.map { String(describing: $0) } ?? "succeeded")"
        case let .capability(value): return "Hardware: haptics \(value.supportsHaptics), continuous \(value.supportsContinuousHaptics), curves \(value.supportsParameterCurves)"
        case let .suppressed(value): return "Suppressed: \(value)"
        case let .failure(stage, value): return "Failure: \(stage), \(value.error.description)"
        case let .timing(stage, duration): return "Timing: \(stage), \(milliseconds(duration))"
        case let .preparation(value): return preparation(value)
        case let .lifecycle(value): return "Lifecycle: \(value)"
        case .started: return "Started"
        case let .cancelled(stage): return "Cancelled: \(stage)"
        case let .discarded(stage): return "Discarded stale: \(stage)"
        case let .completed(revision, commands, failure):
            return "Completed: revision \(revision), attempted commands \(commands), renderer \(failure.map { String(describing: $0) } ?? "ok")"
        }
    }
    private static func preparation(_ event: QualiaPreparationDiagnostic) -> String {
        switch event {
        case let .language(policy, source, confidence, outcome):
            return "Language resolution: \(policy), \(source.map { String(describing: $0) } ?? "no source"), \(confidence.map { String(describing: $0) } ?? "no confidence"), \(outcome)"
        case let .context(before, after, outcome):
            return "Context: \(outcome); fragments \(before.fragments) → \(after.fragments), characters \(before.characters) → \(after.characters), UTF-8 bytes \(before.utf8Bytes) → \(after.utf8Bytes)"
        case let .analyzerRejected(reason): return "Analyzer rejected input: \(reason)"
        }
    }
}
