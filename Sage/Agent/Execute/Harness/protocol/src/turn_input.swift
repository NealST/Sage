//
//  turn_input.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/turn_input.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `CyberAccessProgram` is defined in openai_models.swift (same module).
//

import Foundation

/// Result of stopping an unfinished root turn so another worker can recover it.
public enum SuspendTurnOutcome: Equatable, Sendable {
    case suspended(turnId: String)
    case notActive
    /// A currently loaded descendant would remain running after root handoff.
    case hasLiveDescendants
    case unsupportedTask
}

/// Input consumed by a regular turn.
///
/// Default serde externally-tagged enum (variant names as written).
public enum TurnInput: Codable, Equatable, Sendable {
    case userInput(content: [UserInput], clientId: String?)
    case responseItem(ResponseItem)
    case interAgentCommunication(InterAgentCommunication)

    private enum ExternalKey: String, CodingKey {
        case userInput = "UserInput"
        case responseItem = "ResponseItem"
        case interAgentCommunication = "InterAgentCommunication"
    }

    private enum UserInputKeys: String, CodingKey {
        case content
        case clientId = "client_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ExternalKey.self)
        if container.contains(.userInput) {
            let nested = try container.nestedContainer(
                keyedBy: UserInputKeys.self, forKey: .userInput)
            self = .userInput(
                content: try nested.decode([UserInput].self, forKey: .content),
                clientId: try nested.decodeIfPresent(String.self, forKey: .clientId))
        } else if container.contains(.responseItem) {
            self = .responseItem(try container.decode(ResponseItem.self, forKey: .responseItem))
        } else if container.contains(.interAgentCommunication) {
            self = .interAgentCommunication(
                try container.decode(InterAgentCommunication.self, forKey: .interAgentCommunication))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown TurnInput variant"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ExternalKey.self)
        switch self {
        case .userInput(let content, let clientId):
            var nested = container.nestedContainer(
                keyedBy: UserInputKeys.self, forKey: .userInput)
            try nested.encode(content, forKey: .content)
            try nested.encode(clientId, forKey: .clientId)
        case .responseItem(let item):
            try container.encode(item, forKey: .responseItem)
        case .interAgentCommunication(let comm):
            try container.encode(comm, forKey: .interAgentCommunication)
        }
    }
}

/// One turn input and the context that follows it through submission.
public struct TurnInputRequest: Equatable, Sendable {
    public var input: TurnInput
    public var threadSettings: ThreadSettingsOverrides
    public var start: TurnStartOptions
    public var additionalContext: [String: AdditionalContextEntry]
    public var responsesapiClientMetadata: [String: String]?
    public var trace: W3cTraceContext?

    public init(
        input: TurnInput,
        threadSettings: ThreadSettingsOverrides = ThreadSettingsOverrides(),
        start: TurnStartOptions = TurnStartOptions(),
        additionalContext: [String: AdditionalContextEntry] = [:],
        responsesapiClientMetadata: [String: String]? = nil,
        trace: W3cTraceContext? = nil
    ) {
        self.input = input
        self.threadSettings = threadSettings
        self.start = start
        self.additionalContext = additionalContext
        self.responsesapiClientMetadata = responsesapiClientMetadata
        self.trace = trace
    }

    /// Creates turn input that can be passed to one of the submission methods.
    public static func new(_ input: TurnInput) -> TurnInputRequest {
        TurnInputRequest(input: input)
    }

    /// Creates ordinary user input without a client-provided message id.
    public static func userInput(_ content: [UserInput]) -> TurnInputRequest {
        .new(.userInput(content: content, clientId: nil))
    }

    public func withThreadSettings(_ threadSettings: ThreadSettingsOverrides) -> TurnInputRequest {
        var copy = self
        copy.threadSettings = threadSettings
        return copy
    }

    public func onStart(_ start: TurnStartOptions) -> TurnInputRequest {
        var copy = self
        copy.start = start
        return copy
    }

