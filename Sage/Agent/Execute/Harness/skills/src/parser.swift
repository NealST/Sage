//
//  parser.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `serde_yaml` is a line-oriented frontmatter map parser plus the same
//  scalar-repair pass. Block scalars (`|` / `|-`) keep indented bodies.
//

import Foundation

let SKILL_MAX_NAME_LEN = 64

/// Validated metadata parsed from a `SKILL.md` frontmatter block.
public struct ParsedSkillFrontmatter: Equatable, Sendable {
    public var name: String
    public var description: String
    public var shortDescription: String?

    public init(name: String, description: String, shortDescription: String? = nil) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
    }
}

/// Error produced while parsing or validating `SKILL.md` metadata.
public enum SkillParseError: Error, Equatable, CustomStringConvertible {
    case missingFrontmatter
    case invalidYaml(String)
    case missingField(String)
    case invalidField(field: String, reason: String)

    public var description: String {
        switch self {
        case .missingFrontmatter:
            return "missing YAML frontmatter delimited by ---"
        case .invalidYaml(let message):
            return "invalid YAML: \(message)"
        case .missingField(let field):
            return "missing field `\(field)`"
        case .invalidField(let field, let reason):
            return "invalid \(field): \(reason)"
        }
    }
}

/// Parses and validates the metadata frontmatter from `SKILL.md` contents.
public func parseSkillFrontmatterMetadata(
    _ contents: String,
    defaultName: () -> String
) throws -> ParsedSkillFrontmatter {
    guard let frontmatter = extractFrontmatter(contents) else {
        throw SkillParseError.missingFrontmatter
    }

    let parsed: SkillFrontmatter
    do {
        parsed = try parseSkillFrontmatterMap(frontmatter)
    } catch {
        if let repaired = repairFrontmatterScalarFields(frontmatter) {
            parsed = try parseSkillFrontmatterMap(repaired)
        } else {
            throw SkillParseError.invalidYaml(String(describing: error))
        }
    }

    let name = parsed.name
        .map(sanitizeSingleLine)
        .flatMap { $0.isEmpty ? nil : $0 }
        ?? defaultName()
    let description = parsed.description.map(sanitizeSingleLine) ?? ""
    let shortDescription = parsed.shortDescription
        .map(sanitizeSingleLine)
        .flatMap { $0.isEmpty ? nil : $0 }

    try validateLen(name, maxLen: SKILL_MAX_NAME_LEN, fieldName: "name")
    if description.isEmpty {
        throw SkillParseError.missingField("description")
    }

    return ParsedSkillFrontmatter(
        name: name,
        description: description,
        shortDescription: shortDescription
    )
}

private struct SkillFrontmatter {
    var name: String?
    var description: String?
    var shortDescription: String?
}

func sanitizeSingleLine(_ raw: String) -> String {
    raw.split { $0.isWhitespace }.joined(separator: " ")
}

func repairFrontmatterScalarFields(_ frontmatter: String) -> String? {
    var changed = false
    var blockScalarIndent: Int?
    var repairedLines: [String] = []
    for line in frontmatter.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        let indent = line.prefix(while: { $0 == " " }).count
        if let blockIndent = blockScalarIndent {
            if line.trimmingCharacters(in: .whitespaces).isEmpty || indent > blockIndent {
                repairedLines.append(line)
                continue
            }
            blockScalarIndent = nil
        }

        guard let colon = line.firstIndex(of: ":") else {
            repairedLines.append(line)
            continue
        }
        let key = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])
        if key.trimmingCharacters(in: .whitespaces).isEmpty
            || !(value.first?.isWhitespace ?? true) {
            repairedLines.append(line)
            continue
        }

        let trimmedStart = String(value.drop(while: { $0.isWhitespace }))
        let leadingWhitespaceCount = value.count - trimmedStart.count
        let leadingWhitespace = String(value.prefix(leadingWhitespaceCount))
        var scalar = trimmedStart
        var comment = ""
        var charIndex = 0
        for character in trimmedStart {
            if character == "#" {
                let prefix = String(trimmedStart.prefix(charIndex))
                if charIndex == 0 || prefix.last?.isWhitespace == true {
                    var end = prefix.endIndex
                    while end > prefix.startIndex {
                        let previous = prefix.index(before: end)
                        if prefix[previous].isWhitespace {
                            end = previous
                        } else {
                            break
                        }
                    }
                    let commentStart = prefix.distance(from: prefix.startIndex, to: end)
                    scalar = String(trimmedStart.prefix(commentStart))
                    comment = String(trimmedStart.dropFirst(commentStart))
                    break
                }
            }
            charIndex += 1
        }

        let scalarTrimmed = scalar.trimmingCharacters(in: .whitespaces)
        guard let firstChar = scalarTrimmed.first else {
            repairedLines.append(line)
            continue
        }
        if firstChar == "|" || firstChar == ">" {
            blockScalarIndent = indent
            repairedLines.append(line)
            continue
        }
        if firstChar == "'" || firstChar == "\"" {
            repairedLines.append(line)
            continue
        }
        var hasColonSeparator = false
        let scalars = Array(scalarTrimmed)
        for i in scalars.indices {
            if scalars[i] == ":", i + 1 < scalars.count, scalars[i + 1].isWhitespace {
                hasColonSeparator = true
                break
            }
        }
        let invalidFlowLike = firstChar == "[" || firstChar == "{" || firstChar == "@" || firstChar == "`"
        if !hasColonSeparator && !invalidFlowLike {
            repairedLines.append(line)
            continue
        }

        let quotedScalar = "'\(scalarTrimmed.replacingOccurrences(of: "'", with: "''"))'"
        repairedLines.append("\(key):\(leadingWhitespace)\(quotedScalar)\(comment)")
        changed = true
    }
    return changed ? repairedLines.joined(separator: "\n") : nil
}

