//
//  prompt.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/prompt.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Reviewer contract (ALLOW/DENY/ASK) only; the full upstream prompt
//  assembly lands with the Guardian phase (Phase 8).
//

import Foundation

enum GuardianPrompt {
    static let system = """
    You are Guardian, an isolated reviewer. The execute agent proposed one action.
    You do not run tools. Reply with exactly one decision:

    ALLOW
    DENY <reason>
    ASK <reason>

    ALLOW only when the action stays inside the confirmed work and does not \
    leak secrets, destroy the workspace, or escalate beyond the sandbox \
    without a clear need. DENY unacceptable risk. ASK when a person must decide.
    """

    static func user(
        request: GuardianApprovalRequest,
        approvalReason: String?,
        retryReason: String?
    ) -> String {
        var parts = [
            ">>> ACTION",
            request.pretty(),
        ]
        if let approvalReason, !approvalReason.isEmpty {
            parts.append("approval_reason: \(approvalReason)")
        }
        if let retryReason, !retryReason.isEmpty {
            parts.append("retry_reason: \(retryReason)")
        }
        return parts.joined(separator: "\n")
    }

    static func parse(_ raw: String) -> ReviewDecision? {
        let line = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let upper = line.uppercased()
        if upper == "ALLOW" || upper.hasPrefix("ALLOW ") {
            return .approved
        }
        if upper.hasPrefix("DENY") {
            let reason = line.drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespaces)
            return .denied(reason: reason.isEmpty ? "Guardian denied this action." : reason)
        }
        if upper.hasPrefix("ASK") {
            return nil
        }
        return nil
    }

    /// Codex `guardian_truncate_text`: keep a prefix and suffix under the cap.
    static func truncate(_ content: String, tokenCap: Int) -> String {
        let tokens = PromptBudget.estimatedTokenCount(in: content)
        guard tokens > tokenCap, tokenCap > 8 else { return content }
        let keep = max(tokenCap / 2, 4)
        let scalars = Array(content)
        let head = String(scalars.prefix(keep * 2))
        let tail = String(scalars.suffix(keep * 2))
        return "\(head)\n…\n\(tail)"
    }

    static func isAsk(_ raw: String) -> Bool {
        let line = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            ?? ""
        return line == "ASK" || line.hasPrefix("ASK ")
    }
}
