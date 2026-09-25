//
//  parse_command.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/parse_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Public API (`parseCommand`, `extractShellCommand`, `shlexJoin`) matches
//  upstream. The 2,766-line summarizer (head/cat/rg/find/git/cwd tracking)
//  is ported for the common word-only bash sequences; remaining script
//  walkers will follow the rest of that file.
//

import CodexProtocol
import Foundation

public func shlexJoin(_ tokens: [String]) -> String {
    tokens.map(posixShlexQuote).joined(separator: " ")
}

public func tokenizePowershellCommand(_ command: String) -> [String] {
    let normalized = command.replacingOccurrences(of: "\\", with: "/")
    var tokens = posixShlexSplit(normalized) ?? normalized.split(whereSeparator: \.isWhitespace).map(String.init)
    if var executable = tokens.first,
       ["get-content", "gc", "type"].contains(executable.lowercased()) {
        executable = "Get-Content"
        tokens[0] = executable
        if tokens.dropFirst().contains(where: { !normalized.contains($0) }) {
            return []
        }
    }
    return tokens
}

public func extractShellCommand(_ command: [String]) -> (shell: String, script: String)? {
    extractBashCommand(command) ?? extractPowershellCommand(command)
}

public func parseCommand(_ command: [String]) -> [ParsedCommand] {
    let parsed = parseCommandImpl(command)
    var deduped: [ParsedCommand] = []
    for cmd in parsed {
        if deduped.last == cmd { continue }
        deduped.append(cmd)
    }
    if deduped.contains(where: { if case .unknown = $0 { return true }; return false }) {
        return [singleUnknownForCommand(command)]
    }
    return deduped
}

private func singleUnknownForCommand(_ command: [String]) -> ParsedCommand {
    if let (_, shellCommand) = extractShellCommand(command) {
        return .unknown(cmd: shellCommand)
    }
    return .unknown(cmd: shlexJoin(command))
}

func parseCommandImpl(_ command: [String]) -> [ParsedCommand] {
    if let commands = parseShellLcPlainCommands(command) {
        return commands.map(summarizeTokens)
    }
    if extractBashCommand(command) != nil || extractPowershellCommand(command) != nil {
        return [singleUnknownForCommand(command)]
    }
    if command.isEmpty {
        return [.unknown(cmd: "")]
    }
    return [summarizeTokens(command)]
}

private func summarizeTokens(_ tokens: [String]) -> ParsedCommand {
    guard let first = tokens.first else { return .unknown(cmd: "") }
    let cmd = shlexJoin(tokens)
    let exe = (first as NSString).lastPathComponent
    switch exe {
    case "ls", "dir":
        let path = tokens.dropFirst().last { !$0.hasPrefix("-") }
        return .listFiles(cmd: cmd, path: path)
    case "cat", "head", "tail", "more", "less", "Get-Content", "gc", "type":
        let path = tokens.dropFirst().last { !$0.hasPrefix("-") } ?? first
        return .read(cmd: cmd, name: (path as NSString).lastPathComponent, path: path)
    case "rg", "grep", "find", "fd":
        let query = tokens.dropFirst().first { !$0.hasPrefix("-") }
        let path = tokens.dropFirst().drop(while: { $0.hasPrefix("-") || $0 == query }).last { !$0.hasPrefix("-") }
        return .search(cmd: cmd, query: query, path: path)
    default:
        return .unknown(cmd: cmd)
    }
}

private func posixShlexQuote(_ token: String) -> String {
    if token.isEmpty { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./-_"))
    if token.unicodeScalars.allSatisfy({ safe.contains($0) }) { return token }
    return "'" + token.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

func posixShlexSplit(_ input: String) -> [String]? {
    var tokens: [String] = []
    var current = ""
    var inSingle = false
    var inDouble = false
    var escaped = false
    var sawToken = false
    for ch in input {
        if escaped {
            current.append(ch)
            escaped = false
            sawToken = true
            continue
        }
        if ch == "\\" && !inSingle {
            escaped = true
            sawToken = true
            continue
        }
        if ch == "'" && !inDouble {
            inSingle.toggle()
            sawToken = true
            continue
        }
        if ch == "\"" && !inSingle {
            inDouble.toggle()
            sawToken = true
            continue
        }
        if ch.isWhitespace && !inSingle && !inDouble {
            if sawToken {
                tokens.append(current)
                current = ""
                sawToken = false
            }
            continue
        }
        current.append(ch)
        sawToken = true
    }
    if inSingle || inDouble || escaped { return nil }
    if sawToken { tokens.append(current) }
    return tokens
}
