//
//  output_truncation_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/output-truncation/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Shared byte/token truncation for tool and exec output. The core text
//  truncation functions are faithfully ported. Functions operating on
//  `FunctionCallOutputPayload` / `FunctionCallOutputContentItem` / 
//  `TruncationPolicy` are deferred until `protocol/models.rs` and
//  `protocol/protocol.rs` are ported (Phase 1 protocol layer).
//
//  R4a: upstream `lib.rs` → `output_truncation_lib.swift` (basename dedup).
//

import Foundation

// Re-export from string utils (upstream does `pub use`).
// These functions are defined in string/truncate.swift.

/// Adds the existing 20% allowance for serialization and headers.
/// Saved history budgets already include this allowance.
public func withSerializationAllowanceBudget(bytes: Int) -> Int {
    Int(Double(bytes) * 1.2)
}

/// Truncate text to a byte budget, adding a warning header with
/// the original token count and total line count.
public func formattedTruncateText(content: String, byteBudget: Int) -> String {
    if content.utf8.count <= byteBudget {
        return content
    }

    let originalTokenCount = approxTokenCount(content)
    let totalLines = content.split(separator: "\n", omittingEmptySubsequences: false).count
    let result = truncateTextByBytes(content, budget: byteBudget)
    return """
        Warning: truncated output (original token count: \(originalTokenCount))
        Total output lines: \(totalLines)

        \(result)
        """
}

/// Truncate text to a byte budget by removing the middle.
public func truncateTextByBytes(_ content: String, budget: Int) -> String {
    truncateMiddleChars(content, maxBytes: budget)
}

/// Truncate text to a token budget by removing the middle.
public func truncateTextByTokens(_ content: String, tokenBudget: Int) -> String {
    truncateMiddleWithTokenBudget(content, maxTokens: tokenBudget).0
}

/// Convert a signed byte count to an approximate token count.
public func approxTokensFromByteCountI64(_ bytes: Int64) -> Int64 {
    guard bytes > 0 else { return 0 }
    let ub = Int(clamping: bytes)
    return Int64(clamping: approxTokensFromByteCount(ub))
}

// TODO: Port `truncate_function_output_payload`,
// `formatted_truncate_text_content_items_with_policy`,
// `truncate_function_output_items_with_policy` once
// FunctionCallOutputPayload / FunctionCallOutputContentItem /
// TruncationPolicy are available (protocol/models.rs).
