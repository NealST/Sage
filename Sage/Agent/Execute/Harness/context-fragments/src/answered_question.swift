//
//  answered_question.swift
//  CodexContextFragments
//
//  Port of codex-rs/context-fragments/src/answered_question.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Async answers use the desktop's existing reply envelope and stable question
//  identity. Model-authored framing is bounded; oversized identities use the
//  previous plain-text format. `floor_char_boundary` is a UTF-8 byte budget
//  snapped to a Swift `Character` boundary.
//

import CodexProtocol
import Foundation

/// Identifies an answered question without repeating an unbounded model-authored prompt.
public struct AnsweredQuestion: ContextualUserFragment, Sendable {
    public var questionId: String?
    public var question: String
    public var answer: String

    public init(questionId: String, question: String, answer: String) {
        let clipped = floorCharBoundary(question, maxBytes: min(512, question.utf8.count))
        self.questionId = questionId.utf8.count <= 512 ? questionId : nil
        self.question = clipped
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        self.answer = answer
    }

    public var contentKind: ContentItemKind {
        ContentItemKind("user.answered_question")
    }

    public var role: String { "user" }

    public var openMarker: String {
        questionId == nil ? "" : Self.typeMarkers().0
    }

    public var closeMarker: String {
        questionId == nil ? "" : Self.typeMarkers().1
    }

    public static func typeMarkers() -> (String, String) {
        (
            "<send_user_message_question_reply>",
            "</send_user_message_question_reply>"
        )
    }

    public var body: String {
        guard let questionId else {
            return "> \(question)\n\n\(answer)"
        }
        let replies: JSONValue = .array([
            .object([
                "answer": .string(answer),
                "question": .string(question),
                "questionItemId": .string(questionId),
            ])
        ])
        return "\n\(replies.encodedString())\n"
    }
}

func floorCharBoundary(_ text: String, maxBytes: Int) -> String {
    if maxBytes <= 0 { return "" }
    if text.utf8.count <= maxBytes { return text }
    var used = 0
    var end = text.startIndex
    for character in text {
        let size = character.utf8.count
        if used + size > maxBytes { break }
        used += size
        end = text.index(after: end)
    }
    return String(text[..<end])
}
