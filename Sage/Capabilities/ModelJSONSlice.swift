//
//  ModelJSONSlice.swift
//  Sage
//
//  Shared helpers for extracting a JSON object from free-form model output.
//

import Foundation

nonisolated enum ModelJSONSlice {
    /// Returns the substring spanning the first `{` through the last `}`, if both exist.
    static func objectString(in content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[start...end])
    }

    /// Decodes the first JSON object slice as a dictionary (fail-soft).
    static func jsonObject(in content: String) -> [String: Any]? {
        guard let jsonString = objectString(in: content),
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parsed
    }

    /// Decodes the first JSON object slice with `JSONDecoder`.
    static func decode<T: Decodable>(_ type: T.Type, from content: String) -> T? {
        guard let jsonString = objectString(in: content),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
