/// Typed construction and execution failures for the haptic subsystem.
public enum HapticError: Error, Hashable, Sendable {
    case invalidHapticValue
    case invalidHapticIdentifier
    case invalidHapticCurve
    case invalidHapticPattern
    case hapticsUnavailable
    case unsupportedFeature(HapticFeature)
    case enginePreparationFailed
    case invalidLifecycleState
    case invalidCommand
    case playerCreationFailed
    case playerStartFailed
    case playerStopFailed
    case ownershipConflict
    case engineInterrupted
    case engineReset
    case injectedFailure
}

public enum HapticFeature: Hashable, Sendable {
    case continuousHaptics
    case parameterCurves
}

/// A finite normalized haptic parameter in the closed range `0...1`.
public struct HapticValue: Hashable, Codable, Sendable {
    public let rawValue: Float

    public init(_ rawValue: Float) throws {
        guard rawValue.isFinite, (0...1).contains(rawValue) else {
            throw HapticError.invalidHapticValue
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Float.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An event on a validated haptic timeline.
public enum HapticEvent: Hashable, Sendable {
    case transient(
        at: Duration,
        intensity: HapticValue,
        sharpness: HapticValue
    )
    case continuous(
        at: Duration,
        duration: Duration,
        intensity: HapticValue,
        sharpness: HapticValue
    )

    public var startTime: Duration {
        switch self {
        case let .transient(at, _, _), let .continuous(at, _, _, _):
            return at
        }
    }

    public var endTime: Duration {
        switch self {
        case let .transient(at, _, _):
            return at
        case let .continuous(at, duration, _, _):
            return at + duration
        }
    }

    public var isContinuous: Bool {
        if case .continuous = self {
            return true
        }
        return false
    }
}

/// A dynamic parameter controlled by a curve over the pattern timeline.
public enum HapticCurveParameter: Hashable, Sendable {
    case intensity
    case sharpness
}

public struct HapticCurveControlPoint: Hashable, Sendable {
    public let at: Duration
    public let value: HapticValue

    public init(at: Duration, value: HapticValue) throws {
        guard at >= .zero else {
            throw HapticError.invalidHapticCurve
        }
        self.at = at
        self.value = value
    }
}

public struct HapticParameterCurve: Hashable, Sendable {
    public let parameter: HapticCurveParameter
    public let controlPoints: [HapticCurveControlPoint]

    public init(
        parameter: HapticCurveParameter,
        controlPoints: [HapticCurveControlPoint]
    ) throws {
        guard !controlPoints.isEmpty,
              controlPoints.isOrdered(by: \HapticCurveControlPoint.at) else {
            throw HapticError.invalidHapticCurve
        }
        self.parameter = parameter
        self.controlPoints = controlPoints
    }
}

public enum HapticLooping: Hashable, Sendable {
    case none
    case loop(period: Duration)
}

/// A complete, bounded and validated haptic timeline.
public struct HapticPattern: Hashable, Sendable {
    public let duration: Duration
    public let events: [HapticEvent]
    public let curves: [HapticParameterCurve]
    public let looping: HapticLooping

    public init(
        duration: Duration,
        events: [HapticEvent],
        curves: [HapticParameterCurve] = [],
        looping: HapticLooping = .none
    ) throws {
        guard duration > .zero,
              !events.isEmpty,
              events.isOrdered(by: \HapticEvent.startTime),
              events.allSatisfy({ event in
                  event.startTime >= .zero
                      && event.endTime <= duration
                      && (!event.isContinuous || event.endTime > event.startTime)
              }),
              curves.allSatisfy({ curve in
                  guard let last = curve.controlPoints.last else { return false }
                  return last.at <= duration
              }),
              curves.isOrderedByFirstControlPoint else {
            throw HapticError.invalidHapticPattern
        }

        if case let .loop(period) = looping {
            guard period >= duration else {
                throw HapticError.invalidHapticPattern
            }
        }

        self.duration = duration
        self.events = events
        self.curves = curves
        self.looping = looping
    }

    public var requiresContinuousHaptics: Bool {
        events.contains(where: \HapticEvent.isContinuous)
    }
}

private extension Array {
    func isOrdered<Value: Comparable>(by keyPath: KeyPath<Element, Value>) -> Bool {
        zip(self, dropFirst()).allSatisfy {
            $0[keyPath: keyPath] <= $1[keyPath: keyPath]
        }
    }
}

private extension Array where Element == HapticParameterCurve {
    var isOrderedByFirstControlPoint: Bool {
        zip(self, dropFirst()).allSatisfy { left, right in
            guard let leftTime = left.controlPoints.first?.at,
                  let rightTime = right.controlPoints.first?.at else {
                return false
            }
            return leftTime <= rightTime
        }
    }
}
