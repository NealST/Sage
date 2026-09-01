//
//  PlanStreamAdapter.swift
//  Sage
//
//  A plan stream can splice two shapes: markdown prose, then a hidden JSON plan.
//  Prose is shown as it arrives. JSON never is — reserve a card until it parses.
//

import Foundation

nonisolated struct PlanStreamAdapter: Sendable {
    enum Outcome: Sendable, Equatable {
        case answer(String)
        case envelope(raw: String, visible: String)
    }

    private(set) var raw = ""
    private(set) var visible = ""
    private var jsonStarted = false

    var isEnvelope: Bool { jsonStarted }

    var isReservingWorkPlan: Bool { jsonStarted }

    mutating func ingest(_ chunk: String) -> String? {
        raw += chunk
        if !jsonStarted, let start = Self.planJSONStart(in: raw) {
            jsonStarted = true
            visible = String(raw[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if !jsonStarted {
            visible = String(raw.drop(while: \.isWhitespace))
        }
        return visible.isEmpty ? nil : visible
    }

    func finish() -> Outcome {
        if jsonStarted {
            return .envelope(raw: raw, visible: visible)
        }
        if let start = Self.planJSONStart(in: raw) {
            let visible = String(raw[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
            return .envelope(raw: raw, visible: visible)
        }
        return .answer(raw)
    }

    /// First index of a work-plan JSON object or ` ```json ` fence.
    static func planJSONStart(in raw: String) -> String.Index? {
        if let fence = jsonFenceStart(in: raw) { return fence }
        if let brace = firstLineLeadingBrace(in: raw) { return brace }
        if let brace = raw.firstIndex(of: "{"), looksLikePlanObject(raw[brace...]) {
            return brace
        }
        return nil
    }

    private static func jsonFenceStart(in raw: String) -> String.Index? {
        guard let fence = raw.range(of: "```")?.lowerBound else { return nil }
        let afterFence = raw[raw.index(fence, offsetBy: 3)...]
        let langLine = String(afterFence.prefix { !$0.isNewline && $0 != "{" })
        let lang = langLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lang == "json" { return fence }
        if afterFence.first?.isNewline == true {
            let body = afterFence.drop { $0.isNewline || $0.isWhitespace }
            if body.first == "{" { return fence }
        }
        if lang.isEmpty || "json".hasPrefix(lang) { return nil }
        return nil
    }

    private static func firstLineLeadingBrace(in raw: String) -> String.Index? {
        var lineStart = raw.startIndex
        var index = raw.startIndex
        while index < raw.endIndex {
            if raw[index] == "\n" {
                index = raw.index(after: index)
                lineStart = index
                continue
            }
            let leading = raw[lineStart..<index]
            if leading.allSatisfy(\.isWhitespace), raw[index] == "{" {
                return index
            }
            if !raw[index].isWhitespace, raw[index] != "{" {
                guard let newline = raw[index...].firstIndex(of: "\n") else { return nil }
                index = raw.index(after: newline)
                lineStart = index
                continue
            }
            index = raw.index(after: index)
        }
        return nil
    }

    private static func looksLikePlanObject(_ fromBrace: Substring) -> Bool {
        fromBrace.contains(#""kind""#)
    }
}
