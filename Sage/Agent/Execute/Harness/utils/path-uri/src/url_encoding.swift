//
//  url_encoding.swift
//  CodexUtils
//
//  Sage addition (no codex counterpart).
//
//  Stands in for the `urlencoding` and `base64` crates (the two helpers
//  codex-utils-path-uri relies on):
//  - `urlencoding::decode_binary` / `decode` / `encode_binary`
//  - `base64::engine::general_purpose::URL_SAFE_NO_PAD`
//

import Foundation

/// `urlencoding::decode_binary`: percent-decode valid `%XX` triplets,
/// pass everything else through verbatim.
func urlDecodeBinary(_ bytes: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var index = 0
    while index < bytes.count {
        if bytes[index] == UInt8(ascii: "%"),
           index + 2 < bytes.count,
           let hi = hexValue(bytes[index + 1]),
           let lo = hexValue(bytes[index + 2]) {
            out.append(UInt8(hi * 16 + lo))
            index += 3
        } else {
            out.append(bytes[index])
            index += 1
        }
    }
    return out
}

/// `urlencoding::decode`: percent-decode, requiring valid UTF-8.
func urlDecode(_ string: String) -> String? {
    let bytes = urlDecodeBinary(Array(string.utf8))
    return String(bytes: bytes, encoding: .utf8)
}

/// `urlencoding::encode_binary`: keep unreserved bytes
/// (`A-Z a-z 0-9 - . _ ~`), percent-encode the rest with uppercase hex.
func urlEncodeBinary(_ bytes: [UInt8]) -> String {
    var out = ""
    for byte in bytes {
        if isUnreservedByte(byte) {
            out.append(Character(UnicodeScalar(byte)))
        } else {
            out += String(format: "%%%02X", byte)
        }
    }
    return out
}

func isUnreservedByte(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "A")...UInt8(ascii: "Z"),
         UInt8(ascii: "a")...UInt8(ascii: "z"),
         UInt8(ascii: "0")...UInt8(ascii: "9"),
         UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
        return true
    default:
        return false
    }
}

func hexValue(_ byte: UInt8) -> Int? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
        return Int(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "A")...UInt8(ascii: "F"):
        return Int(byte - UInt8(ascii: "A")) + 10
    case UInt8(ascii: "a")...UInt8(ascii: "f"):
        return Int(byte - UInt8(ascii: "a")) + 10
    default:
        return nil
    }
}

/// `base64::engine::general_purpose::URL_SAFE_NO_PAD`.
///
/// Decoding is lenient about trailing bits; canonicality is enforced by the
/// caller's re-encode comparison (`decode_bad_path_uri`).
enum Base64URLNoPad {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    static func encode(_ bytes: [UInt8]) -> String {
        var out = ""
        var index = 0
        while index + 3 <= bytes.count {
            let n = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            out.append(Character(UnicodeScalar(alphabet[(n >> 18) & 63])))
            out.append(Character(UnicodeScalar(alphabet[(n >> 12) & 63])))
            out.append(Character(UnicodeScalar(alphabet[(n >> 6) & 63])))
            out.append(Character(UnicodeScalar(alphabet[n & 63])))
            index += 3
        }
        switch bytes.count - index {
        case 1:
            let n = Int(bytes[index]) << 16
            out.append(Character(UnicodeScalar(alphabet[(n >> 18) & 63])))
            out.append(Character(UnicodeScalar(alphabet[(n >> 12) & 63])))
        case 2:
            let n = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8
            out.append(Character(UnicodeScalar(alphabet[(n >> 18) & 63])))
            out.append(Character(UnicodeScalar(alphabet[(n >> 12) & 63])))
            out.append(Character(UnicodeScalar(alphabet[(n >> 6) & 63])))
        default:
            break
        }
        return out
    }

    static func decode(_ string: String) -> [UInt8]? {
        let chars = Array(string.utf8)
        guard !chars.isEmpty, chars.count % 4 != 1 else { return nil }
        var values: [UInt8] = []
        values.reserveCapacity(chars.count)
        for char in chars {
            guard let value = alphabetValue(char) else { return nil }
            values.append(value)
        }
        var out: [UInt8] = []
        var index = 0
        while index + 4 <= values.count {
            let n = Int(values[index]) << 18 | Int(values[index + 1]) << 12
                | Int(values[index + 2]) << 6 | Int(values[index + 3])
            out.append(UInt8((n >> 16) & 0xFF))
            out.append(UInt8((n >> 8) & 0xFF))
            out.append(UInt8(n & 0xFF))
            index += 4
        }
        switch values.count - index {
        case 2:
            let n = Int(values[index]) << 18 | Int(values[index + 1]) << 12
            out.append(UInt8((n >> 16) & 0xFF))
        case 3:
            let n = Int(values[index]) << 18 | Int(values[index + 1]) << 12
                | Int(values[index + 2]) << 6
            out.append(UInt8((n >> 16) & 0xFF))
            out.append(UInt8((n >> 8) & 0xFF))
        default:
            break
        }
        return out
    }

    private static func alphabetValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"):
            return byte - UInt8(ascii: "A")
        case UInt8(ascii: "a")...UInt8(ascii: "z"):
            return byte - UInt8(ascii: "a") + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return byte - UInt8(ascii: "0") + 52
        case UInt8(ascii: "-"):
            return 62
        case UInt8(ascii: "_"):
            return 63
        default:
            return nil
        }
    }
}
