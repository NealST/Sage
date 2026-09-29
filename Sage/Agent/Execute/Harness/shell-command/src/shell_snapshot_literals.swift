//
//  shell_snapshot_literals.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_literals.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Literal word decoder for snapshot replay. tree-sitter byte offsets are
//  UTF-16 units × 2 (same as bash.swift). `shlex::split` is posixShlexSplit.
//

import Foundation
import SwiftTreeSitter

enum SnapshotQuoting: Hashable {
    case posix
    case legacyBash
    case zshRcQuotes

    static func deferredModes(_ shellType: ShellType) -> [SnapshotQuoting] {
        switch shellType {
        case .bash, .sh: return [.posix, .legacyBash]
        default: return [.posix, .zshRcQuotes]
        }
    }
}

private enum SnapshotParsing {
    case snapshot
    case deferred(SnapshotQuoting)
}

public func isLiteralAssignmentValue(_ value: String) -> Bool {
    !value.contains(where: { "$`!".contains($0) })
}

func snapshotLiteralWords(_ script: String, shellType: ShellType) -> [String]? {
    var shellType = shellType
    if shellType == .sh, script.hasPrefix(bashShSnapshotHeader) {
        shellType = .bash
    }
    var checkedAliases = Set<SnapshotAliasKey>()
    guard var words = literalWordsWithQuoting(
        script, shellType: shellType, parsing: .snapshot, checkedAliases: &checkedAliases
    ) else { return nil }
    if shellType == .bash || shellType == .sh {
        guard let extra = literalWordsWithQuoting(
            script, shellType: shellType, parsing: .deferred(.legacyBash),
            checkedAliases: &checkedAliases
        ) else { return nil }
        words.append(contentsOf: extra)
    }
    return words
}

private struct SnapshotAliasKey: Hashable {
    var body: String
    var quoting: SnapshotQuoting
}

private struct NodeQuoteKey: Hashable {
    var id: UInt
    var quoting: SnapshotQuoting
}

