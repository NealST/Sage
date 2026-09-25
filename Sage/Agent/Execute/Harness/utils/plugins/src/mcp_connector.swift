//
//  mcp_connector.swift
//  CodexUtils
//
//  Port of codex-rs/utils/plugins/src/mcp_connector.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Name sanitization for MCP connectors (plugin → tool namespace).
//

/// Sanitizes a plugin name into a tool-namespace identifier.
///
/// Alphanumeric characters are lowercased; everything else becomes `_`.
/// Leading/trailing `_` are trimmed; empty input yields `"app"`.
public func sanitizeMCPConnectorName(_ name: String) -> String {
    sanitizeSlug(name).replacingOccurrences(of: "-", with: "_")
}

private func sanitizeSlug(_ name: String) -> String {
    var normalized = ""
    normalized.reserveCapacity(name.count)
    for character in name {
        if character.isASCII, let av = character.asciiValue, av.isAlphanumericByte {
            normalized.append(Character(UnicodeScalar(av)).lowercased())
        } else {
            normalized.append("-")
        }
    }
    let trimmed = normalized.trimmingCharacters(in: .init(charactersIn: "-"))
    return trimmed.isEmpty ? "app" : trimmed
}

private extension UInt8 {
    var isAlphanumericByte: Bool {
        (self >= 48 && self <= 57)      // 0-9
            || (self >= 65 && self <= 90)   // A-Z
            || (self >= 97 && self <= 122)  // a-z
    }
}
