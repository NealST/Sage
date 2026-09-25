//
//  sandbox_migration.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/sandbox_migration.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  One-shot removal of banned allow prefix rules. `tempfile::persist_noclobber`
//  is `FileManager.createFile` with no overwrite for the marker.
//

import Foundation

let MIGRATION_MARKER_FILENAME = ".sandbox_migration"

public func prefixRuleMigration(
    codexHome: String,
    policyPath: String,
    bannedPrefixes: [[String]]
) async throws {
    let markerPath = (codexHome as NSString).appendingPathComponent(MIGRATION_MARKER_FILENAME)
    if FileManager.default.fileExists(atPath: markerPath) {
        return
    }
    try await cleanRulesFile(policyPath: policyPath, bannedPrefixes: bannedPrefixes)
    try await writeMigrationMarker(codexHome: codexHome, markerPath: markerPath)
}

private func writeMigrationMarker(codexHome: String, markerPath: String) async throws {
    try FileManager.default.createDirectory(atPath: codexHome, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: markerPath) {
        return
    }
    let created = FileManager.default.createFile(
        atPath: markerPath,
        contents: Data("v1\n".utf8),
        attributes: nil
    )
    if !created && !FileManager.default.fileExists(atPath: markerPath) {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST))
    }
}

private func cleanRulesFile(policyPath: String, bannedPrefixes: [[String]]) async throws {
    guard FileManager.default.fileExists(atPath: policyPath) else { return }
    let contents = try String(contentsOfFile: policyPath, encoding: .utf8)
    let retained = stripBannedAllowRules(contents, bannedPrefixes: bannedPrefixes)
    if retained == contents { return }
    try retained.write(toFile: policyPath, atomically: true, encoding: .utf8)
}

func stripBannedAllowRules(_ contents: String, bannedPrefixes: [[String]]) -> String {
    let banned = Set(bannedPrefixes.map { $0.map { $0.lowercased() } })
    var kept: [String] = []
    var index = contents.startIndex
    while index < contents.endIndex {
        let next = contents[index...].firstIndex(of: "\n").map { contents.index(after: $0) } ?? contents.endIndex
        let line = String(contents[index..<next])
        if !shouldRemoveRule(line, bannedPrefixes: banned) {
            kept.append(line)
        }
        index = next
    }
    return kept.joined()
}

private func shouldRemoveRule(_ line: String, bannedPrefixes: Set<[String]>) -> Bool {
    var trimmed = line
    if trimmed.hasSuffix("\n") { trimmed.removeLast() }
    if trimmed.hasSuffix("\r") { trimmed.removeLast() }
    guard trimmed.hasPrefix("prefix_rule(pattern="),
          trimmed.hasSuffix(", decision=\"allow\")") else {
        return false
    }
    let pattern = String(trimmed.dropFirst("prefix_rule(pattern=".count).dropLast(", decision=\"allow\")".count))
    guard let data = pattern.data(using: .utf8),
          let prefix = try? JSONDecoder().decode([String].self, from: data) else {
        return false
    }
    return bannedPrefixes.contains(prefix.map { $0.lowercased() })
}