private func literalWordsWithQuoting(
    _ script: String,
    shellType: ShellType,
    parsing: SnapshotParsing,
    checkedAliases: inout Set<SnapshotAliasKey>
) -> [String]? {
    guard let tree = tryParseShell(script), let root = tree.rootNode else { return nil }
    var quoting: SnapshotQuoting
    switch parsing {
    case .snapshot: quoting = .posix
    case .deferred(let value): quoting = value
    }
    var pending: [(Node, SnapshotQuoting)] = []
    for node in namedChildren(root) {
        if case .snapshot = parsing, node.nodeType == "command" {
            switch nodeText(node, script) {
            case "setopt rcquotes": quoting = .zshRcQuotes
            case "unsetopt rcquotes": quoting = .posix
            default: break
            }
        }
        pending.append((node, quoting))
    }
    var words: [String] = []
    var checkedNodes = Set<NodeQuoteKey>()
    while let (node, quoting) = pending.popLast() {
        if !checkedNodes.insert(NodeQuoteKey(id: node.id, quoting: quoting)).inserted {
            continue
        }
        let kind = node.nodeType ?? ""
        if kind == "command_substitution" || kind == "process_substitution" {
            if let raw = Optional(nodeText(node, script)),
               raw.hasPrefix("`"), raw.hasSuffix("`"), raw.count >= 2 {
                let bodySource = String(raw.dropFirst().dropLast())
                var context = node.parent
                if shellType == .zsh {
                    while let parent = context,
                          parent.nodeType == "expansion" || parent.nodeType == "concatenation" {
                        context = parent.parent
                    }
                }
                let inDoubleQuotes = context?.nodeType == "string"
                var body = ""
                var chars = Array(bodySource)
                var i = 0
                while i < chars.count {
                    let character = chars[i]
                    i += 1
                    if character == "\\" {
                        if i < chars.count, chars[i] == "\n" {
                            i += 1
                            continue
                        }
                        if i < chars.count, ["$", "`", "\\"].contains(chars[i]) {
                            body.append(chars[i])
                            i += 1
                            continue
                        }
                        if inDoubleQuotes, i < chars.count, chars[i] == "\"" {
                            body.append(chars[i])
                            i += 1
                            continue
                        }
                    }
                    body.append(character)
                }
                for mode in SnapshotQuoting.deferredModes(shellType) {
                    let key = SnapshotAliasKey(body: body, quoting: mode)
                    if checkedAliases.insert(key).inserted {
                        guard let extra = literalWordsWithQuoting(
                            body, shellType: shellType, parsing: .deferred(mode),
                            checkedAliases: &checkedAliases
                        ) else { return nil }
                        words.append(contentsOf: extra)
                    }
                }
                continue
            }
            for child in namedChildren(node) {
                for mode in SnapshotQuoting.deferredModes(shellType) {
                    pending.append((child, mode))
                }
            }
            continue
        }
        if kind == "heredoc_body" {
            guard let parent = node.parent else { return nil }
            guard let delimiterNode = namedChildren(parent).first(where: { $0.nodeType == "heredoc_start" }) else {
                return nil
            }
            let delimiter = nodeText(delimiterNode, script)
            let quoted = delimiter.contains(where: { "'\"\\".contains($0) })
            let stripTabs = allChildren(parent).contains { $0.nodeType == "<<-" }
            var start = utf16Start(node)
            let ends = namedChildren(node).filter { !quoted && $0.nodeType != "heredoc_content" }
            for endNode in ends + [nil as Node?] {
                let end = endNode.map(utf16Start) ?? utf16End(node)
                guard var text = utf16Slice(script, start, end) else { return nil }
                if stripTabs {
                    text = text.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { line -> String in
                            let raw = String(line)
                            if raw.hasSuffix("\n") {
                                let body = String(raw.dropLast())
                                return String(body.drop(while: { $0 == "\t" })) + "\n"
                            }
                            return String(raw.drop(while: { $0 == "\t" }))
                        }
                        .joined()
                }
                var decoded = ""
                var chars = Array(text)
                var i = 0
                while i < chars.count {
                    let character = chars[i]
                    i += 1
                    if !quoted, character == "\\" {
                        if i < chars.count, chars[i] == "\n" {
                            i += 1
                            continue
                        }
                        if i < chars.count, ["$", "`", "\\"].contains(chars[i]) {
                            decoded.append(chars[i])
                            i += 1
                            continue
                        }
                    }
                    decoded.append(character)
                }
                words.append(decoded)
                if let child = endNode {
                    start = utf16End(child)
                    pending.append((child, quoting))
                }
            }
            continue
        }
        var commandWords: [(range: Range<Int>, word: [UInt8]?)] = []
        var declaration: String?
        if kind == "command" {
            var arguments: [Node] = []
            if let name = node.child(byFieldName: "name") {
                arguments.append(name)
            }
            arguments.append(contentsOf: childrenByField(node, "argument"))
            for argument in arguments {
                let word = snapshotLiteralWordBytes(argument, script: script, shellType: shellType, quoting: quoting)
                if shellType == .zsh,
                   var previous = commandWords.last,
                   hasContinuationGap(script, previous.range.upperBound, utf16Start(argument)) {
                    previous.word = zipOptional(previous.word, word).map { left, right in
                        var out = left
                        out.append(contentsOf: right)
                        return out
                    }
                    previous.range = previous.range.lowerBound..<utf16End(argument)
                    commandWords[commandWords.count - 1] = previous
                } else {
                    commandWords.append((utf16Range(argument), word))
                }
            }
            var names = commandWords.map { pair -> String? in
                pair.word.map { String(decoding: $0, as: UTF8.self) }
            }
            var name = names.isEmpty ? nil : names.removeFirst()
            declarationLoop: while true {
                switch name {
                case "alias", "declare", "typeset", "local", "readonly", "export":
                    declaration = name
                    break declarationLoop
                case "noglob" where shellType == .zsh, "-" where shellType == .zsh:
                    name = names.isEmpty ? nil : names.removeFirst()
                case "time":
                    name = names.isEmpty ? nil : names.removeFirst()
                    if shellType == .bash, name == "-p" {
                        name = names.isEmpty ? nil : names.removeFirst()
                    }
                case "builtin", "command":
                    let prefix = name
                    name = names.isEmpty ? nil : names.removeFirst()
                    if prefix == "command" {
                        while let argument = name,
                              let options = argument.stripPrefix("-"),
                              !options.isEmpty,
                              options.utf8.allSatisfy({ $0 == 0x70 }) {
                            name = names.isEmpty ? nil : names.removeFirst()
                        }
                    }
                    if (prefix == "command" || (prefix == "builtin" && shellType != .zsh)),
                       name == "--" {
                        name = names.isEmpty ? nil : names.removeFirst()
                    }
                default:
                    declaration = nil
                    break declarationLoop
                }
            }
        } else {
            declaration = nil
        }
        let isAlias = declaration == "alias"
        let mayInitializeArray = shellType == .bash
            && (kind == "declaration_command" || (declaration != nil && !isAlias))
        if isAlias || mayInitializeArray {
            for argument in namedChildren(node) {
                if commandWords.contains(where: {
                    $0.range.lowerBound < utf16Start(argument) && utf16End(argument) <= $0.range.upperBound
                }) {
                    continue
                }
                let continued = commandWords.first(where: {
                    $0.range.lowerBound == utf16Start(argument) && $0.range.upperBound > utf16End(argument)
                })
                let decoded: [UInt8]?
                if let continued {
                    decoded = continued.word
                } else if let word = snapshotLiteralWordBytes(
                    argument, script: script, shellType: shellType, quoting: quoting
                ) {
                    decoded = word
                } else {
                    let end = continued?.range.upperBound ?? utf16End(argument)
                    var pieces: [Node] = []
                    var piece: Node? = argument
                    while let current = piece, utf16End(current) <= end {
                        pieces.append(current)
                        piece = current.nextNamedSibling
                    }
                    pieces.reverse()
                    var word: [UInt8] = []
                    var failed = false
                    while let current = pieces.popLast() {
                        if let literal = snapshotLiteralWordBytes(
                            current, script: script, shellType: shellType, quoting: quoting
                        ) {
                            word.append(contentsOf: literal)
                            continue
                        }
                        switch current.nodeType {
                        case "variable_assignment":
                            word.append(contentsOf: Array("_=".utf8))
                            if let value = current.child(byFieldName: "value") {
                                pieces.append(value)
                            } else {
                                failed = true
                            }
                        case "concatenation", "string":
                            pieces.append(contentsOf: namedChildren(current).reversed())
                        case "string_content":
                            let text = nodeText(current, script)
                            guard let decoded = posixShlexSplit("\"\(text)\""), decoded.count == 1 else {
                                failed = true
                                break
                            }
                            word.append(contentsOf: Array(decoded[0].utf8))
                        case "simple_expansion", "expansion", "command_substitution",
                             "process_substitution", "arithmetic_expansion":
                            word.append(contentsOf: Array("${__codex_snapshot_dynamic}".utf8))
                        default:
                            failed = true
                        }
                        if failed { break }
                    }
                    decoded = failed ? nil : word
                }
                if let assignment = decoded.map({ String(decoding: $0, as: UTF8.self) }),
                   let eq = assignment.firstIndex(of: "=") {
                    var body = String(assignment[assignment.index(after: eq)...])
                    if mayInitializeArray {
                        var trimmed = body
                        if let stripped = trimmed.stripPrefix("${__codex_snapshot_dynamic}") {
                            trimmed = stripped
                        }
                        if let stripped = Optional(trimmed).flatMap({ $0.hasSuffix("${__codex_snapshot_dynamic}") ? String($0.dropLast("${__codex_snapshot_dynamic}".count)) : $0 }) {
                            trimmed = stripped
                        }
                        if !trimmed.hasPrefix("(") || !trimmed.hasSuffix(")") {
                            continue
                        }
                        body = "_=\(trimmed)"
                    }
                    for mode in SnapshotQuoting.deferredModes(shellType) {
                        let key = SnapshotAliasKey(body: body, quoting: mode)
                        if checkedAliases.insert(key).inserted {
                            guard let extra = literalWordsWithQuoting(
                                body, shellType: shellType, parsing: .deferred(mode),
                                checkedAliases: &checkedAliases
                            ) else { return nil }
                            words.append(contentsOf: extra)
                        }
                    }
                }
            }
        }
        var pieces = [node]
        if shellType == .zsh {
            let previous = node.previousNamedSibling
            if previous == nil || !hasContinuationGap(script, utf16End(previous!), utf16Start(node)) {
                var current = node
                while let next = current.nextNamedSibling,
                      hasContinuationGap(script, utf16End(current), utf16Start(next)) {
                    pieces.append(next)
                    current = next
                }
            }
        }
        let continued = pieces.count > 1
        if kind == "ansi_c_string" {
            guard let decoded = decodeAnsiC(nodeText(node, script), shellType: shellType, quoting: quoting) else {
                return nil
            }
            words.append(decoded)
            if !continued { continue }
        } else if let word = snapshotLiteralWord(node, script: script, shellType: shellType, quoting: quoting) {
            words.append(word)
            if !continued { continue }
        }
        if continued || kind == "string" || kind == "concatenation" {
            pieces.reverse()
            var literal: [UInt8] = []
            var rawStringEnd: Int?
            while let piece = pieces.popLast() {
                if let word = snapshotLiteralWordBytes(
                    piece, script: script, shellType: shellType, quoting: quoting
                ) {
                    if quoting == .zshRcQuotes,
                       piece.nodeType == "raw_string",
                       rawStringEnd == utf16Start(piece) {
                        literal.append(0x27)
                    }
                    literal.append(contentsOf: word)
                    rawStringEnd = piece.nodeType == "raw_string" ? utf16End(piece) : nil
                } else if piece.nodeType == "variable_assignment" {
                    if !literal.isEmpty {
                        words.append(String(decoding: literal, as: UTF8.self))
                        literal.removeAll()
                    }
                    if let value = piece.child(byFieldName: "value") {
                        pieces.append(value)
                    }
                } else if piece.nodeType == "string_content" {
                    let content = nodeText(piece, script)
                    guard let decoded = posixShlexSplit("\"\(content)\""), decoded.count == 1 else {
                        return nil
                    }
                    literal.append(contentsOf: Array(decoded[0].utf8))
                } else if piece.nodeType == "string"
                            || piece.nodeType == "concatenation"
                            || piece.nodeType == "command_name" {
                    if shellType == .zsh,
                       let previous = piece.previousSibling,
                       previous.nodeType == "$",
                       utf16End(previous) == utf16Start(piece) {
                        literal.append(0x24)
                    }
                    pieces.append(contentsOf: namedChildren(piece).reversed())
                } else if !literal.isEmpty {
                    words.append(String(decoding: literal, as: UTF8.self))
                    literal.removeAll()
                }
            }
            if !literal.isEmpty {
                words.append(String(decoding: literal, as: UTF8.self))
            }
        }
        pending.append(contentsOf: namedChildren(node).map { ($0, quoting) })
    }
    return words
}

