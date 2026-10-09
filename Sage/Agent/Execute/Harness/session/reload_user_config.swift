//
//  reload_user_config.swift
//  Sage
//
//  Port of `reload_user_config` / `reload_user_config_layer` in
//  codex-rs/core/src/session/handlers.rs and codex-rs/core/src/session/mod.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Reads the session's user config files and replaces the user layer only
//  when every file parses. A missing file is an empty layer. A read, parse,
//  or shell-policy failure keeps the previous layer and does not clear
//  caches. Feature gates and the session model stay as they were.
//  ConfigLayerStack, tool-suggest, hook rebuild, and the MCP protocol
//  feature flags wait. The TOML reader covers the user-layer subset this
//  reload validates.
//

import Foundation

enum UserConfigValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int64)
    case array([UserConfigValue])
    case table([String: UserConfigValue])
}

extension Session {
    /// rust `reload_user_config_layer`. Does not start a turn.
    func reloadUserConfigLayer() async {
        let paths = userConfigFilePaths()
        var loaded: [[String: UserConfigValue]] = []
        loaded.reserveCapacity(paths.count)
        for path in paths {
            switch readUserConfigFile(path) {
            case .missing:
                loaded.append([:])
            case .parsed(let table):
                if let message = shellEnvironmentPolicyFailure(table) {
                    _ = message
                    return
                }
                loaded.append(table)
            case .failed:
                return
            }
        }
        var merged: [String: UserConfigValue] = [:]
        for table in loaded {
            merged = mergeUserConfig(merged, table)
        }
        state.sessionConfiguration.userConfigLayer = merged
        skillsCacheGeneration += 1
        pluginsCacheGeneration += 1
        markMcpRuntimeDirty()
        scheduleMcpPrewarm()
        await refreshHooks(state.sessionConfiguration.originalConfig)
    }

    func userConfigFilePaths() -> [String] {
        let configured = state.sessionConfiguration.userConfigPaths
        if !configured.isEmpty { return configured }
        return [(state.sessionConfiguration.codexHome as NSString).appendingPathComponent("config.toml")]
    }
}

private enum ReadUserConfig {
    case missing
    case parsed([String: UserConfigValue])
    case failed
}

private func readUserConfigFile(_ path: String) -> ReadUserConfig {
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        return isFileNotFound(error) ? .missing : .failed
    }
    guard let text = String(data: data, encoding: .utf8) else { return .failed }
    guard let table = try? parseUserConfigToml(text) else { return .failed }
    return .parsed(table)
}

private func isFileNotFound(_ error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError { return true }
    if ns.domain == NSPOSIXErrorDomain && ns.code == Int(POSIXError.ENOENT.rawValue) { return true }
    return false
}

private func shellEnvironmentPolicyFailure(_ table: [String: UserConfigValue]) -> String? {
    guard case .table(let shell)? = table["shell_environment_policy"] else { return nil }
    guard let exclude = shell["exclude"] else { return nil }
    guard case .array(let items) = exclude,
          items.allSatisfy({ if case .string = $0 { return true }; return false })
    else {
        return "shell_environment_policy.exclude must be an array of strings"
    }
    return nil
}

private func mergeUserConfig(
    _ base: [String: UserConfigValue],
    _ overlay: [String: UserConfigValue]
) -> [String: UserConfigValue] {
    var merged = base
    for (key, value) in overlay {
        if case .table(let baseTable) = merged[key], case .table(let overlayTable) = value {
            merged[key] = .table(mergeUserConfig(baseTable, overlayTable))
        } else {
            merged[key] = value
        }
    }
    return merged
}

private func parseUserConfigToml(_ text: String) throws -> [String: UserConfigValue] {
    var parser = UserConfigTomlParser(text)
    return try parser.parse()
}

private struct UserConfigTomlParser {
    var text: String
    var index: String.Index

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    var isAtEnd: Bool { index == text.endIndex }

    mutating func parse() throws -> [String: UserConfigValue] {
        var root: [String: UserConfigValue] = [:]
        var context: [String] = []
        while true {
            skipTrivia(includingNewlines: true)
            if isAtEnd { return root }
            if peek() == "[" {
                context = try parseTableHeader()
                try ensureTable(&root, path: context)
            } else {
                let key = try parseKey()
                skipTrivia(includingNewlines: false)
                guard take("=") else { throw UserConfigTomlError("expected '='") }
                skipTrivia(includingNewlines: false)
                let value = try parseValue()
                try insert(&root, path: context + key, value: value)
            }
        }
    }

    mutating func parseTableHeader() throws -> [String] {
        guard take("[") else { throw UserConfigTomlError("expected '['") }
        if peek() == "[" { throw UserConfigTomlError("array of tables is not supported") }
        skipTrivia(includingNewlines: false)
        let path = try parseKey()
        skipTrivia(includingNewlines: false)
        guard take("]") else { throw UserConfigTomlError("expected ']'") }
        return path
    }

