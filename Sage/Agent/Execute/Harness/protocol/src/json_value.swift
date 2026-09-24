//
//  json_value.swift
//  CodexProtocol
//
//  Sage addition (no codex counterpart).
//
//  Stands in for `serde_json::Value`. Codex builds serde_json without the
//  `preserve_order` feature, so objects are BTreeMaps: keys encode in sorted
//  order, which `encodedString()` reproduces. (Foundation's `JSONEncoder`
//  emits keys in unspecified order — a known wire-format gap for `Codable`
//  structs, where serde_json would use declaration order.) Numbers keep the
//  serde_json distinction
//  between u64 / i64 / f64.
//
//  Known gap: Foundation's JSON decoder may coerce a whole-number double
//  literal (e.g. `1.0`) into the integer cases; serde_json keeps it f64.
//

import Foundation

public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .uint(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .object(let object):
            // serde_json (BTreeMap) emits keys in sorted order.
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            for key in object.keys.sorted() {
                try container.encode(object[key], forKey: JSONCodingKey(key))
            }
        default:
            var container = encoder.singleValueContainer()
            switch self {
            case .null:
                try container.encodeNil()
            case .bool(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .uint(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            case .object:
                break // handled above
            }
        }
    }
}

/// Dynamic key for `JSONValue.object` encoding.
struct JSONCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension JSONValue {
    /// `serde_json::to_string` for `Value`: deterministic, object keys sorted
    /// (BTreeMap). Foundation's `JSONEncoder` emits keys in unspecified order,
    /// so byte-level wire comparisons must go through this serializer.
    public func encodedString() -> String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .uint(let value):
            return String(value)
        case .double(let value):
            // serde_json uses ryu (shortest round-trip), as does Swift's
            // Double description; non-finite doubles are rejected upstream.
            return String(value)
        case .string(let value):
            return JSONValue.escape(value)
        case .array(let values):
            return "[" + values.map { $0.encodedString() }.joined(separator: ",") + "]"
        case .object(let object):
            return "{" + object.keys.sorted().map { key in
                JSONValue.escape(key) + ":" + (object[key] ?? .null).encodedString()
            }.joined(separator: ",") + "}"
        }
    }

    /// serde_json string escaping: `"` `\` and control chars (< 0x20) with the
    /// short forms `\b \t \n \f \r` where they exist, else `\u00XX`.
    private static func escape(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{09}": out += "\\t"
            case "\u{0A}": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\u{0D}": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

extension JSONValue {
    /// Convenience memberwise accessors mirroring common `serde_json::Value`
    /// inspection helpers (`as_str`, `as_i64`, ...).
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int64? {
        switch self {
        case .int(let value): return value
        case .uint(let value): return Int64(exactly: value)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .uint(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