private func hasContinuationGap(_ script: String, _ leftEnd: Int, _ rightStart: Int) -> Bool {
    guard let gap = utf16Slice(script, leftEnd, rightStart), !gap.isEmpty else { return false }
    return gap.replacingOccurrences(of: "\\\n", with: "").isEmpty
}

private func snapshotLiteralWord(
    _ node: Node,
    script: String,
    shellType: ShellType,
    quoting: SnapshotQuoting
) -> String? {
    snapshotLiteralWordBytes(node, script: script, shellType: shellType, quoting: quoting)
        .map { String(decoding: $0, as: UTF8.self) }
}

func snapshotLiteralWordBytes(
    _ node: Node,
    script: String,
    shellType: ShellType,
    quoting: SnapshotQuoting
) -> [UInt8]? {
    var word: [UInt8]
    switch node.nodeType {
    case "command_name":
        guard let name = node.namedChild(at: 0) else { return nil }
        guard let bytes = snapshotLiteralWordBytes(
            name, script: script, shellType: shellType, quoting: quoting
        ) else { return nil }
        word = bytes
    case "concatenation":
        var assembled: [UInt8] = []
        var rawStringEnd: Int?
        for child in namedChildren(node) {
            if quoting == .zshRcQuotes,
               child.nodeType == "raw_string",
               rawStringEnd == utf16Start(child) {
                assembled.append(0x27)
            }
            guard let piece = snapshotLiteralWordBytes(
                child, script: script, shellType: shellType, quoting: quoting
            ) else { return nil }
            assembled.append(contentsOf: piece)
            rawStringEnd = child.nodeType == "raw_string" ? utf16End(child) : nil
        }
        word = assembled
    case "ansi_c_string":
        guard let bytes = decodeAnsiCBytes(
            nodeText(node, script), shellType: shellType, quoting: quoting
        ) else { return nil }
        word = bytes
    case "word", "number", "string", "raw_string":
        if namedChildren(node).contains(where: { $0.nodeType != "string_content" }) {
            return nil
        }
        let text = nodeText(node, script)
        var context = node.parent
        while let parent = context,
              parent.nodeType == "expansion" || parent.nodeType == "concatenation" {
            context = parent.parent
        }
        let tokens: [String]
        if shellType == .zsh, node.nodeType == "word", context?.nodeType == "string" {
            guard let split = posixShlexSplit("\"\(text)\"") else { return nil }
            tokens = split
        } else {
            guard let split = posixShlexSplit(text) else { return nil }
            tokens = split
        }
        guard tokens.count == 1 else { return nil }
        word = Array(tokens[0].utf8)
    default:
        return nil
    }
    if shellType == .zsh,
       node.nodeType == "string" || node.nodeType == "concatenation",
       let previous = node.previousSibling,
       previous.nodeType == "$",
       utf16End(previous) == utf16Start(node) {
        word.insert(0x24, at: 0)
    }
    return word
}

