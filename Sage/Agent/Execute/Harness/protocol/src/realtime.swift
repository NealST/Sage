//
//  realtime.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/realtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Realtime thread item types for rollout persistence. Sage defers the voice
//  realtime form factor but preserves these wire types for rollout compatibility.
//  serde tag="type" + rename_all="snake_case" → hand-coded Codable with
//  discriminator key.
//

import Foundation

/// A realtime thread item persisted in the canonical rollout.
public struct RealtimeItem: Codable, Equatable, Sendable {
    public var id: String
    public var realtimeSessionId: String
    public var content: RealtimeItemContent

    enum CodingKeys: String, CodingKey {
        case id
        case realtimeSessionId = "realtime_session_id"
    }

    public init(id: String, realtimeSessionId: String, content: RealtimeItemContent) {
        self.id = id
        self.realtimeSessionId = realtimeSessionId
        self.content = content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        realtimeSessionId = try container.decode(String.self, forKey: .realtimeSessionId)
        content = try RealtimeItemContent(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(realtimeSessionId, forKey: .realtimeSessionId)
        try content.encode(to: encoder)
    }
}

/// The minimum facts needed to interleave realtime speech and agent work.
///
/// Wire: `#[serde(tag = "type", rename_all = "snake_case")]`.
public enum RealtimeItemContent: Equatable, Sendable {
    case realtimeSessionStarted
    case transcriptSegment(role: RealtimeTranscriptRole, text: String)
    case bemItemPromoted(turnId: String, itemId: String, presentation: BemItemPresentation)
    case realtimeSessionClosed(outcome: RealtimeSessionOutcome)
}

extension RealtimeItemContent: Codable {
    private enum TypeKey: String, CodingKey { case type }

    private enum Variant: String, Codable {
        case realtimeSessionStarted = "realtime_session_started"
        case transcriptSegment = "transcript_segment"
        case bemItemPromoted = "bem_item_promoted"
        case realtimeSessionClosed = "realtime_session_closed"
    }

    private enum TranscriptKeys: String, CodingKey {
        case role, text
    }
    private enum BemKeys: String, CodingKey {
        case turnId = "turn_id"
        case itemId = "item_id"
        case presentation
    }
    private enum ClosedKeys: String, CodingKey {
        case outcome
    }

    public init(from decoder: any Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let variant = try typeContainer.decode(Variant.self, forKey: .type)
        switch variant {
        case .realtimeSessionStarted:
            self = .realtimeSessionStarted
        case .transcriptSegment:
            let c = try decoder.container(keyedBy: TranscriptKeys.self)
            self = .transcriptSegment(
                role: try c.decode(RealtimeTranscriptRole.self, forKey: .role),
                text: try c.decode(String.self, forKey: .text)
            )
        case .bemItemPromoted:
            let c = try decoder.container(keyedBy: BemKeys.self)
            self = .bemItemPromoted(
                turnId: try c.decode(String.self, forKey: .turnId),
                itemId: try c.decode(String.self, forKey: .itemId),
                presentation: try c.decode(BemItemPresentation.self, forKey: .presentation)
            )
        case .realtimeSessionClosed:
            let c = try decoder.container(keyedBy: ClosedKeys.self)
            self = .realtimeSessionClosed(
                outcome: try c.decode(RealtimeSessionOutcome.self, forKey: .outcome)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var typeContainer = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .realtimeSessionStarted:
            try typeContainer.encode(Variant.realtimeSessionStarted, forKey: .type)
        case let .transcriptSegment(role, text):
            try typeContainer.encode(Variant.transcriptSegment, forKey: .type)
            var c = encoder.container(keyedBy: TranscriptKeys.self)
            try c.encode(role, forKey: .role)
            try c.encode(text, forKey: .text)
        case let .bemItemPromoted(turnId, itemId, presentation):
            try typeContainer.encode(Variant.bemItemPromoted, forKey: .type)
            var c = encoder.container(keyedBy: BemKeys.self)
            try c.encode(turnId, forKey: .turnId)
            try c.encode(itemId, forKey: .itemId)
            try c.encode(presentation, forKey: .presentation)
        case let .realtimeSessionClosed(outcome):
            try typeContainer.encode(Variant.realtimeSessionClosed, forKey: .type)
            var c = encoder.container(keyedBy: ClosedKeys.self)
            try c.encode(outcome, forKey: .outcome)
        }
    }
}

public enum RealtimeSessionOutcome: String, Codable, Equatable, Sendable {
    case ended
    case failed
}

public enum RealtimeTranscriptRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

/// How an existing agent item is presented in the realtime conversation.
///
/// Wire: `#[serde(tag = "type", rename_all = "snake_case")]`.
public enum BemItemPresentation: Equatable, Sendable {
    case wholeItem
    case inlineMarkdown
    case inlineVisualization(index: UInt32)
}

extension BemItemPresentation: Codable {
    private enum TypeKey: String, CodingKey { case type }
    private enum Variant: String, Codable {
        case wholeItem = "whole_item"
        case inlineMarkdown = "inline_markdown"
        case inlineVisualization = "inline_visualization"
    }
    private enum VisKeys: String, CodingKey { case index }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        let variant = try c.decode(Variant.self, forKey: .type)
        switch variant {
        case .wholeItem:
            self = .wholeItem
        case .inlineMarkdown:
            self = .inlineMarkdown
        case .inlineVisualization:
            let vc = try decoder.container(keyedBy: VisKeys.self)
            self = .inlineVisualization(index: try vc.decode(UInt32.self, forKey: .index))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .wholeItem:
            try c.encode(Variant.wholeItem, forKey: .type)
        case .inlineMarkdown:
            try c.encode(Variant.inlineMarkdown, forKey: .type)
        case let .inlineVisualization(index):
            try c.encode(Variant.inlineVisualization, forKey: .type)
            var vc = encoder.container(keyedBy: VisKeys.self)
            try vc.encode(index, forKey: .index)
        }
    }
}