func validateLen(_ value: String, maxLen: Int, fieldName: String) throws {
    if value.isEmpty {
        throw SkillParseError.missingField(fieldName)
    }
    if value.count > maxLen {
        throw SkillParseError.invalidField(
            field: fieldName,
            reason: "exceeds maximum length of \(maxLen) characters"
        )
    }
}

func extractFrontmatter(_ contents: String) -> String? {
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
        return nil
    }
    var frontmatterLines: [String] = []
    var foundClosing = false
    for line in lines.dropFirst() {
        if line.trimmingCharacters(in: .whitespaces) == "---" {
            foundClosing = true
            break
        }
        frontmatterLines.append(line)
    }
    if frontmatterLines.isEmpty || !foundClosing {
        return nil
    }
    return frontmatterLines.joined(separator: "\n")
}

private func parseSkillFrontmatterMap(_ frontmatter: String) throws -> SkillFrontmatter {
    var name: String?
    var description: String?
    var shortDescription: String?
    let lines = frontmatter.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var index = 0
    var inMetadata = false
    while index < lines.count {
        let line = lines[index]
        let indent = line.prefix(while: { $0 == " " }).count
        if indent == 0 {
            inMetadata = false
        }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("metadata:") {
            inMetadata = true
            index += 1
            continue
        }
        guard let colon = line.firstIndex(of: ":") else {
            index += 1
            continue
        }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: colon)...])
        if value.trimmingCharacters(in: .whitespaces).hasPrefix("|")
            || value.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            let (body, consumed) = readBlockScalar(lines, start: index, parentIndent: indent)
            value = body
            index = consumed
            assignFrontmatterField(
                key: key,
                value: value,
                inMetadata: inMetadata,
                name: &name,
                description: &description,
                shortDescription: &shortDescription
            )
            continue
        }
        assignFrontmatterField(
            key: key,
            value: unquoteYAMLScalar(value.trimmingCharacters(in: .whitespaces)),
            inMetadata: inMetadata,
            name: &name,
            description: &description,
            shortDescription: &shortDescription
        )
        index += 1
    }
    return SkillFrontmatter(name: name, description: description, shortDescription: shortDescription)
}

func readBlockScalar(_ lines: [String], start: Int, parentIndent: Int) -> (String, Int) {
    var body: [String] = []
    var index = start + 1
    while index < lines.count {
        let line = lines[index]
        let indent = line.prefix(while: { $0 == " " }).count
        if line.trimmingCharacters(in: .whitespaces).isEmpty || indent > parentIndent {
            let stripped = line.drop(while: { $0 == " " }).drop(while: { $0 == " " })
            // Strip one indent level beyond the parent (typically 2 spaces).
            if line.count >= parentIndent + 2 {
                body.append(String(line.dropFirst(parentIndent + 2)))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                body.append("")
            } else {
                body.append(String(line.drop(while: { $0 == " " })))
            }
            _ = stripped
            index += 1
            continue
        }
        break
    }
    return (body.joined(separator: "\n"), index)
}

func assignFrontmatterField(
    key: String,
    value: String,
    inMetadata: Bool,
    name: inout String?,
    description: inout String?,
    shortDescription: inout String?
) {
    switch key {
    case "name" where !inMetadata:
        name = value
    case "description" where !inMetadata:
        description = value
    case "short-description" where inMetadata:
        shortDescription = value
    default:
        break
    }
}

func unquoteYAMLScalar(_ value: String) -> String {
    if value.count >= 2, value.first == "'", value.last == "'" {
        let inner = String(value.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "''", with: "'")
    }
    if value.count >= 2, value.first == "\"", value.last == "\"" {
        return String(value.dropFirst().dropLast())
    }
    return value
}
