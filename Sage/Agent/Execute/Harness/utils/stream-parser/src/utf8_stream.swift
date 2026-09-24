//
//  utf8_stream.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/utf8_stream.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `std::str::from_utf8` maps to `validateUtf8`, a private helper replicating
//  `core::str::Utf8Error` semantics: `validUpTo` is the byte offset of the
//  first invalid sequence and `errorLen` the length of the maximal subpart of
//  the ill-formed sequence (`nil` for an incomplete code point at EOF).
//
//  `into_inner` consumes `self` upstream; Swift classes cannot be consumed,
//  so by convention the parser must not be used afterwards.
//

import Foundation

/// Error returned by `Utf8StreamParser` when streamed bytes are not valid
/// UTF-8.
public enum Utf8StreamParserError: Error, Equatable, CustomStringConvertible {
    /// The provided bytes contain an invalid UTF-8 sequence.
    case invalidUtf8(
        /// Byte offset in the parser's buffered bytes where decoding failed.
        validUpTo: Int,
        /// Length in bytes of the invalid sequence.
        errorLen: Int
    )
    /// EOF was reached with a buffered partial UTF-8 code point.
    case incompleteUtf8AtEof

    public var description: String {
        switch self {
        case .invalidUtf8(let validUpTo, let errorLen):
            "invalid UTF-8 in streamed bytes at offset \(validUpTo) (error length \(errorLen))"
        case .incompleteUtf8AtEof:
            "incomplete UTF-8 code point at end of stream"
        }
    }
}

/// `core::str::Utf8Error`: `errorLen == nil` means incomplete at end of input.
private struct Utf8ErrorInfo {
    let validUpTo: Int
    let errorLen: Int?
}

/// `std::str::from_utf8` validation: returns `nil` when `bytes` is valid
/// UTF-8, else the first error. Ranges follow the Unicode "maximal subpart"
/// rule exactly like Rust (e.g. `E0` requires `A0..=BF` as the second byte).
private func validateUtf8(_ bytes: [UInt8]) -> Utf8ErrorInfo? {
    let count = bytes.count
    var i = 0
    while i < count {
        let first = bytes[i]
        if first < 0x80 {
            i += 1
            continue
        }
        // (sequence length, allowed range for the second byte)
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0xC2 ... 0xDF:
            length = 2
            secondRange = 0x80 ... 0xBF
        case 0xE0:
            length = 3
            secondRange = 0xA0 ... 0xBF
        case 0xE1 ... 0xEC, 0xEE ... 0xEF:
            length = 3
            secondRange = 0x80 ... 0xBF
        case 0xED:
            length = 3
            secondRange = 0x80 ... 0x9F
        case 0xF0:
            length = 4
            secondRange = 0x90 ... 0xBF
        case 0xF1 ... 0xF3:
            length = 4
            secondRange = 0x80 ... 0xBF
        case 0xF4:
            length = 4
            secondRange = 0x80 ... 0x8F
        default:
            // 0x80...0xBF (stray continuation), 0xC0, 0xC1, 0xF5...0xFF.
            return Utf8ErrorInfo(validUpTo: i, errorLen: 1)
        }
        for offset in 1 ..< length {
            guard i + offset < count else {
                return Utf8ErrorInfo(validUpTo: i, errorLen: nil)
            }
            let byte = bytes[i + offset]
            let allowed = offset == 1 ? secondRange : 0x80 ... 0xBF
            guard allowed.contains(byte) else {
                return Utf8ErrorInfo(validUpTo: i, errorLen: offset)
            }
        }
        i += length
    }
    return nil
}

/// Wraps a `StreamTextParser` and accepts raw bytes, buffering partial UTF-8
/// code points.
///
/// This is useful when upstream data arrives as `[UInt8]` and a code point
/// may be split across chunk boundaries (for example `0xC3` followed by
/// `0xA9` for `é`).
public final class Utf8StreamParser<P: StreamTextParser> {
    private let inner: P
    private var pendingUtf8: [UInt8] = []

    public init(inner: P) {
        self.inner = inner
    }

    /// Feed a raw byte chunk.
    ///
    /// If the chunk contains invalid UTF-8, this throws and rolls back the
    /// entire pushed chunk so callers can decide how to recover without the
    /// inner parser seeing a partial prefix from that chunk.
    public func pushBytes(_ chunk: [UInt8]) throws -> StreamTextChunk<P.Extracted> {
        let oldLen = pendingUtf8.count
        pendingUtf8.append(contentsOf: chunk)

        guard let error = validateUtf8(pendingUtf8) else {
            let text = String(decoding: pendingUtf8, as: UTF8.self)
            let out = inner.pushStr(text)
            pendingUtf8.removeAll()
            return out
        }

        if let errorLen = error.errorLen {
            pendingUtf8.removeSubrange(oldLen...)
            throw Utf8StreamParserError.invalidUtf8(
                validUpTo: error.validUpTo,
                errorLen: errorLen
            )
        }

        let validUpTo = error.validUpTo
        if validUpTo == 0 {
            return StreamTextChunk()
        }

        // `bytes[..<validUpTo]` is valid UTF-8 by construction (upstream
        // re-validates the prefix defensively).
        let text = String(decoding: pendingUtf8.prefix(validUpTo), as: UTF8.self)
        let out = inner.pushStr(text)
        pendingUtf8.removeFirst(validUpTo)
        return out
    }

    public func finish() throws -> StreamTextChunk<P.Extracted> {
        if !pendingUtf8.isEmpty, let error = validateUtf8(pendingUtf8) {
            if let errorLen = error.errorLen {
                throw Utf8StreamParserError.invalidUtf8(
                    validUpTo: error.validUpTo,
                    errorLen: errorLen
                )
            }
            throw Utf8StreamParserError.incompleteUtf8AtEof
        }

        var out = StreamTextChunk<P.Extracted>()
        if !pendingUtf8.isEmpty {
            let text = String(decoding: pendingUtf8, as: UTF8.self)
            out = inner.pushStr(text)
            pendingUtf8.removeAll()
        }

        let tail = inner.finish()
        out.visibleText += tail.visibleText
        out.extracted.append(contentsOf: tail.extracted)
        return out
    }

    /// Return the wrapped parser if no undecoded UTF-8 bytes are buffered.
    ///
    /// Use `finish()` first if you want to flush buffered text into the
    /// wrapped parser.
    public func intoInner() throws -> P {
        if !pendingUtf8.isEmpty, let error = validateUtf8(pendingUtf8) {
            if let errorLen = error.errorLen {
                throw Utf8StreamParserError.invalidUtf8(
                    validUpTo: error.validUpTo,
                    errorLen: errorLen
                )
            }
            throw Utf8StreamParserError.incompleteUtf8AtEof
        }
        return inner
    }

    /// Return the wrapped parser without validating or flushing buffered
    /// undecoded bytes.
    ///
    /// This may drop a partial UTF-8 code point that was buffered across
    /// chunk boundaries.
    public func intoInnerLossy() -> P {
        inner
    }
}
