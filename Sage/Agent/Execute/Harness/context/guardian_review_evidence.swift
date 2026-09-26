//
//  guardian_review_evidence.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_review_evidence.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Full evidence formatting waits for the guardian crate. This keeps the
//  record/fragment types so session history can store reviewer input.
//

import CodexProtocol
import Foundation

public struct GuardianUserInputSnapshot: Equatable, Sendable {
    public var text: String
    public var recordedAt: Date?

    public init(text: String, recordedAt: Date? = nil) {
        self.text = text
        self.recordedAt = recordedAt
    }
}

public struct GuardianReviewEvidenceRecord: Equatable, Sendable {
    public var userInput: GuardianUserInputSnapshot?
    public var notes: [String]

    public init(userInput: GuardianUserInputSnapshot? = nil, notes: [String] = []) {
        self.userInput = userInput
        self.notes = notes
    }
}

public struct GuardianReviewEvidenceFragment: ContextualUserFragment, Equatable, Sendable {
    public var record: GuardianReviewEvidenceRecord

    public init(_ record: GuardianReviewEvidenceRecord) {
        self.record = record
    }

    public var contentKind: ContentItemKind { ContentItemKind("guardian.review_evidence") }
    public var role: String { "developer" }
    public var openMarker: String { "<guardian_review_evidence>" }
    public var closeMarker: String { "</guardian_review_evidence>" }
    public var body: String {
        var lines: [String] = []
        if let userInput = record.userInput {
            lines.append("User input:\n\(userInput.text)")
        }
        if !record.notes.isEmpty {
            lines.append("Notes:\n\(record.notes.joined(separator: "\n"))")
        }
        return lines.joined(separator: "\n\n")
    }
}

public typealias GuardianReviewEvidence = GuardianReviewEvidenceFragment
