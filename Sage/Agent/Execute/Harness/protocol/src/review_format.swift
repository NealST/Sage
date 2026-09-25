//
//  review_format.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/review_format.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Plain-text rendering helpers for review results. Higher layers style the
//  output as needed.
//

import Foundation

/// Fallback text used when a review contains no displayable output.
public let reviewFallbackMessage = "Reviewer failed to output a response."

private func formatLocation(_ item: ReviewFinding) -> String {
    let path = item.codeLocation.absoluteFilePath
    let start = item.codeLocation.lineRange.start
    let end = item.codeLocation.lineRange.end
    return "\(path):\(start)-\(end)"
}

/// Format a full review findings block as plain text lines.
///
/// - When `selection` is non-nil, each item line includes a checkbox marker:
///   "[x]" for selected items and "[ ]" for unselected. Missing indices
///   default to selected.
/// - When `selection` is nil, the marker is omitted and a simple bullet is
///   rendered ("- Title — path:start-end").
public func formatReviewFindingsBlock(
    findings: [ReviewFinding],
    selection: [Bool]?
) -> String {
    var lines: [String] = []
    lines.append("")

    // Header
    if findings.count > 1 {
        lines.append("Full review comments:")
    } else {
        lines.append("Review comment:")
    }

    for (idx, item) in findings.enumerated() {
        lines.append("")

        let title = item.title
        let location = formatLocation(item)

        if let flags = selection {
            // Default to selected if index is out of bounds.
            let checked = idx < flags.count ? flags[idx] : true
            let marker = checked ? "[x]" : "[ ]"
            lines.append("- \(marker) \(title) — \(location)")
        } else {
            lines.append("- \(title) — \(location)")
        }

        // Rust `str::lines()` splits on \n and strips a trailing \r.
        for rawLine in item.body.split(separator: "\n", omittingEmptySubsequences: false) {
            let bodyLine = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            lines.append("  \(bodyLine)")
        }
    }

    return lines.joined(separator: "\n")
}

/// Render a human-readable review summary suitable for a user-facing message.
///
/// Returns either the explanation, the formatted findings block, or both
/// separated by a blank line. If neither is present, emits a fallback message.
public func renderReviewOutputText(_ output: ReviewOutputEvent) -> String {
    var sections: [String] = []
    let explanation = output.overallExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
    if !explanation.isEmpty {
        sections.append(explanation)
    }
    if !output.findings.isEmpty {
        let findings = formatReviewFindingsBlock(findings: output.findings, selection: nil)
        let trimmed = findings.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sections.append(trimmed)
        }
    }
    if sections.isEmpty {
        return reviewFallbackMessage
    }
    return sections.joined(separator: "\n\n")
}
