//
//  PlanStreamAdapter.swift
//  Sage
//
//  One plan stream, two shapes: prose is the reply; `{` is a hidden JSON plan.
//

import Foundation

nonisolated struct PlanStreamAdapter: Sendable {
    enum Outcome: Sendable, Equatable {
        case answer(String)
        case envelope(String)
    }

    private enum Kind {
        case undecided
        case answer
        case envelope
    }

    private var kind = Kind.undecided
    private(set) var raw = ""

    mutating func ingest(_ chunk: String) -> String? {
        raw += chunk
        if kind == .undecided {
            kind = Self.classify(raw)
        }
        guard kind == .answer else { return nil }
        return raw
    }

    func finish() -> Outcome {
        kind == .answer ? .answer(raw) : .envelope(raw)
    }

    private static func classify(_ raw: String) -> Kind {
        let text = String(raw.drop(while: \.isWhitespace))
        guard let first = text.first else { return .undecided }
        if first == "{" { return .envelope }
        if text.hasPrefix("```") { return classifyFence(text) }
        return .answer
    }

    private static func classifyFence(_ text: String) -> Kind {
        let after = text.dropFirst(3)
        guard !after.isEmpty else { return .undecided }
        if after.first?.isNewline == true {
            let body = after.drop { $0.isNewline || $0.isWhitespace }
            guard let first = body.first else { return .undecided }
            return first == "{" ? .envelope : .answer
        }
        return classifyFencedLanguage(after)
    }

    private static func classifyFencedLanguage(_ after: Substring) -> Kind {
        let langLine = String(after.prefix { !$0.isNewline && $0 != "{" })
        let lang = langLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lang.isEmpty else { return .undecided }
        if lang == "json" {
            let rest = after.dropFirst(langLine.count).drop { $0.isWhitespace || $0.isNewline }
            guard let first = rest.first else { return .undecided }
            return first == "{" ? .envelope : .answer
        }
        if "json".hasPrefix(lang) { return .undecided }
        return .answer
    }
}
