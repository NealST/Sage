//
//  shell_snapshot_render.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_render.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Serialize prepared snapshot values without inspecting credentials or
//  executing shell code. Native declarations stay unchanged unless the
//  credential stage supplies a replacement.
//

import Foundation

struct SnapshotValue {
    var parts: [SnapshotValuePart] = []

    func render() -> String? {
        var output = ""
        for part in parts {
            switch part {
            case .literal(let value):
                output.append(posixShlexQuotePublic(value))
            case .credential(let key):
                output.append("\"${\(key)-}\"")
            }
        }
        if output.isEmpty { output.append("''") }
        return output
    }
}

enum SnapshotValuePart {
    case literal(String)
    case credential(key: String)
}

enum SnapshotExport {
    case captured(String)
    case assignment(declaration: String, value: SnapshotValue)
    case array(prefix: String, elements: [SnapshotValue], suffix: String)
    case arrayBinding(key: String, declaration: String, suffix: String)
}

func renderSnapshot(state: String, aliases: String, exports: [SnapshotExport]) -> String? {
    var output = state + aliases
    if !exports.isEmpty {
        output.append("# exports (native declarations)\n")
    }
    for export in exports {
        switch export {
        case .captured(let source):
            output.append(source)
        case .assignment(let declaration, let value):
            guard let rendered = value.render() else { return nil }
            output.append("\(declaration)=\(rendered)\n")
        case .array(let prefix, let elements, let suffix):
            var rendered: [String] = []
            rendered.reserveCapacity(elements.count)
            for element in elements {
                guard let piece = element.render() else { return nil }
                rendered.append(piece)
            }
            output.append("\(prefix)(\(rendered.joined(separator: " ")))\(suffix)")
        case .arrayBinding(let key, let declaration, let suffix):
            output.append(
                "if [ \"${\(key)+x}\" = x ]; then\n\(declaration)\(suffix.trimmingCharacters(in: .newlines))\nfi\n"
            )
        }
    }
    return output
}

public func renderShellSnapshot(_ snapshot: ShellSnapshot) -> String {
    snapshot.exports
        .sorted { $0.key < $1.key }
        .filter { !looksLikeCredentialName($0.key) }
        .map { key, value in "export \(key)=\(posixShlexQuotePublic(value))" }
        .joined(separator: "\n")
}

func posixShlexQuotePublic(_ token: String) -> String {
    if token.isEmpty { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./-_"))
    if token.unicodeScalars.allSatisfy({ safe.contains($0) }) { return token }
    return "'" + token.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