private func decodeAnsiC(_ raw: String, shellType: ShellType, quoting: SnapshotQuoting) -> String? {
    decodeAnsiCBytes(raw, shellType: shellType, quoting: quoting)
        .map { String(decoding: $0, as: UTF8.self) }
}

private func decodeAnsiCBytes(
    _ raw: String,
    shellType: ShellType,
    quoting: SnapshotQuoting
) -> [UInt8]? {
    guard let prefixed = raw.stripPrefix("$'") else { return nil }
    let body: String
    if prefixed.hasSuffix("'") {
        body = String(prefixed.dropLast())
    } else if shellType == .bash {
        body = prefixed
    } else {
        return nil
    }
    var chars = Array(body)
    var i = 0
    var decoded: [UInt8] = []
    var modifiers = ZshByteModifiers()
    while i < chars.count {
        let character = chars[i]
        i += 1
        if character != "\\" {
            let bytes = Array(String(character).utf8)
            guard let first = bytes.first else { continue }
            decoded.append(modifiers.apply(first))
            decoded.append(contentsOf: bytes.dropFirst())
            continue
        }
        guard i < chars.count else {
            if shellType == .zsh { return nil }
            decoded.append(0x5c)
            break
        }
        let escape = chars[i]
        i += 1
        let mapped: UInt8?
        switch escape {
        case "a": mapped = 7
        case "b": mapped = 8
        case "e", "E": mapped = 27
        case "f": mapped = 12
        case "n": mapped = 0x0a
        case "r": mapped = 0x0d
        case "t": mapped = 0x09
        case "v": mapped = 11
        case "\\", "'", "\"", "?":
            mapped = escape.asciiValue
        case "c" where shellType != .zsh:
            guard i < chars.count else {
                decoded.append(0x5c)
                if quoting != .legacyBash { decoded.append(0x63) }
                return decoded
            }
            var control = chars[i]
            i += 1
            if control == "\\", quoting != .legacyBash, i < chars.count, chars[i] == "\\" {
                i += 1
            }
            let bytes = Array(String(control).utf8)
            guard let first = bytes.first else { continue }
            decoded.append(first == 0x3f ? 127 : first & 31)
            decoded.append(contentsOf: bytes.dropFirst())
            mapped = nil
        case "C" where shellType == .zsh, "M" where shellType == .zsh:
            if i < chars.count, chars[i] == "-" { i += 1 }
            if escape == "C" {
                modifiers.control = true
            } else {
                modifiers.meta = modifiers.control ? .beforeControl : .afterControl
            }
            mapped = nil
        case "0", "1", "2", "3", "4", "5", "6", "7", "x", "u", "U":
            if (escape == "u" || escape == "U"), quoting == .legacyBash {
                decoded.append(contentsOf: [0x5c, escape.asciiValue ?? 0])
                mapped = nil
                break
            }
            let radix: UInt32
            let digits: Int
            switch escape {
            case "x": radix = 16; digits = 2
            case "u": radix = 16; digits = 4
            case "U": radix = 16; digits = 8
            default: radix = 8; digits = 2
            }
            var value: UInt32 = 0
            var found = false
            if radix == 8, let digit = escape.wholeNumberValue, digit < 8 {
                value = UInt32(digit)
                found = true
            }
            for _ in 0..<digits {
                guard i < chars.count, let digit = digitValue(chars[i], radix: radix) else { break }
                i += 1
                let (product, overflow) = value.multipliedReportingOverflow(by: radix)
                if overflow { return nil }
                let (sum, addOverflow) = product.addingReportingOverflow(digit)
                if addOverflow { return nil }
                value = sum
                found = true
            }
            if !found {
                if shellType == .zsh { return nil }
                decoded.append(contentsOf: [0x5c, escape.asciiValue ?? 0])
                mapped = nil
                break
            }
            if escape == "u" || escape == "U" {
                if let scalar = UnicodeScalar(value) {
                    decoded.append(contentsOf: Array(String(Character(scalar)).utf8))
                } else {
                    if shellType == .zsh { return nil }
                    let length: Int
                    switch value {
                    case 0...0xffff: length = 3
                    case 0x10000...0x1fffff: length = 4
                    case 0x200000...0x3ffffff: length = 5
                    case 0x4000000...0x7fffffff: length = 6
                    default:
                        mapped = nil
                        continue
                    }
                    var bytes = [UInt8](repeating: 0, count: 6)
                    var remaining = value
                    for index in (1..<length).reversed() {
                        bytes[index] = 0x80 | UInt8(remaining & 0x3f)
                        remaining >>= 6
                    }
                    bytes[0] = UInt8((0xff << (8 - length)) & 0xff) | UInt8(remaining)
                    decoded.append(contentsOf: bytes[..<length])
                }
                mapped = nil
            } else {
                mapped = UInt8(truncatingIfNeeded: value)
            }
        default:
            if shellType != .zsh {
                decoded.append(0x5c)
            }
            let bytes = Array(String(escape).utf8)
            guard let first = bytes.first else { continue }
            decoded.append(modifiers.apply(first))
            decoded.append(contentsOf: bytes.dropFirst())
            mapped = nil
        }
        if let mapped {
            decoded.append(modifiers.apply(mapped))
        }
    }
    return decoded
}

