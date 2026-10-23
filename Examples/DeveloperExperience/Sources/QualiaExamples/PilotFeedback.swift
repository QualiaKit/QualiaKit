import Foundation
import QualiaKit

/// Host-owned, opt-in feedback. There is deliberately no transport or text field.
public struct PilotFeedback: Encodable, Sendable {
    public enum Judgment: String, Encodable, Sendable {
        case appropriate, inappropriate, uncertain
    }

    /// Installation metadata only. Never pass input text, IDs or user attributes.
    public struct BuildIdentity: Sendable {
        let runtime: QualiaDiagnosticIdentity
        let model: QualiaDiagnosticIdentity
        let policy: QualiaDiagnosticIdentity
        let effect: QualiaDiagnosticIdentity

        public init(runtime: QualiaDiagnosticIdentity, model: QualiaDiagnosticIdentity,
                    policy: QualiaDiagnosticIdentity, effect: QualiaDiagnosticIdentity) {
            self.runtime = runtime
            self.model = model
            self.policy = policy
            self.effect = effect
        }
    }

    public let judgment: Judgment
    public let hapticsDisabled: Bool
    private let identity: BuildIdentity

    public static func make(consented: Bool, judgment: Judgment, hapticsDisabled: Bool,
                            identity: BuildIdentity) -> Self? {
        guard consented else { return nil }
        return Self(judgment: judgment, hapticsDisabled: hapticsDisabled, identity: identity)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, judgment, hapticsDisabled, runtime, model, policy, effect
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(judgment, forKey: .judgment)
        try container.encode(hapticsDisabled, forKey: .hapticsDisabled)
        for (key, value) in [(CodingKeys.runtime, identity.runtime), (.model, identity.model),
                             (.policy, identity.policy), (.effect, identity.effect)] {
            let hex: (QualiaDiagnosticFingerprint) -> String = { $0.bytes.map { String(format: "%02x", $0) }.joined() }
            try container.encode(["identifier": hex(value.identifier), "version": hex(value.version)], forKey: key)
        }
    }
}
