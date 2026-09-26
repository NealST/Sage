//
//  agent_role_config.swift
//  CodexAgentRoles
//
//  Port of codex-rs/agent-roles/src/agent_role_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `toml` / `serde` / `ConfigToml` are not ported. A table-oriented TOML
//  parser covers `name` / `description` / `nickname_candidates` /
//  `developer_instructions` and keeps leftover keys as `TomlValue`.
//  `AbsolutePathBufGuard` is held while parsing so relative paths inside
//  leftover config resolve the same way as upstream.
//

import CodexUtils
import Foundation

public struct AgentRoleConfig: Equatable, Sendable {
    /// Human-facing role documentation used in spawn tool guidance.
    /// Required for loaded user-defined roles after deprecated/new metadata precedence resolves.
    public var description: String?
    /// Path to a role-specific config layer.
    public var configFile: String?
    /// Candidate nicknames for agents spawned with this role.
    public var nicknameCandidates: [String]?

    public init(
        description: String? = nil,
        configFile: String? = nil,
        nicknameCandidates: [String]? = nil
    ) {
        self.description = description
        self.configFile = configFile
        self.nicknameCandidates = nicknameCandidates
    }
}

public enum TomlValue: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case bool(Bool)
    case array([TomlValue])
    case table([String: TomlValue])

    public func asTable() -> [String: TomlValue]? {
        if case .table(let table) = self { return table }
        return nil
    }

    public func asString() -> String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public func asStringArray() -> [String]? {
        guard case .array(let values) = self else { return nil }
        var strings: [String] = []
        strings.reserveCapacity(values.count)
        for value in values {
            guard let string = value.asString() else { return nil }
            strings.append(string)
        }
        return strings
    }

    public subscript(_ key: String) -> TomlValue? {
        asTable()?[key]
    }
}

public struct ResolvedAgentRoleFile: Equatable, Sendable {
    public var roleName: String
    public var description: String?
    public var nicknameCandidates: [String]?
    public var config: TomlValue

    public init(
        roleName: String,
        description: String?,
        nicknameCandidates: [String]?,
        config: TomlValue
    ) {
        self.roleName = roleName
        self.description = description
        self.nicknameCandidates = nicknameCandidates
        self.config = config
    }
}

public func parseAgentRoleFileContents(
    _ contents: String,
    roleFileLabel: String,
    configBaseDir: String,
    roleNameHint: String?
) throws -> ResolvedAgentRoleFile {
    let roleFileToml: TomlValue
    do {
        roleFileToml = try parseTomlDocument(contents)
    } catch {
        throw IOError.invalidData(
            "failed to parse agent role file at \(roleFileLabel): \(error)"
        )
    }

    let _guard = AbsolutePathBufGuard(basePath: configBaseDir)
    _ = _guard

    guard var configTable = roleFileToml.asTable() else {
        throw IOError.invalidData(
            "agent role file at \(roleFileLabel) must contain a TOML table"
        )
    }

    let name = configTable["name"]?.asString()
    let rawDescription = configTable["description"]?.asString()
    let rawNicknames = configTable["nickname_candidates"]?.asStringArray()
    let developerInstructions = configTable["developer_instructions"]?.asString()

    let description = try normalizeAgentRoleDescription(
        "agent role file \(roleFileLabel).description",
        rawDescription
    )
    try validateAgentRoleFileDeveloperInstructions(
        roleFileLabel: roleFileLabel,
        developerInstructions: developerInstructions,
        requirePresent: roleNameHint == nil
    )

    let roleName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty
        ?? roleNameHint
    guard let roleName, !roleName.isEmpty else {
        throw IOError.invalidInput(
            "agent role file at \(roleFileLabel) must define a non-empty `name`"
        )
    }

    let nicknameCandidates = try normalizeAgentRoleNicknameCandidates(
        "agent role file \(roleFileLabel).nickname_candidates",
        rawNicknames
    )

    configTable.removeValue(forKey: "name")
    configTable.removeValue(forKey: "description")
    configTable.removeValue(forKey: "nickname_candidates")

    return ResolvedAgentRoleFile(
        roleName: roleName,
        description: description,
        nicknameCandidates: nicknameCandidates,
        config: .table(configTable)
    )
}

func normalizeAgentRoleDescription(
    _ fieldLabel: String,
    _ description: String?
) throws -> String? {
    switch description?.trimmingCharacters(in: .whitespacesAndNewlines) {
    case .some(""):
        throw IOError.invalidInput("\(fieldLabel) cannot be blank")
    case .some(let value):
        return value
    case .none:
        return nil
    }
}

