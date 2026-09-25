//
//  shell_snapshot_exports.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_exports.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Export parsing for snapshot capture.
//

public func parseExportedAssignments(_ text: String) -> [String: String] {
    var exports: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("export ") else { continue }
        let body = trimmed.dropFirst("export ".count)
        guard let eq = body.firstIndex(of: "=") else { continue }
        let name = String(body[..<eq])
        var value = String(body[body.index(after: eq)...])
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        exports[name] = value
    }
    return exports
}
