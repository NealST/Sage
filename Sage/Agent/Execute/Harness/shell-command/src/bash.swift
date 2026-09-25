//
//  bash.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/bash.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  tree-sitter-bash via SwiftTreeSitter. Word-only sequence parsing and
//  literal command extraction match upstream node-kind allowlists.
//

import Foundation
import SwiftTreeSitter
import TreeSitterBash

public func tryParseShell(_ shellLcArg: String) -> Tree? {
    let language = Language(language: tree_sitter_bash())
    let parser = Parser()
    do {
        try parser.setLanguage(language)
    } catch {
        preconditionFailure("load bash grammar")
    }
    return parser.parse(shellLcArg)?.copy()
}

public func tryParseWordOnlyCommandsSequence(_ tree: Tree, src: String) -> [[String]]? {
    guard let root = tree.rootNode else { return nil }
    if root.hasError { return nil }
    let allowedKinds: Set<String> = [
        "program", "list", "pipeline",
        "command", "command_name", "word", "string", "string_content",
        "raw_string", "number", "concatenation",
    ]
    let allowedPunct: Set<String> = ["&&", "||", ";", "|", "\"", "'"]
    var stack = [root]
    var commandNodes: [Node] = []
    while let node = stack.popLast() {
        let kind = node.nodeType ?? ""
        if node.isNamed {
            if !allowedKinds.contains(kind) { return nil }
            if (kind == "word" || kind == "number") && !isLiteralWordOrNumber(node, src) {
                return nil
            }
            if kind == "command" { commandNodes.append(node) }
        } else {
            if kind.contains(where: { "&;|".contains($0) }) && !allowedPunct.contains(kind) {
                return nil
            }
            if !allowedPunct.contains(kind) && !kind.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
        }
        let cursor = node.treeCursor
        if cursor.goToFirstChild() {
            repeat {
                if let current = cursor.currentNode { stack.append(current) }
            } while cursor.gotoNextSibling()
        }
    }
    commandNodes.sort { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
    var commands: [[String]] = []
    for node in commandNodes {
        guard let words = parsePlainCommandFromNode(node, src) else { return nil }
        commands.append(words)
    }
    return commands
}

public func parseShellScriptIntoCommands(_ script: String) -> [[String]]? {
    guard let tree = tryParseShell(script) else { return nil }
    return tryParseWordOnlyCommandsSequence(tree, src: script)
}

public func extractBashCommand(_ command: [String]) -> (shell: String, script: String)? {
    guard command.count == 3 else { return nil }
    let shell = command[0]
    let flag = command[1]
    let script = command[2]
    guard flag == "-lc" || flag == "-c" else { return nil }
    guard let type = detectShellType(shell), type == .zsh || type == .bash || type == .sh else {
        return nil
    }
    return (shell, script)
}

public func parseShellLcPlainCommands(_ command: [String]) -> [[String]]? {
    guard let (_, script) = extractBashCommand(command) else { return nil }
    return parseShellScriptIntoCommands(script)
}

func parseShellLcLiteralCommands(_ command: [String]) -> [[String]]? {
    guard let (_, script) = extractBashCommand(command) else { return nil }
    guard let tree = tryParseShell(script) else { return nil }
    guard let root = tree.rootNode else { return nil }
    if root.hasError { return nil }
    var commands: [[String]] = []
    var stack = [root]
    while let node = stack.popLast() {
        if node.nodeType == "command", let command = parseLiteralCommandFromNode(node, script) {
            commands.append(command)
        }
        let cursor = node.treeCursor
        if cursor.goToFirstChild() {
            repeat {
                if let current = cursor.currentNode, current.isNamed { stack.append(current) }
            } while cursor.gotoNextSibling()
        }
    }
    return commands
}

private func parsePlainCommandFromNode(_ cmd: Node, _ src: String) -> [String]? {
    guard cmd.nodeType == "command" else { return nil }
    var words: [String] = []
    for child in namedChildren(cmd) {
        switch child.nodeType {
        case "command_name":
            guard let wordNode = namedChildren(child).first, wordNode.nodeType == "word" else {
                return nil
            }
            words.append(text(wordNode, src))
        case "word", "number":
            words.append(text(child, src))
        case "string":
            guard let parsed = parseDoubleQuotedString(child, src) else { return nil }
            words.append(parsed)
        case "raw_string":
            guard let parsed = parseRawString(child, src) else { return nil }
            words.append(parsed)
        case "concatenation":
            var concatenated = ""
            for part in namedChildren(child) {
                switch part.nodeType {
                case "word", "number":
                    concatenated += text(part, src)
                case "string":
                    guard let parsed = parseDoubleQuotedString(part, src) else { return nil }
                    concatenated += parsed
                case "raw_string":
                    guard let parsed = parseRawString(part, src) else { return nil }
                    concatenated += parsed
                default:
                    return nil
                }
            }
            if concatenated.isEmpty { return nil }
            words.append(concatenated)
        default:
            return nil
        }
    }
    return words
}

private func parseLiteralCommandFromNode(_ cmd: Node, _ src: String) -> [String]? {
    guard cmd.nodeType == "command" else { return nil }
    var words: [String] = []
    var foundCommandName = false
    for child in namedChildren(cmd) {
        if child.nodeType == "command_name" {
            guard let first = namedChildren(child).first,
                  let commandName = parseLiteralShellWord(first, src) else { return nil }
            words.append(commandName)
            foundCommandName = true
        } else if foundCommandName, let word = parseLiteralShellWord(child, src) {
            words.append(word)
        }
    }
    return foundCommandName ? words : nil
}

private func parseLiteralShellWord(_ node: Node, _ src: String) -> String? {
    switch node.nodeType {
    case "word", "number":
        return isLiteralWordOrNumber(node, src) ? text(node, src) : nil
    case "string":
        return parseDoubleQuotedString(node, src)
    case "raw_string":
        return parseRawString(node, src)
    case "concatenation":
        var concatenated = ""
        for part in namedChildren(node) {
            guard let piece = parseLiteralShellWord(part, src) else { return nil }
            concatenated += piece
        }
        return concatenated.isEmpty ? nil : concatenated
    default:
        return nil
    }
}

private func isLiteralWordOrNumber(_ node: Node, _ src: String) -> Bool {
    guard node.nodeType == "word" || node.nodeType == "number" else { return false }
    if !namedChildren(node).isEmpty { return false }
    let word = text(node, src)
    if word.hasPrefix("=") { return false }
    return !word.contains(where: { "{ } * ? [ ] \\ ~ ^ # $ `".contains($0) })
}

private func parseDoubleQuotedString(_ node: Node, _ src: String) -> String? {
    guard node.nodeType == "string" else { return nil }
    for part in namedChildren(node) where part.nodeType != "string_content" {
        return nil
    }
    let raw = text(node, src)
    guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else { return nil }
    let stripped = String(raw.dropFirst().dropLast())
    let bytes = Array(stripped.utf8)
    if bytes.indices.dropLast().contains(where: { i in
        bytes[i] == 0x5c && [UInt8]([0x24, 0x60, 0x22, 0x5c, 0x0a]).contains(bytes[i + 1])
    }) {
        return nil
    }
    return stripped
}

private func parseRawString(_ node: Node, _ src: String) -> String? {
    guard node.nodeType == "raw_string" else { return nil }
    let raw = text(node, src)
    guard raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 else { return nil }
    return String(raw.dropFirst().dropLast())
}

private func namedChildren(_ node: Node) -> [Node] {
    (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
}

private func text(_ node: Node, _ src: String) -> String {
    // SwiftTreeSitter's default `Parser.parse` uses UTF-16 LE, so node
    // byte offsets are UTF-16 code units × 2.
    let startByte = Int(node.byteRange.lowerBound)
    let endByte = Int(node.byteRange.upperBound)
    guard startByte >= 0, endByte >= startByte, startByte % 2 == 0, endByte % 2 == 0 else {
        return ""
    }
    let start = startByte / 2
    let end = endByte / 2
    let units = Array(src.utf16)
    guard end <= units.count else { return "" }
    return String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
}