private enum MetaOrder {
    case beforeControl
    case afterControl
}

private struct ZshByteModifiers {
    var control = false
    var meta: MetaOrder?

    mutating func apply(_ byte: UInt8) -> UInt8 {
        var byte = byte
        let meta = self.meta
        self.meta = nil
        if meta == .beforeControl { byte |= 0x80 }
        if control {
            control = false
            byte = byte == 0x3f ? 0x7f : byte & 0x9f
        }
        if meta == .afterControl { byte |= 0x80 }
        return byte
    }
}

private func childrenByField(_ node: Node, _ name: String) -> [Node] {
    (0..<node.childCount).compactMap { index in
        guard node.fieldNameForChild(at: index) == name else { return nil }
        return node.child(at: index)
    }
}

private func allChildren(_ node: Node) -> [Node] {
    (0..<node.childCount).compactMap { node.child(at: $0) }
}

private func namedChildren(_ node: Node) -> [Node] {
    (0..<node.namedChildCount).compactMap { node.namedChild(at: $0) }
}

private func nodeText(_ node: Node, _ src: String) -> String {
    utf16Slice(src, utf16Start(node), utf16End(node)) ?? ""
}

private func utf16Start(_ node: Node) -> Int { Int(node.byteRange.lowerBound) / 2 }
private func utf16End(_ node: Node) -> Int { Int(node.byteRange.upperBound) / 2 }
private func utf16Range(_ node: Node) -> Range<Int> { utf16Start(node)..<utf16End(node) }

func utf16Slice(_ script: String, _ start: Int, _ end: Int) -> String? {
    let units = Array(script.utf16)
    guard start >= 0, end >= start, end <= units.count else { return nil }
    return String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
}

private func zipOptional<A, B>(_ left: A?, _ right: B?) -> (A, B)? {
    guard let left, let right else { return nil }
    return (left, right)
}

private func digitValue(_ character: Character, radix: UInt32) -> UInt32? {
    guard let value = character.hexDigitValue else { return nil }
    let number = UInt32(value)
    return number < radix ? number : nil
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
