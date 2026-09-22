#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Receives a session result on the main actor so callers can update UI state
/// without creating another actor hop.
public typealias QualiaReactionResultHandler =
    @MainActor @Sendable (Result<QualiaResponse, any Error>) -> Void

/// Invalid values are rejected before a live-reaction modifier is installed.
public enum QualiaLiveReactionConfigurationError: Error, Hashable, Sendable {
    case negativeDebounce
    case negativeMinimumCharacters
}

/// Immutable typing-preview behavior. A live preview still requires its own
/// explicitly constructed `QualiaSession`; this value never creates one.
public struct QualiaLiveReactionConfiguration: Hashable, Sendable {
    public let debounce: Duration
    public let minimumCharacters: Int

    public init(
        debounce: Duration = .milliseconds(350),
        minimumCharacters: Int = 3
    ) throws {
        guard debounce >= .zero else {
            throw QualiaLiveReactionConfigurationError.negativeDebounce
        }
        guard minimumCharacters >= 0 else {
            throw QualiaLiveReactionConfigurationError.negativeMinimumCharacters
        }
        self.debounce = debounce
        self.minimumCharacters = minimumCharacters
    }

    private init(validatedDebounce debounce: Duration, minimumCharacters: Int) {
        self.debounce = debounce
        self.minimumCharacters = minimumCharacters
    }

    public static let `default` = QualiaLiveReactionConfiguration(
        validatedDebounce: .milliseconds(350),
        minimumCharacters: 3
    )
}

private struct QualiaEventReactionModifier<EventID: Hashable & Sendable>: ViewModifier {
    let eventID: EventID
    let input: QualiaInput
    let session: QualiaSession
    let onResult: QualiaReactionResultHandler?
    @State private var coordinator = QualiaEventReactionCoordinator<EventID>()

    func body(content: Content) -> some View {
        content.task(id: eventID) {
            do {
                guard let response = try await coordinator.process(
                    eventID: eventID,
                    input: input,
                    session: session
                ) else { return }
                onResult?(.success(response))
            } catch {
                onResult?(.failure(error))
            }
        }
    }
}

private struct QualiaLiveReactionModifier: ViewModifier {
    @Binding var text: String
    let configuration: QualiaLiveReactionConfiguration
    let session: QualiaSession
    let onResult: QualiaReactionResultHandler?
    @State private var coordinator: QualiaLiveReactionCoordinator

    init(
        text: Binding<String>,
        configuration: QualiaLiveReactionConfiguration,
        session: QualiaSession,
        onResult: QualiaReactionResultHandler?,
        clock: any QualiaClock = QualiaContinuousClock()
    ) {
        _text = text
        self.configuration = configuration
        self.session = session
        self.onResult = onResult
        _coordinator = State(initialValue: QualiaLiveReactionCoordinator(clock: clock))
    }

    func body(content: Content) -> some View {
        content.task(id: text) {
            do {
                guard let response = try await coordinator.process(
                    text: text,
                    configuration: configuration,
                    session: session
                ) else { return }
                onResult?(.success(response))
            } catch {
                onResult?(.failure(error))
            }
        }
    }
}

extension View {
    /// Processes one host-accepted event. Recomputing the view with the same
    /// stable identity does not submit the input again.
    ///
    /// The host owns `session` and remains responsible for calling
    /// `suspend()`, `resume()`, or `reset()` at its screen/room boundary.
    public func qualiaReaction<EventID: Hashable & Sendable>(
        eventID: EventID,
        input: QualiaInput,
        session: QualiaSession,
        onResult: QualiaReactionResultHandler? = nil
    ) -> some View {
        modifier(QualiaEventReactionModifier(
            eventID: eventID,
            input: input,
            session: session,
            onResult: onResult
        ))
    }

    /// Debounces draft text before submitting it to an explicitly injected
    /// session. Pass a session dedicated to preview if draft analysis must not
    /// advance production scene state.
    ///
    /// The preview input has no explicit language, so the injected session's
    /// language resolver must support detection when language is absent.
    public func qualiaLiveReaction(
        text: Binding<String>,
        configuration: QualiaLiveReactionConfiguration,
        session: QualiaSession,
        onResult: QualiaReactionResultHandler? = nil
    ) -> some View {
        modifier(QualiaLiveReactionModifier(
            text: text,
            configuration: configuration,
            session: session,
            onResult: onResult
        ))
    }

    /// Convenience spelling for the common live-preview controls.
    /// Invalid arguments fail immediately while constructing the modifier.
    public func qualiaLiveReaction(
        text: Binding<String>,
        debounce: Duration = .milliseconds(350),
        minimumCharacters: Int = 3,
        session: QualiaSession,
        onResult: QualiaReactionResultHandler? = nil
    ) -> some View {
        let configuration: QualiaLiveReactionConfiguration
        do {
            configuration = try .init(
                debounce: debounce,
                minimumCharacters: minimumCharacters
            )
        } catch {
            preconditionFailure("Invalid Qualia live reaction configuration: \(error)")
        }
        return qualiaLiveReaction(
            text: text,
            configuration: configuration,
            session: session,
            onResult: onResult
        )
    }
}

/// Actor isolation makes the secondary duplicate check atomic even if a host
/// temporarily installs the same modifier task more than once.
actor QualiaEventReactionCoordinator<EventID: Hashable & Sendable> {
    private var lastEventID: EventID?

    func process(
        eventID: EventID,
        input: QualiaInput,
        session: QualiaSession
    ) async throws -> QualiaResponse? {
        guard lastEventID != eventID else { return nil }
        lastEventID = eventID
        return try await session.process(input)
    }
}

/// Testable debounce adapter. Its generation check also protects against a
/// custom clock whose `sleep` implementation returns after cancellation.
actor QualiaLiveReactionCoordinator {
    private let clock: any QualiaClock
    private var generation: UInt64 = 0

    init(clock: any QualiaClock) {
        self.clock = clock
    }

    func process(
        text: String,
        configuration: QualiaLiveReactionConfiguration,
        session: QualiaSession
    ) async throws -> QualiaResponse? {
        generation &+= 1
        let requestGeneration = generation

        guard !text.allSatisfy(\.isWhitespace),
              text.count >= configuration.minimumCharacters else {
            return nil
        }

        try await clock.sleep(for: configuration.debounce)
        try Task.checkCancellation()
        guard requestGeneration == generation else { throw CancellationError() }

        let input = try QualiaInput(
            id: QualiaInputID(rawValue: "qualia-live-\(UUID().uuidString)"),
            text: text
        )
        return try await session.process(input)
    }
}
#endif