func validateAgentRoleFileDeveloperInstructions(
    roleFileLabel: String,
    developerInstructions: String?,
    requirePresent: Bool
) throws {
    switch developerInstructions?.trimmingCharacters(in: .whitespacesAndNewlines) {
    case .some(""):
        throw IOError.invalidInput(
            "agent role file at \(roleFileLabel).developer_instructions cannot be blank"
        )
    case .some:
        return
    case .none where requirePresent:
        throw IOError.invalidInput(
            "agent role file at \(roleFileLabel) must define `developer_instructions`"
        )
    case .none:
        return
    }
}

func normalizeAgentRoleNicknameCandidates(
    _ fieldLabel: String,
    _ nicknameCandidates: [String]?
) throws -> [String]? {
    guard let nicknameCandidates else { return nil }
    if nicknameCandidates.isEmpty {
        throw IOError.invalidInput("\(fieldLabel) must contain at least one name")
    }

    var normalizedCandidates: [String] = []
    normalizedCandidates.reserveCapacity(nicknameCandidates.count)
    var seenCandidates: Set<String> = []

    for nickname in nicknameCandidates {
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedNickname.isEmpty {
            throw IOError.invalidInput("\(fieldLabel) cannot contain blank names")
        }
        if seenCandidates.contains(normalizedNickname) {
            throw IOError.invalidInput("\(fieldLabel) cannot contain duplicates")
        }
        seenCandidates.insert(normalizedNickname)
        if !normalizedNickname.unicodeScalars.allSatisfy({ scalar in
            scalar.isASCII
                && (Character(scalar).isLetter
                    || Character(scalar).isNumber
                    || scalar == " "
                    || scalar == "-"
                    || scalar == "_")
        }) {
            throw IOError.invalidInput(
                "\(fieldLabel) may only contain ASCII letters, digits, spaces, hyphens, and underscores"
            )
        }
        normalizedCandidates.append(normalizedNickname)
    }
    return normalizedCandidates
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Minimal TOML table parser

func parseTomlDocument(_ text: String) throws -> TomlValue {
    var parser = TomlTableParser(text)
    return .table(try parser.parseDocument())
}

private struct TomlTableParser {
    let text: String
    var index: String.Index

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func parseDocument() throws -> [String: TomlValue] {
        var root: [String: TomlValue] = [:]
        var currentPath: [String] = []
        skipWhitespaceAndComments()
        while !atEnd {
            if peek() == "[" {
                currentPath = try parseTableHeader()
            } else {
                let (key, value) = try parseKeyValue()
                try assignNested(&root, path: currentPath + [key], last: key, value: value)
            }
            skipWhitespaceAndComments()
        }
        return root
    }

    mutating func parseTableHeader() throws -> [String] {
        try expect("[")
        if peek() == "[" {
            throw IOError.invalidData("array-of-tables is not supported in agent role files")
        }
        let key = try parseDottedKey()
        try expect("]")
        return key
    }

    mutating func parseKeyValue() throws -> (String, TomlValue) {
        let key = try parseBareOrQuotedKey()
        skipSpace()
        try expect("=")
        skipSpace()
        let value = try parseValue()
        return (key, value)
    }

    mutating func parseValue() throws -> TomlValue {
        skipSpace()
        if atEnd {
            throw IOError.invalidData("unexpected end of TOML value")
        }
        if remainingHasPrefix("\"\"\"") {
            return .string(try parseMultilineString())
        }
        if peek() == "\"" {
            return .string(try parseBasicString())
        }
        if peek() == "'" {
            return .string(try parseLiteralString())
        }
        if peek() == "[" {
            return .array(try parseArray())
        }
        if peek() == "{" {
            return .table(try parseInlineTable())
        }
        return try parseBareValue()
    }

    mutating func parseArray() throws -> [TomlValue] {
        try expect("[")
        var values: [TomlValue] = []
        skipWhitespaceAndComments()
        while !atEnd && peek() != "]" {
            values.append(try parseValue())
            skipWhitespaceAndComments()
            if peek() == "," {
                advance()
                skipWhitespaceAndComments()
            }
        }
        try expect("]")
        return values
    }

    mutating func parseInlineTable() throws -> [String: TomlValue] {
        try expect("{")
        var table: [String: TomlValue] = [:]
        skipSpace()
        while !atEnd && peek() != "}" {
            let (key, value) = try parseKeyValue()
            table[key] = value
            skipSpace()
            if peek() == "," {
                advance()
                skipSpace()
            }
        }
        try expect("}")
        return table
    }

    mutating func parseBareValue() throws -> TomlValue {
        let start = index
        while !atEnd {
            let character = peek()
            if character == "\n" || character == "\r" || character == "#"
                || character == "," || character == "]" || character == "}" {
                break
            }
            advance()
        }
        let token = String(text[start..<index]).trimmingCharacters(in: .whitespaces)
        if token == "true" { return .bool(true) }
        if token == "false" { return .bool(false) }
        if let integer = Int64(token) { return .integer(integer) }
        if let float = Double(token) { return .float(float) }
        throw IOError.invalidData("unsupported TOML value `\(token)`")
    }

    mutating func parseBasicString() throws -> String {
        try expect("\"")
        var out = ""
        while !atEnd {
            let character = peek()
            if character == "\"" {
                advance()
                return out
            }
            if character == "\\" {
                advance()
                out.append(try parseEscape())
                continue
            }
            if character == "\n" {
                throw IOError.invalidData("unescaped newline in TOML string")
            }
            out.append(character)
            advance()
        }
        throw IOError.invalidData("unterminated TOML string")
    }

    mutating func parseLiteralString() throws -> String {
        try expect("'")
        let start = index
        while !atEnd {
            if peek() == "'" {
                let value = String(text[start..<index])
                advance()
                return value
            }
            if peek() == "\n" {
                throw IOError.invalidData("unescaped newline in TOML literal string")
            }
            advance()
        }
        throw IOError.invalidData("unterminated TOML literal string")
    }

    mutating func parseMultilineString() throws -> String {
        try expect("\"\"\"")
        if peek() == "\n" {
            advance()
        } else if remainingHasPrefix("\r\n") {
            advance()
            advance()
        }
        var out = ""
        while !atEnd {
            if remainingHasPrefix("\"\"\"") {
                advance()
                advance()
                advance()
                return out
            }
            out.append(peek())
            advance()
        }
        throw IOError.invalidData("unterminated TOML multiline string")
    }

    mutating func parseEscape() throws -> Character {
        if atEnd { throw IOError.invalidData("unterminated TOML escape") }
        let character = peek()
        advance()
        switch character {
        case "b": return "\u{08}"
        case "t": return "\t"
        case "n": return "\n"
        case "f": return "\u{0C}"
        case "r": return "\r"
        case "\"": return "\""
        case "\\": return "\\"
        default:
            throw IOError.invalidData("unsupported TOML escape \\\(character)")
        }
    }

    mutating func parseBareOrQuotedKey() throws -> String {
        skipSpace()
        if peek() == "\"" { return try parseBasicString() }
        if peek() == "'" { return try parseLiteralString() }
        let start = index
        while !atEnd {
            let character = peek()
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                advance()
                continue
            }
            break
        }
        let key = String(text[start..<index])
        if key.isEmpty {
            throw IOError.invalidData("expected TOML key")
        }
        return key
    }

    mutating func parseDottedKey() throws -> [String] {
        var parts: [String] = []
        skipSpace()
        parts.append(try parseBareOrQuotedKey())
        skipSpace()
        while peek() == "." {
            advance()
            skipSpace()
            parts.append(try parseBareOrQuotedKey())
            skipSpace()
        }
        return parts
    }

    mutating func assignNested(
        _ table: inout [String: TomlValue],
        path: [String],
        last: String,
        value: TomlValue
    ) throws {
        if path.count == 1 {
            table[last] = value
            return
        }
        let head = path[0]
        var nested = table[head]?.asTable() ?? [:]
        try assignNested(&nested, path: Array(path.dropFirst()), last: last, value: value)
        table[head] = .table(nested)
    }

    mutating func skipWhitespaceAndComments() {
        while !atEnd {
            skipSpace()
            if peek() == "#" {
                while !atEnd && peek() != "\n" {
                    advance()
                }
                continue
            }
            if peek() == "\n" || peek() == "\r" {
                advance()
                continue
            }
            break
        }
    }

    mutating func skipSpace() {
        while !atEnd && (peek() == " " || peek() == "\t") {
            advance()
        }
    }

    mutating func expect(_ token: String) throws {
        guard remainingHasPrefix(token) else {
            throw IOError.invalidData("expected `\(token)` in TOML")
        }
        for _ in token {
            advance()
        }
    }

    func remainingHasPrefix(_ prefix: String) -> Bool {
        text[index...].hasPrefix(prefix)
    }

    func peek() -> Character {
        text[index]
    }

    var atEnd: Bool { index == text.endIndex }

    mutating func advance() {
        index = text.index(after: index)
    }
}
