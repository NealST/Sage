//
//  string_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/string/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `regex_lite::Regex` maps to `NSRegularExpression` (the UUID pattern is
//  ASCII-only, so the engines agree). The `OnceLock` static maps to a lazy
//  global. `&str` byte slicing maps to UTF-8-view offsets.
//
//  R4a: upstream `lib.rs` maps to `string_lib.swift` because
//  `utils/absolute-path/src/lib.swift` claimed the basename first (plan §5.1).
//

import Foundation

/// Truncate a string to a byte budget at a char boundary (prefix).
public func takeBytesAtCharBoundary(_ s: String, maxb: Int) -> Substring {
    if s.utf8.count <= maxb {
        return Substring(s)
    }
    var lastOk = 0
    for ch in s {
        // `char_indices` yields byte starts; chars are contiguous, so the end
        // of the previous char is the start of this one.
        let nb = lastOk + ch.utf8.count
        if nb > maxb {
            break
        }
        lastOk = nb
    }
    let end = s.utf8.index(s.utf8.startIndex, offsetBy: lastOk)
    return Substring(s[..<end])
}

/// Sanitize a tag value to comply with metric tag validation rules:
/// only ASCII alphanumeric, '.', '_', '-', and '/' are allowed.
public func sanitizeMetricTagValue(_ value: String) -> String {
    let maxLen = 256
    let sanitized = value.map { ch -> Character in
        if ch.isASCII, ch.asciiValue!.isAsciiAlphanumeric || ch == "." || ch == "_" || ch == "-"
            || ch == "/" {
            return ch
        }
        return "_"
    }
    let trimmed = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    if trimmed.isEmpty || trimmed.allSatisfy({ !($0.isASCII && $0.asciiValue!.isAsciiAlphanumeric) }) {
        return "unspecified"
    }
    // After sanitizing, all characters are ASCII, so byte count == char count.
    if trimmed.utf8.count <= maxLen {
        return trimmed
    }
    return String(trimmed.prefix(maxLen))
}

private extension UInt8 {
    var isAsciiAlphanumeric: Bool {
        (self >= 48 && self <= 57) || (self >= 65 && self <= 90) || (self >= 97 && self <= 122)
    }
}

/// The UUID pattern compiled once (`OnceLock` → lazy global).
private let uuidRegex: NSRegularExpression = {
    // Force-unwrapping is safe thanks to the tests (upstream does the same).
    // swiftlint:disable:next force_try
    try! NSRegularExpression(
        pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    )
}()

/// Find all UUIDs in a string.
public func findUuids(_ s: String) -> [String] {
    let range = NSRange(s.startIndex..., in: s)
    return uuidRegex.matches(in: s, range: range).map { match in
        String(s[Range(match.range, in: s)!])
    }
}

/// Convert a markdown-style `#L..` location suffix into a terminal-friendly
/// `:line[:column][-line[:column]]` suffix.
public func normalizeMarkdownHashLocationSuffix(_ suffix: String) -> String? {
    guard let fragment = suffix.stripPrefix("#") else { return nil }
    let (start, end): (Substring, Substring?) = switch fragment.splitOnce("-") {
    case .some(let pair): (pair.0, pair.1)
    case .none: (Substring(fragment), nil)
    }
    guard let (startLine, startColumn) = parseMarkdownHashLocationPoint(start) else {
        return nil
    }
    var normalized = ":"
    normalized += startLine
    if let column = startColumn {
        normalized += ":"
        normalized += column
    }
    if let end {
        guard let (endLine, endColumn) = parseMarkdownHashLocationPoint(end) else {
            return nil
        }
        normalized += "-"
        normalized += endLine
        if let column = endColumn {
            normalized += ":"
            normalized += column
        }
    }
    return normalized
}

private func parseMarkdownHashLocationPoint(_ point: Substring) -> (String, String?)? {
    guard let point = point.stripPrefix("L") else { return nil }
    if let (line, column) = point.splitOnce("C") {
        return (String(line), String(column))
    }
    return (String(point), nil)
}

// File-private: other ported files define their own `stripPrefix` shims
// (e.g. absolute-path/lib.swift); same-signature extensions on the same type
// collide module-wide even at `private` visibility.
private extension String {
    /// `str::strip_prefix`.
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    /// `str::split_once`.
    func splitOnce(_ separator: Character) -> (Substring, Substring)? {
        guard let index = firstIndex(of: separator) else { return nil }
        return (self[..<index], self[index...].dropFirst())
    }
}

private extension Substring {
    /// `str::strip_prefix`.
    func stripPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }

    /// `str::split_once`.
    func splitOnce(_ separator: Character) -> (Substring, Substring)? {
        guard let index = firstIndex(of: separator) else { return nil }
        return (self[..<index], self[index...].dropFirst())
    }
}