    public func withAdditionalContext(
        _ additionalContext: [String: AdditionalContextEntry]
    ) -> TurnInputRequest {
        var copy = self
        copy.additionalContext = additionalContext
        return copy
    }

    public func withResponsesMetadata(
        _ responsesapiClientMetadata: [String: String]?
    ) -> TurnInputRequest {
        var copy = self
        copy.responsesapiClientMetadata = responsesapiClientMetadata
        return copy
    }

    public func withTrace(_ trace: W3cTraceContext?) -> TurnInputRequest {
        var copy = self
        copy.trace = trace
        return copy
    }
}

/// Request to resume sampling for an interrupted regular turn.
public struct RecoverTurnRequest: Equatable, Sendable {
    public var turnId: String
    public var threadSettings: ThreadSettingsOverrides
    public var trace: W3cTraceContext?
    /// Program recorded in the interrupted turn's persisted context.
    public var cyberAccessProgram: CyberAccessProgram?

    public init(
        turnId: String,
        threadSettings: ThreadSettingsOverrides = ThreadSettingsOverrides(),
        trace: W3cTraceContext? = nil,
        cyberAccessProgram: CyberAccessProgram? = nil
    ) {
        self.turnId = turnId
        self.threadSettings = threadSettings
        self.trace = trace
        self.cyberAccessProgram = cyberAccessProgram
    }
}

/// How Core should route submitted turn input.
public enum TurnInputMode: Equatable, Sendable {
    /// Start a regular turn when idle, otherwise steer the active regular turn.
    case startOrSteer
    /// Start only when the thread is idle.
    case startIfIdle
    /// Start an internal continuation when idle.
    case continueIfIdle(expectedPreviousTurnId: String)
    /// Steer only if this exact turn is active.
    case steer(expectedTurnId: String)
}

/// Options for the new-turn branch of a submission.
public struct TurnStartOptions: Equatable, Sendable {
    public var turnTrigger: String?
    public var finalOutputJsonSchema: JSONValue?
    public var serviceTier: String?
    public var parentTurnId: String?
    public var rootTurnId: String?
    public var cyberAccessProgram: CyberAccessProgram?

    public init(
        turnTrigger: String? = nil,
        finalOutputJsonSchema: JSONValue? = nil,
        serviceTier: String? = nil,
        parentTurnId: String? = nil,
        rootTurnId: String? = nil,
        cyberAccessProgram: CyberAccessProgram? = nil
    ) {
        self.turnTrigger = turnTrigger
        self.finalOutputJsonSchema = finalOutputJsonSchema
        self.serviceTier = serviceTier
        self.parentTurnId = parentTurnId
        self.rootTurnId = rootTurnId
        self.cyberAccessProgram = cyberAccessProgram
    }
}

/// What Core did with input submitted through `start_or_steer_turn`.
public enum TurnInputSubmission: Equatable, Sendable {
    case started(turnId: String)
    case steered(turnId: String)
    case notSubmitted(reason: NotSubmittedReason)
}

/// What Core did with input submitted only for an idle turn start.
public enum StartIfIdleSubmission: Equatable, Sendable {
    case started(turnId: String)
    case notSubmitted(reason: NotSubmittedReason)
}

/// What Core did with input submitted only for steering.
public enum SteerSubmission: Equatable, Sendable {
    case steered(turnId: String)
    case notSubmitted(reason: NotSubmittedReason)
}

/// Why Core did not accept submitted turn input for turn processing.
public enum NotSubmittedReason: Equatable, Sendable {
    case superseded
    case serverDraining
    case notIdle
    case pendingTriggerTurn
    case planMode
    case noActiveTurn
    case expectedTurnMismatch(expected: String, actual: String)
    case activeTurnNotSteerable(turnKind: NonSteerableTurnKind)
    case activeTurnOutputSchemaMismatch
    case emptyInput
}
