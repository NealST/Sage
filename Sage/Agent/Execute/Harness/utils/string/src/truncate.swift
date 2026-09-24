//
//  truncate.swift
//  CodexUtils
//
//  Port of codex-rs/utils/string/src/truncate.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `&str` byte budgets map to UTF-8 byte counts; slicing by byte offset uses
//  the UTF-8 view (offsets are always at char boundaries by construction).
//  `usize`/`u64` saturating arithmetic maps to explicit clamping helpers
//  (string lengths never approach Int.max in practice).
//

import Foundation

private let approxBytesPerToken = 4

/// Truncate a string to `maxBytes` using a character-count marker.
public func truncateMiddleChars(_ s: String, maxBytes: Int) -> String {
    truncateWithByteEstimate(s, maxBytes: maxBytes, useTokens: false)
}

/// Truncate the middle of a UTF-8 string to at most `maxTokens` approximate
/// tokens, preserving the beginning and the end. Returns the possibly
/// truncated string and `originalTokenCount` if truncation occurred;
/// otherwise returns the original string and `nil`.
public func truncateMiddleWithTokenBudget(
    _ s: String,
    maxTokens: Int
) -> (String, originalTokenCount: UInt64?) {
    if s.isEmpty {
        return ("", nil)
    }

    if maxTokens > 0 && s.utf8.count <= approxBytesForTokens(maxTokens) {
        return (s, nil)
    }

    let truncated = truncateWithByteEstimate(
        s,
        maxBytes: approxBytesForTokens(maxTokens),
        useTokens: true
    )
    let totalTokens = UInt64(approxTokenCount(s))

    if truncated == s {
        return (truncated, nil)
    }
    return (truncated, totalTokens)
}

private func truncateWithByteEstimate(_ s: String, maxBytes: Int, useTokens: Bool) -> String {
    if s.isEmpty {
        return ""
    }

    let totalChars = s.count

    if maxBytes == 0 {
        return formatTruncationMarker(
            useTokens: useTokens,
            removedCount: removedUnits(
                useTokens: useTokens,
                removedBytes: s.utf8.count,
                removedChars: totalChars
            )
        )
    }

    if s.utf8.count <= maxBytes {
        return s
    }

    let totalBytes = s.utf8.count
    let (leftBudget, rightBudget) = splitBudget(maxBytes)
    let (removedChars, left, right) = splitString(
        s,
        beginningBytes: leftBudget,
        endBytes: rightBudget
    )
    let marker = formatTruncationMarker(
        useTokens: useTokens,
        removedCount: removedUnits(
            useTokens: useTokens,
            removedBytes: totalBytes - maxBytes, // saturating_sub: totalBytes > maxBytes here
            removedChars: removedChars
        )
    )

    return assembleTruncatedOutput(prefix: left, suffix: right, marker: marker)
}

public func approxTokenCount(_ text: String) -> Int {
    let len = text.utf8.count
    return (len + approxBytesPerToken - 1) / approxBytesPerToken
}

public func approxBytesForTokens(_ tokens: Int) -> Int {
    tokens > Int.max / approxBytesPerToken ? Int.max : tokens * approxBytesPerToken
}

public func approxTokensFromByteCount(_ bytes: Int) -> UInt64 {
    let bytes = UInt64(bytes)
    let bump = UInt64(approxBytesPerToken - 1)
    // saturating_add
    return (bytes > UInt64.max - bump ? UInt64.max : bytes + bump) / UInt64(approxBytesPerToken)
}

/// `(removed_chars, prefix, suffix)` — `split_string`.
func splitString(
    _ s: String,
    beginningBytes: Int,
    endBytes: Int
) -> (Int, Substring, Substring) {
    if s.isEmpty {
        return (0, "", "")
    }

    let len = s.utf8.count
    let tailStartTarget = len - min(len, endBytes) // saturating_sub
    var prefixEnd = 0
    var suffixStart = len
    var removedChars = 0
    var suffixStarted = false

    var idx = 0
    for ch in s {
        let charEnd = idx + ch.utf8.count
        if charEnd <= beginningBytes {
            prefixEnd = charEnd
            idx = charEnd
            continue
        }

        if idx >= tailStartTarget {
            if !suffixStarted {
                suffixStart = idx
                suffixStarted = true
            }
            idx = charEnd
            continue
        }

        removedChars += 1
        idx = charEnd
    }

    if suffixStart < prefixEnd {
        suffixStart = prefixEnd
    }

    let utf8 = s.utf8
    let before = s[..<utf8.index(utf8.startIndex, offsetBy: prefixEnd)]
    let after = s[utf8.index(utf8.startIndex, offsetBy: suffixStart)...]

    return (removedChars, before, after)
}

private func splitBudget(_ budget: Int) -> (Int, Int) {
    let left = budget / 2
    return (left, budget - left)
}

private func formatTruncationMarker(useTokens: Bool, removedCount: UInt64) -> String {
    if useTokens {
        return "…\(removedCount) tokens truncated…"
    }
    return "…\(removedCount) chars truncated…"
}

private func removedUnits(useTokens: Bool, removedBytes: Int, removedChars: Int) -> UInt64 {
    if useTokens {
        return approxTokensFromByteCount(removedBytes)
    }
    return UInt64(removedChars)
}

private func assembleTruncatedOutput(prefix: Substring, suffix: Substring, marker: String) -> String {
    var out = ""
    out.reserveCapacity(prefix.utf8.count + marker.utf8.count + suffix.utf8.count + 1)
    out += prefix
    out += marker
    out += suffix
    return out
}
