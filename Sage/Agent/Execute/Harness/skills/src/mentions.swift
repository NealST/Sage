//
//  mentions.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/mentions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Mention slices become owned `String` values in `Set<String>`.
//

import Foundation

public struct ToolMentions: Equatable, Sendable {
    public var names: Set<String>
    public var paths: Set<String>
    public var plainNames: Set<String>

    public func isEmpty() -> Bool {
        names.isEmpty && paths.isEmpty
    }

    public func containsPlainName(_ name: String) -> Bool {
        plainNames.contains(name)
    }
}

public enum ToolMentionKind: Equatable, Sendable {
    case app
    case mcp
    case plugin
    case skill
    case other
}

let APP_PATH_PREFIX = "app://"
let MCP_PATH_PREFIX = "mcp://"
let PLUGIN_PATH_PREFIX = "plugin://"
let SKILL_PATH_PREFIX = "skill://"
let SKILL_FILENAME = "SKILL.md"
let TOOL_MENTION_SIGIL: Character = "$"

public func toolKindForPath(_ path: String) -> ToolMentionKind {
    if path.hasPrefix(APP_PATH_PREFIX) {
        return .app
    }
    if path.hasPrefix(MCP_PATH_PREFIX) {
        return .mcp
    }
    if path.hasPrefix(PLUGIN_PATH_PREFIX) {
        return .plugin
    }
    if path.hasPrefix(SKILL_PATH_PREFIX) || isSkillFilename(path) {
        return .skill
    }
    return .other
}

func isSkillFilename(_ path: String) -> Bool {
    let fileName = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    return fileName.compare(SKILL_FILENAME, options: .caseInsensitive) == .orderedSame
}

public func appIdFromPath(_ path: String) -> String? {
    guard let value = path.stripPrefix(APP_PATH_PREFIX), !value.isEmpty else { return nil }
    return value
}

/// Desktop app/browser mentions append `?app=...` or `?browserFamily=...`.
/// Ignore these targeting parameters when matching the plugin ID.
public func pluginConfigNameFromPath(_ path: String) -> String? {
    guard let value = path.stripPrefix(PLUGIN_PATH_PREFIX) else { return nil }
    let beforeQuery = value.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
        .map(String.init) ?? value
    return beforeQuery.isEmpty ? nil : beforeQuery
}

public func normalizeSkillPath(_ path: String) -> String {
    path.stripPrefix(SKILL_PATH_PREFIX) ?? path
}

/// Extract `$tool-name` mentions from a single text input.
public func extractToolMentions(_ text: String) -> ToolMentions {
    extractToolMentions(text, sigil: TOOL_MENTION_SIGIL)
}

public func extractToolMentions(_ text: String, sigil: Character) -> ToolMentions {
    let textBytes = Array(text.utf8)
    var mentionedNames = Set<String>()
    var mentionedPaths = Set<String>()
    var plainNames = Set<String>()
    let sigilByte = sigil.asciiValue ?? 0

    var index = 0
    while index < textBytes.count {
        let byte = textBytes[index]
        if byte == UInt8(ascii: "["),
           let parsed = parseLinkedToolMention(text, textBytes, start: index, sigil: sigil) {
            if !isCommonEnvVar(parsed.name) {
                switch toolKindForPath(parsed.path) {
                case .app, .mcp, .plugin:
                    break
                default:
                    mentionedNames.insert(parsed.name)
                }
                mentionedPaths.insert(parsed.path)
            }
            index = parsed.endIndex
            continue
        }

        if byte != sigilByte {
            index += 1
            continue
        }

        let nameStart = index + 1
        guard nameStart < textBytes.count else {
            index += 1
            continue
        }
        if !isMentionNameChar(textBytes[nameStart]) {
            index += 1
            continue
        }

        var nameEnd = nameStart + 1
        while nameEnd < textBytes.count, isMentionNameChar(textBytes[nameEnd]) {
            nameEnd += 1
        }

        let name = substringUTF8(text, start: nameStart, end: nameEnd)
        if !isCommonEnvVar(name) {
            mentionedNames.insert(name)
            plainNames.insert(name)
        }
        index = nameEnd
    }

    return ToolMentions(names: mentionedNames, paths: mentionedPaths, plainNames: plainNames)
}

private func parseLinkedToolMention(
    _ text: String,
    _ textBytes: [UInt8],
    start: Int,
    sigil: Character
) -> (name: String, path: String, endIndex: Int)? {
    let sigilIndex = start + 1
    guard sigilIndex < textBytes.count, textBytes[sigilIndex] == (sigil.asciiValue ?? 0) else {
        return nil
    }
    let nameStart = sigilIndex + 1
    guard nameStart < textBytes.count, isMentionNameChar(textBytes[nameStart]) else {
        return nil
    }
    var nameEnd = nameStart + 1
    while nameEnd < textBytes.count, isMentionNameChar(textBytes[nameEnd]) {
        nameEnd += 1
    }
    guard nameEnd < textBytes.count, textBytes[nameEnd] == UInt8(ascii: "]") else {
        return nil
    }

    var pathStart = nameEnd + 1
    while pathStart < textBytes.count {
        let byte = textBytes[pathStart]
        if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C {
            pathStart += 1
            continue
        }
        break
    }
    guard pathStart < textBytes.count, textBytes[pathStart] == UInt8(ascii: "(") else {
        return nil
    }

    var pathEnd = pathStart + 1
    while pathEnd < textBytes.count, textBytes[pathEnd] != UInt8(ascii: ")") {
        pathEnd += 1
    }
    guard pathEnd < textBytes.count, textBytes[pathEnd] == UInt8(ascii: ")") else {
        return nil
    }

    let path = substringUTF8(text, start: pathStart + 1, end: pathEnd)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if path.isEmpty { return nil }
    let name = substringUTF8(text, start: nameStart, end: nameEnd)
    return (name, path, pathEnd + 1)
}

func isCommonEnvVar(_ name: String) -> Bool {
    switch name.uppercased() {
    case "PATH", "HOME", "USER", "SHELL", "PWD", "TMPDIR", "TEMP", "TMP",
         "LANG", "TERM", "XDG_CONFIG_HOME":
        return true
    default:
        return false
    }
}

func isMentionNameChar(_ byte: UInt8) -> Bool {
    (byte >= 97 && byte <= 122)
        || (byte >= 65 && byte <= 90)
        || (byte >= 48 && byte <= 57)
        || byte == 95 || byte == 45 || byte == 58
}

func substringUTF8(_ text: String, start: Int, end: Int) -> String {
    let utf8 = text.utf8
    let startIndex = utf8.index(utf8.startIndex, offsetBy: start)
    let endIndex = utf8.index(utf8.startIndex, offsetBy: end)
    return String(decoding: utf8[startIndex..<endIndex], as: UTF8.self)
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