    mutating func parseKey() throws -> [String] {
        var parts: [String] = []
        parts.append(try parseBareKey())
        while true {
            let saved = index
            skipTrivia(includingNewlines: false)
            if take(".") {
                skipTrivia(includingNewlines: false)
                parts.append(try parseBareKey())
            } else {
                index = saved
                break
            }
        }
        return parts
    }

    mutating func parseBareKey() throws -> String {
        guard let first = peek(), first.isLetter || first == "_" else {
            throw UserConfigTomlError("expected key")
        }
        var key = ""
        while let character = peek(), character.isLetter || character.isNumber || character == "_" || character == "-" {
            key.append(character)
            advance()
        }
        return key
    }

    mutating func parseValue() throws -> UserConfigValue {
        if peek() == "\"" { return .string(try parseString()) }
        if peek() == "[" { return .array(try parseArray()) }
        if lookingAt("true") { advance(4); return .bool(true) }
        if lookingAt("false") { advance(5); return .bool(false) }
        return .int(try parseInt())
    }

    mutating func parseArray() throws -> [UserConfigValue] {
        guard take("[") else { throw UserConfigTomlError("expected '['") }
        var items: [UserConfigValue] = []
        while true {
            skipTrivia(includingNewlines: true)
            if take("]") { return items }
            items.append(try parseValue())
            skipTrivia(includingNewlines: true)
            if take(",") { continue }
            guard take("]") else { throw UserConfigTomlError("expected ']'") }
            return items
        }
    }

    mutating func parseString() throws -> String {
        guard take("\"") else { throw UserConfigTomlError("expected string") }
        var value = ""
        while let character = peek() {
            advance()
            if character == "\"" { return value }
            if character == "\n" { throw UserConfigTomlError("unterminated string") }
            if character == "\\" {
                guard let escaped = peek() else { throw UserConfigTomlError("unterminated escape") }
                advance()
                switch escaped {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": value.append("\r")
                case "\\", "\"": value.append(escaped)
                default: throw UserConfigTomlError("unsupported escape")
                }
            } else {
                value.append(character)
            }
        }
        throw UserConfigTomlError("unterminated string")
    }

    mutating func parseInt() throws -> Int64 {
        let negative = take("-")
        guard let first = peek(), first.isNumber else { throw UserConfigTomlError("expected value") }
        var digits = ""
        while let character = peek(), character.isNumber {
            digits.append(character)
            advance()
        }
        guard let magnitude = Int64(digits) else { throw UserConfigTomlError("integer overflow") }
        return negative ? -magnitude : magnitude
    }

    func ensureTable(_ root: inout [String: UserConfigValue], path: [String]) throws {
        var cursor = root
        for (offset, part) in path.enumerated() {
            if offset == path.count - 1 {
                if case .table? = cursor[part] { return }
                if cursor[part] != nil { throw UserConfigTomlError("key is not a table") }
                return
            }
            guard case .table(let child)? = cursor[part] else {
                if cursor[part] != nil { throw UserConfigTomlError("key is not a table") }
                break
            }
            cursor = child
        }
        try insert(&root, path: path, value: .table([:]))
    }

    func insert(
        _ root: inout [String: UserConfigValue],
        path: [String],
        value: UserConfigValue
    ) throws {
        guard let leaf = path.last else { throw UserConfigTomlError("empty key") }
        if path.count == 1 {
            if case .table = root[leaf], case .table = value {
                if case .table(let existing) = root[leaf], case .table(let incoming) = value {
                    root[leaf] = .table(mergeUserConfig(existing, incoming))
                }
                return
            }
            root[leaf] = value
            return
        }
        var child: [String: UserConfigValue]
        if case .table(let existing)? = root[path[0]] {
            child = existing
        } else if root[path[0]] == nil {
            child = [:]
        } else {
            throw UserConfigTomlError("key is not a table")
        }
        try insert(&child, path: Array(path.dropFirst()), value: value)
        root[path[0]] = .table(child)
    }

    mutating func skipTrivia(includingNewlines: Bool) {
        while !isAtEnd {
            if peek() == " " || peek() == "\t" || peek() == "\r" {
                advance()
                continue
            }
            if includingNewlines && peek() == "\n" {
                advance()
                continue
            }
            if peek() == "#" {
                while let character = peek(), character != "\n" { advance() }
                continue
            }
            return
        }
    }

    func peek() -> Character? {
        isAtEnd ? nil : text[index]
    }

    mutating func advance(_ count: Int = 1) {
        for _ in 0..<count where !isAtEnd {
            index = text.index(after: index)
        }
    }

    mutating func take(_ expected: Character) -> Bool {
        guard peek() == expected else { return false }
        advance()
        return true
    }

    func lookingAt(_ word: String) -> Bool {
        guard text[index...].hasPrefix(word) else { return false }
        let after = text.index(index, offsetBy: word.count, limitedBy: text.endIndex) ?? text.endIndex
        if after == text.endIndex { return true }
        let next = text[after]
        return !(next.isLetter || next.isNumber || next == "_" || next == "-")
    }
}

private struct UserConfigTomlError: Error {
    var message: String
    init(_ message: String) { self.message = message }
}
