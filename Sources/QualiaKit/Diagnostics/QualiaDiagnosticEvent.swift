import CryptoKit
import Foundation

/// SHA-256 of installation metadata, never of input text. Hosts can compare
/// against the same identity/version without exposing arbitrary adapter strings.
public struct QualiaDiagnosticFingerprint: Hashable, Sendable {
    public let bytes: [UInt8]
    public init(metadata: String) { bytes = Array(SHA256.hash(data: Data(metadata.utf8))) }
}

public struct QualiaDiagnosticIdentity: Hashable, Sendable {
    public let identifier: QualiaDiagnosticFingerprint
    public let version: QualiaDiagnosticFingerprint
    public init(identifier: String, version: String) {
        self.identifier = .init(metadata: identifier)
        self.version = .init(metadata: version)
    }
}

/// Schema v1 has no free-form strings, input IDs, tensors, or signal scores.
/// Runtime-generated UUIDs correlate sessions; generations correlate requests.
public enum QualiaDiagnosticEvent: Hashable, Sendable {
    public enum Stage: Hashable, Sendable { case preparation, analysis, dispatch }
    public enum LifecycleEvent: Hashable, Sendable { case created, reset, suspended, resumed, cleanupFailed }
    public enum Suppression: Hashable, Sendable {
        case disabled, zeroIntensity, continuousDisabled, hardwareUnavailable, durationLimit, rendererFailure
    }
    public enum TimingStage: Hashable, Sendable { case preparation, inference, stateAndPolicy, dispatch }
    public enum ModelStage: Hashable, Sendable {
        case compiled, loaded, tokenized, prepared, predictionStarted, predicted, transformed
    }
    public enum CommandKind: Hashable, Sendable { case play, start, replace, stop, stopChannel, stopAll }
    public static let schemaVersion = 1
    public static let runtimeVersion = "qualia-runtime-v2"
    case fallbackSelected(cause: QualiaFallbackCause, analyzer: QualiaDiagnosticIdentity?)
    case model(stage: ModelStage, identity: QualiaDiagnosticIdentity,
               contract: QualiaDiagnosticFingerprint, duration: Duration, tokenCount: Int?, truncatedTokenCount: Int?)
    case lifecycle(LifecycleEvent)
    case started(generation: UInt64)
    case failed(generation: UInt64, stage: Stage)
    case discarded(generation: UInt64, stage: Stage)
    case cancelled(generation: UInt64, stage: Stage)
    case completed(generation: UInt64, revision: UInt64, attemptedCommands: Int, rendererFailure: HapticError?)
    case preparation(QualiaPreparationDiagnostic)
    case correlated(session: UUID, generation: UInt64, event: CorrelatedEvent)

    public enum CorrelatedEvent: Hashable, Sendable {
        case lifecycle(LifecycleEvent)
        case started
        case cancelled(Stage)
        case discarded(Stage)
        case completed(revision: UInt64, attemptedCommands: Int, rendererFailure: HapticError?)
        case preparation(QualiaPreparationDiagnostic)
        case installed(analyzer: QualiaDiagnosticIdentity?, policy: QualiaDiagnosticIdentity?, runtime: QualiaDiagnosticIdentity)
        case analyzer(QualiaDiagnosticIdentity)
        case failure(stage: Stage, error: QualiaDiagnosticFailure)
        case language(QualiaDiagnosticFingerprint)
        case observation(signalCount: Int, hasValence: Bool)
        case transition(previous: UInt64, current: UInt64)
        case policy(identity: QualiaDiagnosticIdentity, rule: QualiaDiagnosticFingerprint, commandCount: Int)
        case command(CommandKind, failure: HapticError?)
        case capability(HapticCapabilities)
        case suppressed(Suppression)
        case timing(TimingStage, Duration)
    }
}

/// Compatibility spelling for clients of spec 0010.
public typealias QualiaSessionDiagnostic = QualiaDiagnosticEvent

public protocol QualiaDiagnosticsSink: Sendable {
    /// Must return promptly, support concurrent calls, and never perform
    /// synchronous transport. Buffering must be bounded with an explicit drop
    /// policy. Core cannot enforce a host implementation's I/O behavior.
    var isEnabled: Bool { get }
    func record(_ event: QualiaDiagnosticEvent)
}
public extension QualiaDiagnosticsSink { var isEnabled: Bool { true } }

public struct NoOpQualiaDiagnosticsSink: QualiaDiagnosticsSink {
    public init() {}
    public var isEnabled: Bool { false }
    public func record(_ event: QualiaDiagnosticEvent) {}
}

public extension QualiaDiagnosticsSink {
    func emit(_ event: @autoclosure () -> QualiaDiagnosticEvent) {
        if isEnabled { record(event()) }
    }
}

/// Construction always removes arbitrary language/adapter identity strings.
public struct QualiaDiagnosticFailure: Hashable, Sendable {
    public let error: QualiaError
    public static func redacted(_ error: any Error, stage: QualiaDiagnosticEvent.Stage) -> Self {
        Self(error: QualiaError.redacted(error, stage: stage))
    }
}
