/// An explicit policy that never creates physical feedback.
public struct NoReactionPolicy: QualiaReactionPolicy, Sendable {
    public static let identifier = "qualia.no-reaction"
    public static let version = "1.0.0"

    public init() {}

    public func plan(
        for transition: QualiaSceneTransition,
        context: QualiaReactionContext
    ) -> QualiaReactionPlan {
        _ = transition
        return QualiaReactionPlan(
            hapticCommands: [],
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: "no-reaction-policy"
            ),
            nextState: context.state
        )
    }
}
