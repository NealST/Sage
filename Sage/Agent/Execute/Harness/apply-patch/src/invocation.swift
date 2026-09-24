//
//  invocation.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/invocation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Same two whole-script bash forms as the upstream Tree-sitter query, plus
//  PowerShell here-strings. Extra statements do not match.
//

import Foundation

public enum ApplyPatchInvocation {
    /// Returns the `*** Begin Patch` … `*** End Patch` document when `command`
    /// is an apply_patch invocation. Other shell commands return nil.
    public static func patchDocument(inShellCommand command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bash = extractFromBash(trimmed) {
            return bash
        }
        if let powershell = extractFromPowerShell(trimmed) {
            return powershell
        }
        return nil
    }

    /// `apply_patch <<EOF` or `cd <path> && apply_patch <<EOF` as the only statement.
    static func extractFromBash(_ source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let head = first.trimmingCharacters(in: .whitespaces)
        let heredoc: String
        if let marker = heredocMarker(in: head, after: applyPatchName(in: head)) {
            guard isOnlyApplyPatch(head) else { return nil }
            heredoc = marker
        } else if let afterCD = cdThenApplyPatch(head) {
            heredoc = afterCD
        } else {
            return nil
        }
        return collectHeredoc(lines: lines, marker: heredoc)
    }

    /// `apply_patch @'\n...\n'@` / `@"\n...\n"@` as the only statement.
    static func extractFromPowerShell(_ source: String) -> String? {
        let lowered = source.lowercased()
        guard lowered.contains("apply_patch") || lowered.contains("applypatch") else {
            return nil
        }
        if let start = source.range(of: "@'"),
           let end = source.range(of: "'@", range: start.upperBound..<source.endIndex) {
            return String(source[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .newlines)
        }
        if let start = source.range(of: "@\""),
           let end = source.range(of: "\"@", range: start.upperBound..<source.endIndex) {
            return String(source[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .newlines)
        }
        return nil
    }

    private static func applyPatchName(in head: String) -> String? {
        let lowered = head.lowercased()
        if lowered.hasPrefix("apply_patch") { return "apply_patch" }
        if lowered.hasPrefix("applypatch") { return "applypatch" }
        return nil
    }

    private static func isOnlyApplyPatch(_ head: String) -> Bool {
        applyPatchName(in: head) != nil
            && !head.contains(";")
            && !head.contains("|")
    }

    private static func cdThenApplyPatch(_ head: String) -> String? {
        guard let and = head.range(of: "&&") else { return nil }
        let cd = head[head.startIndex..<and.lowerBound].trimmingCharacters(in: .whitespaces)
        let apply = head[and.upperBound...].trimmingCharacters(in: .whitespaces)
        guard cd.lowercased().hasPrefix("cd ") else { return nil }
        let rest = cd.dropFirst(3).trimmingCharacters(in: .whitespaces)
        guard !rest.contains(" "), !rest.hasPrefix("-") else { return nil }
        guard let name = applyPatchName(in: apply), isOnlyApplyPatch(apply) else { return nil }
        return heredocMarker(in: apply, after: name)
    }

    private static func heredocMarker(in head: String, after name: String?) -> String? {
        guard name != nil, let redirect = head.range(of: "<<") else { return nil }
        var marker = String(head[redirect.upperBound...]).trimmingCharacters(in: .whitespaces)
        if marker.hasPrefix("-") { marker.removeFirst() }
        marker = marker.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return marker.isEmpty ? nil : marker
    }

    private static func collectHeredoc(lines: [Substring], marker: String) -> String? {
        guard lines.count > 1 else { return nil }
        var body: [Substring] = []
        for line in lines.dropFirst() {
            if String(line) == marker {
                let joined = body.joined(separator: "\n")
                guard joined.contains("*** Begin Patch"), joined.contains("*** End Patch") else {
                    return nil
                }
                return joined
            }
            body.append(line)
        }
        return nil
    }
}
