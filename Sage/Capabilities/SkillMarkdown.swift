//
//  SkillMarkdown.swift
//  Sage
//
//  Shared SKILL.md frontmatter / name helpers used by SkillRegistry and SkillWriter.
//

import Foundation

enum SkillMarkdown {
    /// Validates a skill name per the Agent Skills spec:
    /// - 1–64 characters
    /// - Only lowercase alphanumeric and hyphens
    /// - Must not start or end with a hyphen
    /// - Must not contain consecutive hyphens
    static func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        guard !name.hasPrefix("-"), !name.hasSuffix("-") else { return false }
        guard !name.contains("--") else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    /// Finds the closing `---` of a YAML frontmatter block.
    /// Returns the range of the entire frontmatter (including both `---` delimiters)
    /// so the body can be extracted reliably even when it contains `---`.
    static func frontmatterRange(_ text: String) -> Range<String.Index>? {
        guard text.hasPrefix("---") else { return nil }
        guard let firstNewline = text.firstIndex(of: "\n") else { return nil }
        let afterOpener = text.index(after: firstNewline)
        var cursor = afterOpener
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd].trimmingCharacters(in: .whitespaces)
            if line == "---" {
                let blockEnd = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                return text.startIndex..<blockEnd
            }
            if lineEnd == text.endIndex { break }
            cursor = text.index(after: lineEnd)
        }
        return nil
    }

    static func stripFrontmatter(_ text: String) -> String {
        guard let range = frontmatterRange(text) else { return text }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Unquotes a simple YAML scalar (`"value"` → `value`).
    static func unquoteYAMLScalar(_ value: String) -> String {
        var result = value
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    /// Escapes a scalar for YAML frontmatter. Flattens newlines and quotes when needed.
    static func yamlScalar(_ value: String) -> String {
        let flattened = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let needsQuoting =
            flattened.isEmpty
            || flattened.contains(where: { ":#{}[]&*!|>'\"%@`,".contains($0) })
            || flattened.hasPrefix("-")
            || flattened.hasPrefix(" ")
            || flattened.hasSuffix(" ")
            || flattened.contains("---")

        guard needsQuoting else { return flattened }

        let escaped = flattened
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static let recognizedKeys: Set<String> = [
        "name", "description", "disable-model-invocation",
        "license", "compatibility", "allowed-tools", "source",
    ]

    struct ParsedFrontmatter: Sendable {
        var scalars: [String: String] = [:]
        var metadata: [String: String] = [:]
    }

    /// Parses YAML frontmatter scalars, including `|` / `>` block values.
    static func parseFrontmatter(_ text: String) -> ParsedFrontmatter {
        guard let range = frontmatterRange(text) else { return ParsedFrontmatter() }
        let lines = text[range].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result = ParsedFrontmatter()
        var inMetadata = false
        var index = 0

        while index < lines.count {
            let raw = lines[index]
            defer { index += 1 }

            if inMetadata {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if raw.hasPrefix("  ") || raw.hasPrefix("\t"), !trimmed.isEmpty, trimmed != "---" {
                    if let colon = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                        let value = unquoteYAMLScalar(
                            String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        )
                        if !key.isEmpty {
                            result.metadata[key] = value
                        }
                    }
                    continue
                }
                inMetadata = false
            }

            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)

            if key == "metadata" {
                let inlineValue = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if inlineValue.isEmpty {
                    inMetadata = true
                }
                continue
            }

            guard recognizedKeys.contains(key) else { continue }
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if value == "|" || value == ">" {
                let literal = value == "|"
                let blockLines = consumeYAMLBlockScalar(lines: lines, index: &index)
                value = literal
                    ? blockLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    : blockLines
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
            } else {
                value = unquoteYAMLScalar(value)
            }

            result.scalars[key] = value
        }
        return result
    }

    /// Upserts name / description / optional source into body text (adds frontmatter if missing).
    static func ensureFrontmatter(
        body: String,
        name: String,
        description: String,
        source: String?
    ) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = frontmatterRange(trimmed) {
            return upsertFrontmatterFields(
                trimmed,
                range: range,
                name: name,
                description: description,
                source: source
            )
        }

        var lines = [
            "---",
            "name: \(name)",
            "description: \(yamlScalar(description))",
        ]
        if let source, !source.isEmpty {
            lines.append("source: \(yamlScalar(source))")
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n") + trimmed + "\n"
    }

    private static func upsertFrontmatterFields(
        _ text: String,
        range: Range<String.Index>,
        name: String,
        description: String,
        source: String?
    ) -> String {
        let block = String(text[range])
        let markdownBody = String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeLast()
        }

        // Drop managed keys including multi-line `|` / `>` blocks.
        var kept: [String] = []
        var index = 0
        let managedKeys: Set<String> = ["name", "description", "source"]
        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            defer { index += 1 }
            if trimmedLine.isEmpty { continue }
            if let colon = trimmedLine.firstIndex(of: ":") {
                let key = String(trimmedLine[..<colon]).trimmingCharacters(in: .whitespaces)
                if managedKeys.contains(key) {
                    let value = String(trimmedLine[trimmedLine.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                    if value == "|" || value == ">" {
                        _ = consumeYAMLBlockScalar(lines: lines, index: &index)
                    }
                    continue
                }
            }
            kept.append(line)
        }

        var rebuilt = ["---", "name: \(name)", "description: \(yamlScalar(description))"]
        if let source, !source.isEmpty {
            rebuilt.append("source: \(yamlScalar(source))")
        }
        rebuilt.append(contentsOf: kept)
        rebuilt.append("---")
        rebuilt.append("")
        if !markdownBody.isEmpty {
            rebuilt.append(markdownBody)
            rebuilt.append("")
        }
        return rebuilt.joined(separator: "\n")
    }

    /// Advances `index` past a `|` / `>` block that begins on the current key line.
    /// On entry, `index` points at the key line; on exit, it points at the last consumed
    /// block line (callers that `defer { index += 1 }` then move to the next field).
    /// Returns dedented block content lines (empty lines preserved as `""`).
    private static func consumeYAMLBlockScalar(lines: [String], index: inout Int) -> [String] {
        index += 1
        var blockLines: [String] = []
        while index < lines.count {
            let blockRaw = lines[index]
            let trimmed = blockRaw.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if !blockRaw.isEmpty,
               !blockRaw.hasPrefix(" "),
               !blockRaw.hasPrefix("\t"),
               blockRaw.contains(":") {
                break
            }
            if blockRaw.hasPrefix("  ") {
                blockLines.append(String(blockRaw.dropFirst(2)))
            } else if blockRaw.hasPrefix("\t") {
                blockLines.append(String(blockRaw.dropFirst()))
            } else if trimmed.isEmpty {
                blockLines.append("")
            } else {
                break
            }
            index += 1
        }
        index -= 1
        return blockLines
    }
}
