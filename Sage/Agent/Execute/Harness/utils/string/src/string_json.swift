//
//  string_json.swift
//  CodexUtils
//
//  Port of codex-rs/utils/string/src/json.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  serde_json maps to Foundation's `JSONEncoder` (compact, declaration-order
//  keys, `.withoutEscapingSlashes` — serde_json does not escape `/` either).
//
//  `AsciiJsonFormatter` intercepts string fragments during serialization;
//  `JSONEncoder` has no formatter hook, so the port post-processes the
//  serialized output instead: JSON structure is pure ASCII, so any non-ASCII
//  scalar in the output must be inside a string literal and is escaped as
//  `\uXXXX` (UTF-16 code units, lowercase hex — identical to upstream).
//
//  `to_json_string_bounded`'s `BoundedBuffer` fails mid-write once the byte
//  limit is exceeded; the port encodes fully and then checks the byte count.
//  Both return an error and no string in the exceeded case.
//
//  R4a: upstream `json.rs` maps to `string_json.swift` because
//  `core/src/utils/json.rs` claims `utils/json.swift` (plan §5.1).
//

import Foundation

/// `serde_json::Error` stand-in for the bounded writer (`io::ErrorKind::
/// WriteZero`, "JSON byte limit exceeded").
public struct JsonByteLimitExceededError: Error, Equatable, CustomStringConvertible {
    public let description = "JSON byte limit exceeded"
    public init() {}
}

/// `AsciiJsonFormatter::write_string_fragment` applied to serialized output:
/// escapes non-ASCII content inside string literals as `\uXXXX`.
private func escapeNonAsciiStringFragments(_ json: String) -> String {
    var out = ""
    out.reserveCapacity(json.utf8.count)
    var inString = false
    var escaped = false
    for ch in json {
        if escaped {
            // A `\`-escaped character inside a string is ASCII by JSON rules
            // (\" \\ \/ \b \f \n \r \t \uXXXX) — copy verbatim.
            out.append(ch)
            escaped = false
            continue
        }
        if inString, ch == "\\" {
            out.append(ch)
            escaped = true
            continue
        }
        if ch == "\"" {
            inString.toggle()
            out.append(ch)
            continue
        }
        if inString, !ch.isASCII {
            for unit in String(ch).utf16 {
                out += String(format: "\\u%04x", unit)
            }
            continue
        }
        out.append(ch)
    }
    return out
}

private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
}

/// Serialize JSON while escaping non-ASCII string content as `\uXXXX`.
///
/// This is useful when JSON needs to remain parseable as JSON but must be
/// carried through ASCII-safe transports such as HTTP headers.
public func toAsciiJsonString<T: Encodable>(_ value: T) throws -> String {
    let data = try makeEncoder().encode(value)
    return escapeNonAsciiStringFragments(String(decoding: data, as: UTF8.self))
}

/// Serialize UTF-8 JSON while retaining at most `maxBytes` of output.
public func toJsonStringBounded<T: Encodable>(_ value: T, maxBytes: Int) throws -> String {
    let data = try makeEncoder().encode(value)
    guard data.count <= maxBytes else {
        throw JsonByteLimitExceededError()
    }
    return String(decoding: data, as: UTF8.self)
}
