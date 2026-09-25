//
//  exec_output.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/exec_output.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Text encoding detection and conversion utilities for shell output.
//  Upstream uses `chardetng` + `encoding_rs` for legacy code-page detection
//  (CP1251, CP866, Windows-1252). Swift handles this through Foundation's
//  `String(data:encoding:)` and `CFStringConvertEncodingToNSStringEncoding`.
//  The IBM866 ↔ Windows-1252 smart-punctuation heuristic is preserved.
//
//  Difference from upstream: encoding detection uses a simplified heuristic
//  (try UTF-8, then apply the Windows-1252 punctuation heuristic for the
//  0x80-0x9F range, then fall back to lossy UTF-8). macOS rarely encounters
//  the Windows code-page soup that motivates the full chardetng path.
//

import Foundation

public struct StreamOutput<T: Sendable>: Sendable {
    public var text: T
    public var truncatedAfterLines: UInt32?

    public init(text: T, truncatedAfterLines: UInt32? = nil) {
        self.text = text
        self.truncatedAfterLines = truncatedAfterLines
    }
}

extension StreamOutput where T == String {
    public static func new(_ text: String) -> StreamOutput<String> {
        StreamOutput<String>(text: text)
    }
}

extension StreamOutput where T == Data {
    public func fromUTF8Lossy() -> StreamOutput<String> {
        StreamOutput<String>(
            text: bytesToStringSmart(text),
            truncatedAfterLines: truncatedAfterLines
        )
    }
}

public struct ExecToolCallOutput: Sendable {
    public var exitCode: Int32
    public var stdout: StreamOutput<String>
    public var stderr: StreamOutput<String>
    public var aggregatedOutput: StreamOutput<String>
    public var duration: Duration
    public var timedOut: Bool

    public init(
        exitCode: Int32 = 0,
        stdout: StreamOutput<String> = .new(""),
        stderr: StreamOutput<String> = .new(""),
        aggregatedOutput: StreamOutput<String> = .new(""),
        duration: Duration = .zero,
        timedOut: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.aggregatedOutput = aggregatedOutput
        self.duration = duration
        self.timedOut = timedOut
    }
}

/// Attempts to convert arbitrary bytes to a Swift String with best-effort
/// encoding detection.
///
/// Strategy: try UTF-8 first (fast path), then apply the Windows-1252
/// smart-punctuation heuristic for the 0x80-0x9F byte range (matching
/// upstream's `looks_like_windows_1252_punctuation`), then fall back to
/// lossy UTF-8 replacement.
public func bytesToStringSmart(_ bytes: Data) -> String {
    if bytes.isEmpty { return "" }

    if let utf8 = String(data: bytes, encoding: .utf8) {
        return utf8
    }

    if looksLikeWindows1252Punctuation(bytes) {
        if let decoded = String(data: bytes, encoding: .windowsCP1252) {
            return decoded
        }
    }

    // Lossy fallback: replace invalid sequences with U+FFFD.
    return String(decoding: bytes, as: UTF8.self)
}

// MARK: - Windows-1252 smart-punctuation heuristic

/// Windows-1252 byte values for smart punctuation that collide with
/// IBM866 Cyrillic uppercase letters in the 0x80–0x9F range.
private let windows1252PunctBytes: Set<UInt8> = [
    0x91, // ' left single quotation mark
    0x92, // ' right single quotation mark
    0x93, // " left double quotation mark
    0x94, // " right double quotation mark
    0x95, // • bullet
    0x96, // – en dash
    0x97, // — em dash
    0x99, // ™ trade mark sign
]

/// Returns `true` when the byte stream looks like Windows-1252 smart
/// punctuation wrapped around otherwise-ASCII text — the same heuristic
/// as upstream's `looks_like_windows_1252_punctuation`.
private func looksLikeWindows1252Punctuation(_ bytes: Data) -> Bool {
    var sawExtendedPunctuation = false
    var sawAsciiWord = false

    for byte in bytes {
        if byte >= 0xA0 { return false }
        if (0x80...0x9F).contains(byte) {
            guard windows1252PunctBytes.contains(byte) else { return false }
            sawExtendedPunctuation = true
        }
        if byte.isASCIIAlphabetic {
            sawAsciiWord = true
        }
    }
    return sawExtendedPunctuation && sawAsciiWord
}

private extension UInt8 {
    var isASCIIAlphabetic: Bool {
        (self >= 0x41 && self <= 0x5A) || (self >= 0x61 && self <= 0x7A)
    }
}
