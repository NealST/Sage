//
//  num_format.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/num_format.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Locale-aware digit grouping ("12345" -> "12,345" for en-US). Codex uses an
//  ICU DecimalFormatter on the system locale with an en-US fallback; Swift
//  uses `IntegerFormatStyle` on the current locale (Foundation always has a
//  valid locale, so the fallback is unnecessary).
//

import Foundation

/// `format_with_separators` — format an i64 with locale-aware digit separators.
public func formatWithSeparators(_ value: Int64) -> String {
    value.formatted(.number.grouping(.automatic))
}
