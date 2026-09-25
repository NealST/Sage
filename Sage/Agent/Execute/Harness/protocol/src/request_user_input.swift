//
//  request_user_input.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/request_user_input.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  User input request/response types for the elicitation tool. serde rename
//  attributes (camelCase aliases) are reproduced via CodingKeys. The custom
//  Deserialize impl for RequestUserInputEvent defaults `isBlocking` to true
//  when absent, matching upstream wire compat.
//

import Foundation

public struct RequestUserInputQuestionOption: Codable, Equatable, Sendable {
    public var label: String
    public var description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct RequestUserInputQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var header: String
    public var question: String
    public var isOther: Bool
    public var isSecret: Bool
    public var options: [RequestUserInputQuestionOption]?

    enum CodingKeys: String, CodingKey {
        case id, header, question
        case isOther
        case isSecret
        case options
    }

    public init(
        id: String,
        header: String,
        question: String,
        isOther: Bool = false,
        isSecret: Bool = false,
        options: [RequestUserInputQuestionOption]? = nil
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.isOther = isOther
        self.isSecret = isSecret
        self.options = options
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        header = try container.decode(String.self, forKey: .header)
        question = try container.decode(String.self, forKey: .question)
        isOther = try container.decodeIfPresent(Bool.self, forKey: .isOther) ?? false
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        options = try container.decodeIfPresent(
            [RequestUserInputQuestionOption].self, forKey: .options
        )
    }
}

public struct RequestUserInputArgs: Codable, Equatable, Sendable {
    public var questions: [RequestUserInputQuestion]
    public var isBlocking: Bool
    /// @deprecated Use `isBlocking` to decide whether the request should block.
    public var autoResolutionMs: UInt64?

    enum CodingKeys: String, CodingKey {
        case questions
        case isBlocking
        case autoResolutionMs
    }

    public init(
        questions: [RequestUserInputQuestion],
        isBlocking: Bool,
        autoResolutionMs: UInt64? = nil
    ) {
        self.questions = questions
        self.isBlocking = isBlocking
        self.autoResolutionMs = autoResolutionMs
    }
}

public struct RequestUserInputAnswer: Codable, Equatable, Sendable {
    public var answers: [String]

    public init(answers: [String]) {
        self.answers = answers
    }
}

public struct RequestUserInputResponse: Codable, Equatable, Sendable {
    public var answers: [String: RequestUserInputAnswer]

    public init(answers: [String: RequestUserInputAnswer]) {
        self.answers = answers
    }
}

public struct RequestUserInputEvent: Equatable, Sendable {
    /// Responses API call id for the associated tool call, if available.
    public var callId: String
    /// Turn ID that this request belongs to.
    public var turnId: String
    public var questions: [RequestUserInputQuestion]
    public var isBlocking: Bool
    /// @deprecated Use `isBlocking` to decide whether the request should block.
    public var autoResolutionMs: UInt64?

    public init(
        callId: String,
        turnId: String = "",
        questions: [RequestUserInputQuestion],
        isBlocking: Bool,
        autoResolutionMs: UInt64? = nil
    ) {
        self.callId = callId
        self.turnId = turnId
        self.questions = questions
        self.isBlocking = isBlocking
        self.autoResolutionMs = autoResolutionMs
    }
}

extension RequestUserInputEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case turnId = "turn_id"
        case questions
        case isBlocking
        case autoResolutionMs
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(questions, forKey: .questions)
        try container.encode(isBlocking, forKey: .isBlocking)
        try container.encodeIfPresent(autoResolutionMs, forKey: .autoResolutionMs)
    }

    /// Custom decode: defaults `isBlocking` to `true` when absent (upstream compat).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        questions = try container.decode([RequestUserInputQuestion].self, forKey: .questions)
        isBlocking = try container.decodeIfPresent(Bool.self, forKey: .isBlocking) ?? true
        autoResolutionMs = try container.decodeIfPresent(UInt64.self, forKey: .autoResolutionMs)
    }
}
