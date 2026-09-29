//
//  parse_command.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/parse_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Public API and summarizer (head/cat/rg/find/git/cwd tracking, sed -n
//  reads, pipeline formatting helpers) match upstream. `PathBuf` is
//  `String`. `shlex` is the local POSIX splitter.
//

import CodexProtocol
import Foundation

public func shlexJoin(_ tokens: [String]) -> String {
    if tokens.contains(where: { $0.contains("\0") }) {
        return "<command included NUL byte>"
    }
    return tokens.map(posixShlexQuote).joined(separator: " ")
}

/// Tokenizes a PowerShell command while preserving Windows paths and reader aliases.
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

public func parseCommandImpl(_ command: [String]) -> [ParsedCommand] {
    if let commands = parseShellLcCommands(command) {
        return commands
    }

    var powershellCommand: [String]?
    if let shell = command.first, shell.contains("\\") {
        var normalized = command
        normalized[0] = (shell as NSString).lastPathComponent
        powershellCommand = normalized
    }
    if let (_, script) = extractPowershellCommand(powershellCommand ?? command) {
        let tokens = tokenizePowershellCommand(script)
        if tokens.first == "Get-Content" {
            let nested = parseCommandImpl(tokens)
            if nested.count == 1, case .read(_, let name, let path) = nested[0] {
                return [.read(cmd: script, name: name, path: path)]
            }
        }
        return [.unknown(cmd: script)]
    }

    let normalized = normalizeTokens(command)
    let parts = containsConnectors(normalized) ? splitOnConnectors(normalized) : [normalized]

    var commands: [ParsedCommand] = []
    var cwd: String?
    for tokens in parts {
        if let head = tokens.first, head == "cd" {
            let tail = Array(tokens.dropFirst())
            if let dir = cdTarget(tail) {
                cwd = cwd.map { joinPaths($0, dir) } ?? dir
            }
            continue
        }
        let parsed = summarizeMainTokens(tokens)
        if case .read(let cmd, let name, let path) = parsed, let base = cwd {
            commands.append(.read(cmd: cmd, name: name, path: joinPaths(base, path)))
        } else {
            commands.append(parsed)
        }
    }

    while let next = simplifyOnce(commands) {
        commands = next
    }
    return commands
}

private func simplifyOnce(_ commands: [ParsedCommand]) -> [ParsedCommand]? {
    if commands.count <= 1 { return nil }

    if case .unknown(let cmd) = commands[0],
       let tokens = posixShlexSplit(cmd),
       tokens.first == "echo" {
        return Array(commands.dropFirst())
    }

    if let idx = commands.firstIndex(where: { pc in
        if case .unknown(let cmd) = pc,
           let tokens = posixShlexSplit(cmd),
           tokens.first == "cd" {
            return true
        }
        return false
    }), commands.count > idx + 1 {
        var out = Array(commands[..<idx])
        out.append(contentsOf: commands[(idx + 1)...])
        return out
    }

    if let idx = commands.firstIndex(where: { pc in
        if case .unknown(let cmd) = pc { return cmd == "true" }
        return false
    }) {
        var out = Array(commands[..<idx])
        out.append(contentsOf: commands[(idx + 1)...])
        return out
    }

    if let idx = commands.firstIndex(where: { pc in
        if case .unknown(let cmd) = pc, let tokens = posixShlexSplit(cmd) {
            return tokens.first == "nl" && tokens.dropFirst().allSatisfy { $0.hasPrefix("-") }
        }
        return false
    }) {
        var out = Array(commands[..<idx])
        out.append(contentsOf: commands[(idx + 1)...])
        return out
    }

    return nil
}

private func isValidSedNArg(_ arg: String?) -> Bool {
    guard let s = arg, s.hasSuffix("p") else { return false }
    let core = String(s.dropLast())
    let parts = core.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 1:
        return !parts[0].isEmpty && parts[0].isAsciiDigits
    case 2:
        return !parts[0].isEmpty && !parts[1].isEmpty
            && parts[0].isAsciiDigits && parts[1].isAsciiDigits
    default:
        return false
    }
}

private func sedReadPath(_ args: [String]) -> String? {
    let argsNoConnector = trimAtConnector(args)
    if sedHasInPlaceFlag(argsNoConnector) || !argsNoConnector.contains("-n") {
        return nil
    }
    var hasRangeScript = false
    var i = 0
    while i < argsNoConnector.count {
        let arg = argsNoConnector[i]
        if arg == "-e" || arg == "--expression" {
            if isValidSedNArg(argsNoConnector.dropFirst(i + 1).first) {
                hasRangeScript = true
            }
            i += 2
            continue
        }
        if arg == "-f" || arg == "--file" {
            i += 2
            continue
        }
        i += 1
    }
    if !hasRangeScript {
        hasRangeScript = argsNoConnector.contains { !$0.hasPrefix("-") && isValidSedNArg($0) }
    }
    if !hasRangeScript { return nil }
    let candidates = skipFlagValues(argsNoConnector, ["-e", "-f", "--expression", "--file"])
    let nonFlags = candidates.filter { !$0.hasPrefix("-") }
    guard let first = nonFlags.first else { return nil }
    if isValidSedNArg(first) {
        return nonFlags.dropFirst().first
    }
    return first
}

private func normalizeTokens(_ cmd: [String]) -> [String] {
    if cmd.count >= 2 {
        let first = cmd[0]
        let pipe = cmd[1]
        if (first == "yes" || first == "y") && pipe == "|" {
            return Array(cmd.dropFirst(2))
        }
        if (first == "no" || first == "n") && pipe == "|" {
            return Array(cmd.dropFirst(2))
        }
    }
    if cmd.count == 3 {
        let shell = cmd[0]
        let flag = cmd[1]
        let script = cmd[2]
        if (shell == "bash" || shell == "zsh") && (flag == "-c" || flag == "-lc") {
            return posixShlexSplit(script) ?? [shell, flag, script]
        }
    }
    return cmd
}

private func containsConnectors(_ tokens: [String]) -> Bool {
    tokens.contains { $0 == "&&" || $0 == "||" || $0 == "|" || $0 == ";" }
}

private func splitOnConnectors(_ tokens: [String]) -> [[String]] {
    var out: [[String]] = []
    var cur: [String] = []
    for token in tokens {
        if token == "&&" || token == "||" || token == "|" || token == ";" {
            if !cur.isEmpty {
                out.append(cur)
                cur = []
            }
        } else {
            cur.append(token)
        }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

private func trimAtConnector(_ tokens: [String]) -> [String] {
    let idx = tokens.firstIndex(where: { $0 == "|" || $0 == "&&" || $0 == "||" || $0 == ";" })
        ?? tokens.endIndex
    return Array(tokens[..<idx])
}

private func shortDisplayPath(_ path: String) -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    var trimmed = normalized
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let skip = Set(["build", "dist", "node_modules", "src"])
    let parts = components.reversed().filter { !$0.isEmpty && !skip.contains($0) }
    return parts.first ?? trimmed
}

private func skipFlagValues(_ args: [String], _ flagsWithVals: [String]) -> [String] {
    var out: [String] = []
    var skipNext = false
    for (i, arg) in args.enumerated() {
        if skipNext {
            skipNext = false
            continue
        }
        if arg == "--" {
            out.append(contentsOf: args.dropFirst(i + 1))
            break
        }
        if arg.hasPrefix("--"), arg.contains("=") { continue }
        if flagsWithVals.contains(arg) {
            if i + 1 < args.count { skipNext = true }
            continue
        }
        out.append(arg)
    }
    return out
}

private func firstNonFlagOperand(_ args: [String], _ flagsWithVals: [String]) -> String? {
    positionalOperands(args, flagsWithVals).first
}

private func singleNonFlagOperand(_ args: [String], _ flagsWithVals: [String]) -> String? {
    let operands = positionalOperands(args, flagsWithVals)
    guard operands.count == 1 else { return nil }
    return operands[0]
}

private func positionalOperands(_ args: [String], _ flagsWithVals: [String]) -> [String] {
    var out: [String] = []
    var afterDoubleDash = false
    var skipNext = false
    for (i, arg) in args.enumerated() {
        if skipNext {
            skipNext = false
            continue
        }
        if afterDoubleDash {
            out.append(arg)
            continue
        }
        if arg == "--" {
            afterDoubleDash = true
            continue
        }
        if arg.hasPrefix("--"), arg.contains("=") { continue }
        if flagsWithVals.contains(arg) {
            if i + 1 < args.count { skipNext = true }
            continue
        }
        if arg.hasPrefix("-") { continue }
        out.append(arg)
    }
    return out
}

private func parseGrepLike(_ mainCmd: [String], _ args: [String]) -> ParsedCommand {
    let argsNoConnector = trimAtConnector(args)
    var operands: [String] = []
    var pattern: String?
    var afterDoubleDash = false
    var i = 0
    while i < argsNoConnector.count {
        let arg = argsNoConnector[i]
        i += 1
        if afterDoubleDash {
            operands.append(arg)
            continue
        }
        if arg == "--" {
            afterDoubleDash = true
            continue
        }
        switch arg {
        case "-e", "--regexp":
            if pattern == nil, i < argsNoConnector.count {
                pattern = argsNoConnector[i]
            }
            if i < argsNoConnector.count { i += 1 }
            continue
        case "-f", "--file":
            if pattern == nil, i < argsNoConnector.count {
                pattern = argsNoConnector[i]
            }
            if i < argsNoConnector.count { i += 1 }
            continue
        case "-m", "--max-count", "-C", "--context", "-A", "--after-context",
             "-B", "--before-context":
            if i < argsNoConnector.count { i += 1 }
            continue
        default:
            break
        }
        if arg.hasPrefix("-") { continue }
        operands.append(arg)
    }
    let hasPattern = pattern != nil
    let query = pattern ?? operands.first
    let pathIndex = hasPattern ? 0 : 1
    let path = pathIndex < operands.count ? shortDisplayPath(operands[pathIndex]) : nil
    return .search(cmd: shlexJoin(mainCmd), query: query, path: path)
}

private func awkDataFileOperand(_ args: [String]) -> String? {
    if args.isEmpty { return nil }
    let argsNoConnector = trimAtConnector(args)
    let hasScriptFile = argsNoConnector.contains { $0 == "-f" || $0 == "--file" }
    let candidates = skipFlagValues(
        argsNoConnector,
        ["-F", "-v", "-f", "--field-separator", "--assign", "--file"])
    let nonFlags = candidates.filter { !$0.hasPrefix("-") }
    if hasScriptFile { return nonFlags.first }
    if nonFlags.count >= 2 { return nonFlags[1] }
    return nil
}

private func pythonWalksFiles(_ args: [String]) -> Bool {
    let argsNoConnector = trimAtConnector(args)
    var i = 0
    while i < argsNoConnector.count {
        let arg = argsNoConnector[i]
        i += 1
        if arg == "-c", i < argsNoConnector.count {
            let script = argsNoConnector[i]
            return script.contains("os.walk")
                || script.contains("os.listdir")
                || script.contains("os.scandir")
                || script.contains("glob.glob")
                || script.contains("glob.iglob")
                || script.contains("pathlib.Path")
                || script.contains(".rglob(")
        }
    }
    return false
}

private func isPythonCommand(_ cmd: String) -> Bool {
    cmd == "python" || cmd == "python2" || cmd == "python3"
        || cmd.hasPrefix("python2.") || cmd.hasPrefix("python3.")
}

private func cdTarget(_ args: [String]) -> String? {
    if args.isEmpty { return nil }
    var i = 0
    var target: String?
    while i < args.count {
        let arg = args[i]
        if arg == "--" {
            return args.dropFirst(i + 1).first
        }
        if arg == "-L" || arg == "-P" || arg.hasPrefix("-") {
            i += 1
            continue
        }
        target = arg
        i += 1
    }
    return target
}

/// Returns whether a command token has an explicit path shape.
public func isPathish(_ s: String) -> Bool {
    s == "." || s == ".." || s.hasPrefix("./") || s.hasPrefix("../")
        || s.contains("/") || s.contains("\\")
}

private func parseFdQueryAndPath(_ tail: [String]) -> (query: String?, path: String?) {
    let argsNoConnector = trimAtConnector(tail)
    let candidates = skipFlagValues(
        argsNoConnector,
        ["-t", "--type", "-e", "--extension", "-E", "--exclude", "--search-path"])
    let nonFlags = candidates.filter { !$0.hasPrefix("-") }
    switch nonFlags.count {
    case 1:
        let one = nonFlags[0]
        if isPathish(one) { return (nil, shortDisplayPath(one)) }
        return (one, nil)
    case let n where n >= 2:
        return (nonFlags[0], shortDisplayPath(nonFlags[1]))
    default:
        return (nil, nil)
    }
}

private func parseFindQueryAndPath(_ tail: [String]) -> (query: String?, path: String?) {
    let argsNoConnector = trimAtConnector(tail)
    var path: String?
    for arg in argsNoConnector {
        if !arg.hasPrefix("-") && arg != "!" && arg != "(" && arg != ")" {
            path = shortDisplayPath(arg)
            break
        }
    }
    var query: String?
    var i = 0
    while i < argsNoConnector.count {
        let arg = argsNoConnector[i]
        if arg == "-name" || arg == "-iname" || arg == "-path" || arg == "-regex" {
            if i + 1 < argsNoConnector.count {
                query = argsNoConnector[i + 1]
            }
            break
        }
        i += 1
    }
    return (query, path)
}

private func parseShellLcCommands(_ original: [String]) -> [ParsedCommand]? {
    guard let (_, script) = extractBashCommand(original) else { return nil }
    return parseShellScript(script)
}

/// Parses command metadata from a Bash-compatible shell script.
public func parseShellScript(_ script: String) -> [ParsedCommand] {
    if let tree = tryParseShell(script),
       let allCommands = tryParseWordOnlyCommandsSequence(tree, src: script),
       !allCommands.isEmpty {
        let scriptTokens = posixShlexSplit(script) ?? [script]
        let hadMultipleCommands = allCommands.count > 1
        let filteredCommands = dropSmallFormattingCommands(allCommands)
        if filteredCommands.isEmpty {
            return [.unknown(cmd: script)]
        }
        var commands: [ParsedCommand] = []
        var cwd: String?
        for tokens in filteredCommands {
            if let head = tokens.first, head == "cd" {
                let tail = Array(tokens.dropFirst())
                if let dir = cdTarget(tail) {
                    cwd = cwd.map { joinPaths($0, dir) } ?? dir
                }
                continue
            }
            let parsed = summarizeMainTokens(tokens)
            if case .read(let cmd, let name, let path) = parsed, let base = cwd {
                commands.append(.read(cmd: cmd, name: name, path: joinPaths(base, path)))
            } else {
                commands.append(parsed)
            }
        }
        if commands.count > 1 {
            commands.removeAll { pc in
                if case .unknown(let cmd) = pc { return cmd == "true" }
                return false
            }
            while let next = simplifyOnce(commands) {
                commands = next
            }
        }
        if commands.count == 1 {
            let hadConnectors = hadMultipleCommands
                || scriptTokens.contains { $0 == "|" || $0 == "&&" || $0 == "||" || $0 == ";" }
            commands = commands.map { pc in
                switch pc {
                case .read(let cmd, let name, let path):
                    if hadConnectors {
                        let hasPipe = scriptTokens.contains("|")
                        let hasSedN = zip(scriptTokens, scriptTokens.dropFirst()).contains {
                            $0.0 == "sed" && $0.1 == "-n"
                        }
                        if hasPipe && hasSedN {
                            return .read(cmd: script, name: name, path: path)
                        }
                        return .read(cmd: cmd, name: name, path: path)
                    }
                    return .read(cmd: shlexJoin(scriptTokens), name: name, path: path)
                case .listFiles(let cmd, let path):
                    if hadConnectors { return .listFiles(cmd: cmd, path: path) }
                    return .listFiles(cmd: shlexJoin(scriptTokens), path: path)
                case .search(let cmd, let query, let path):
                    if hadConnectors { return .search(cmd: cmd, query: query, path: path) }
                    return .search(cmd: shlexJoin(scriptTokens), query: query, path: path)
                default:
                    return pc
                }
            }
        }
        return commands
    }
    return [.unknown(cmd: script)]
}

private func isSmallFormattingCommand(_ tokens: [String]) -> Bool {
    guard let cmd = tokens.first else { return false }
    switch cmd {
    case "wc", "tr", "cut", "sort", "uniq", "tee", "column", "yes", "printf":
        return true
    case "xargs":
        return !isMutatingXargsCommand(tokens)
    case "awk":
        return awkDataFileOperand(Array(tokens.dropFirst())) == nil
    case "head":
        switch tokens.count {
        case 1: return true
        case 2: return tokens[1].hasPrefix("-")
        case 3:
            let flag = tokens[1]
            let count = tokens[2]
            return (flag == "-n" || flag == "-c") && count.isAsciiDigits
        default:
            return false
        }
    case "tail":
        switch tokens.count {
        case 1: return true
        case 2: return tokens[1].hasPrefix("-")
        case 3:
            let flag = tokens[1]
            let count = tokens[2]
            if flag == "-n" || flag == "-c" {
                let s = count.hasPrefix("+") ? String(count.dropFirst()) : count
                return !s.isEmpty && s.isAsciiDigits
            }
            return false
        default:
            return false
        }
    case "sed":
        let args = Array(tokens.dropFirst())
        return !sedHasInPlaceFlag(args) && sedReadPath(args) == nil
    default:
        return false
    }
}

private func isMutatingXargsCommand(_ tokens: [String]) -> Bool {
    guard let sub = xargsSubcommand(tokens) else { return false }
    return xargsIsMutatingSubcommand(sub)
}

private func xargsSubcommand(_ tokens: [String]) -> [String]? {
    guard tokens.first == "xargs" else { return nil }
    var i = 1
    while i < tokens.count {
        let token = tokens[i]
        if token == "--" {
            let rest = Array(tokens.dropFirst(i + 1))
            return rest.isEmpty ? nil : rest
        }
        if !token.hasPrefix("-") {
            let rest = Array(tokens.dropFirst(i))
            return rest.isEmpty ? nil : rest
        }
        let takesValue = ["-E", "-e", "-I", "-L", "-n", "-P", "-s"].contains(token) && token.count == 2
        i += takesValue ? 2 : 1
    }
    return nil
}

private func xargsIsMutatingSubcommand(_ tokens: [String]) -> Bool {
    guard let head = tokens.first else { return false }
    let tail = Array(tokens.dropFirst())
    switch head {
    case "perl", "ruby": return hasInPlaceFlag(tail)
    case "sed": return sedHasInPlaceFlag(tail)
    case "rg": return tail.contains("--replace")
    default: return false
    }
}

private func hasInPlaceFlag(_ tokens: [String]) -> Bool {
    tokens.contains { token in
        token == "-i" || token.hasPrefix("-i")
            || token == "-pi" || token.hasPrefix("-pi")
            || token == "--in-place" || token.hasPrefix("--in-place=")
    }
}

private func sedHasInPlaceFlag(_ tokens: [String]) -> Bool {
    var i = 0
    while i < tokens.count {
        let token = tokens[i]
        i += 1
        switch token {
        case "--":
            return false
        case "-e", "-f", "--expression", "--file":
            i += 1
        case "--in-place":
            return true
        default:
            if token.hasPrefix("--in-place=") { return true }
            if token.hasPrefix("--") { continue }
            guard token.hasPrefix("-") else { continue }
            let shortOptions = String(token.dropFirst())
            var index = shortOptions.startIndex
            while index < shortOptions.endIndex {
                let option = shortOptions[index]
                switch option {
                case "i":
                    return true
                case "e", "f":
                    if shortOptions.index(after: index) == shortOptions.endIndex {
                        i += 1
                    }
                    index = shortOptions.endIndex
                    continue
                default:
                    break
                }
                index = shortOptions.index(after: index)
            }
        }
    }
    return false
}

private func dropSmallFormattingCommands(_ commands: [[String]]) -> [[String]] {
    commands.filter { !isSmallFormattingCommand($0) }
}

private func summarizeMainTokens(_ mainCmd: [String]) -> ParsedCommand {
    guard let head = mainCmd.first else {
        return .unknown(cmd: shlexJoin(mainCmd))
    }
    let tail = Array(mainCmd.dropFirst())
    switch head {
    case "ls", "eza", "exa":
        let flagsWithVals: [String]
        switch head {
        case "ls":
            flagsWithVals = [
                "-I", "-w", "--block-size", "--format", "--time-style", "--color",
                "--quoting-style",
            ]
        case "eza", "exa":
            flagsWithVals = [
                "-I", "--ignore-glob", "--color", "--sort", "--time-style", "--time",
            ]
        default:
            flagsWithVals = []
        }
        let path = firstNonFlagOperand(tail, flagsWithVals).map(shortDisplayPath)
        return .listFiles(cmd: shlexJoin(mainCmd), path: path)
    case "tree":
        let path = firstNonFlagOperand(
            tail, ["-L", "-P", "-I", "--charset", "--filelimit", "--sort"]
        ).map(shortDisplayPath)
        return .listFiles(cmd: shlexJoin(mainCmd), path: path)
    case "du":
        let path = firstNonFlagOperand(
            tail,
            ["-d", "--max-depth", "-B", "--block-size", "--exclude", "--time-style"]
        ).map(shortDisplayPath)
        return .listFiles(cmd: shlexJoin(mainCmd), path: path)
    case "rg", "rga", "ripgrep-all":
        let argsNoConnector = trimAtConnector(tail)
        let hasFilesFlag = argsNoConnector.contains("--files")
        let candidates = skipFlagValues(
            argsNoConnector,
            [
                "-g", "--glob", "--iglob", "-t", "--type", "--type-add", "--type-not",
                "-m", "--max-count", "-A", "-B", "-C", "--context", "--max-depth",
            ])
        let nonFlags = candidates.filter { !$0.hasPrefix("-") }
        if hasFilesFlag {
            return .listFiles(cmd: shlexJoin(mainCmd), path: nonFlags.first.map(shortDisplayPath))
        }
        return .search(
            cmd: shlexJoin(mainCmd),
            query: nonFlags.first,
            path: nonFlags.dropFirst().first.map(shortDisplayPath))
    case "git":
        if let subcmd = tail.first {
            let subTail = Array(tail.dropFirst())
            if subcmd == "grep" { return parseGrepLike(mainCmd, subTail) }
            if subcmd == "ls-files" {
                let path = firstNonFlagOperand(
                    subTail, ["--exclude", "--exclude-from", "--pathspec-from-file"]
                ).map(shortDisplayPath)
                return .listFiles(cmd: shlexJoin(mainCmd), path: path)
            }
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "fd":
        let (query, path) = parseFdQueryAndPath(tail)
        if query != nil {
            return .search(cmd: shlexJoin(mainCmd), query: query, path: path)
        }
        return .listFiles(cmd: shlexJoin(mainCmd), path: path)
    case "find":
        let (query, path) = parseFindQueryAndPath(tail)
        if query != nil {
            return .search(cmd: shlexJoin(mainCmd), query: query, path: path)
        }
        return .listFiles(cmd: shlexJoin(mainCmd), path: path)
    case "grep", "egrep", "fgrep":
        return parseGrepLike(mainCmd, tail)
    case "ag", "ack", "pt":
        let argsNoConnector = trimAtConnector(tail)
        let candidates = skipFlagValues(
            argsNoConnector,
            ["-G", "-g", "--file-search-regex", "--ignore-dir", "--ignore-file", "--path-to-ignore"])
        let nonFlags = candidates.filter { !$0.hasPrefix("-") }
        return .search(
            cmd: shlexJoin(mainCmd),
            query: nonFlags.first,
            path: nonFlags.dropFirst().first.map(shortDisplayPath))
    case "cat":
        if let path = singleNonFlagOperand(tail, []) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    default:
        break
    }

    if head.compare("Get-Content", options: .caseInsensitive) == .orderedSame {
        let conservative = tail.allSatisfy { argument in
            !argument.hasPrefix("-")
                || ["-Raw", "-Path", "-LiteralPath"].contains {
                    argument.compare($0, options: .caseInsensitive) == .orderedSame
                }
        }
        let path = conservative ? singleNonFlagOperand(tail, []) : nil
        if let path,
           !path.isEmpty,
           !path.hasPrefix("-"),
           path.allSatisfy({
               $0.isLetter || $0.isNumber
                   || $0 == " " || $0 == "/" || $0 == "\\" || $0 == "."
                   || $0 == "-" || $0 == "_" || $0 == ":"
           }) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    }

    switch head {
    case "bat", "batcat":
        if let path = singleNonFlagOperand(
            tail,
            ["--theme", "--language", "--style", "--terminal-width", "--tabs",
             "--line-range", "--map-syntax"]) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "less":
        if let path = singleNonFlagOperand(
            tail,
            ["-p", "-P", "-x", "-y", "-z", "-j", "--pattern", "--prompt",
             "--tabs", "--shift", "--jump-target"]) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "more":
        if let path = singleNonFlagOperand(tail, []) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "head":
        let hasValidN: Bool
        if let first = tail.first {
            if first == "-n" {
                hasValidN = tail.dropFirst().first?.isAsciiDigits == true
            } else if first.hasPrefix("-n") {
                hasValidN = String(first.dropFirst(2)).isAsciiDigits
            } else {
                hasValidN = false
            }
        } else {
            hasValidN = false
        }
        if hasValidN {
            var candidates: [String] = []
            var i = 0
            while i < tail.count {
                if i == 0, tail[i] == "-n", i + 1 < tail.count, tail[i + 1].isAsciiDigits {
                    i += 2
                    continue
                }
                candidates.append(tail[i])
                i += 1
            }
            if let path = candidates.first(where: { !$0.hasPrefix("-") }) {
                return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
            }
        }
        if tail.count == 1, !tail[0].hasPrefix("-") {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(tail[0]), path: tail[0])
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "tail":
        func isTailCount(_ value: String) -> Bool {
            let s = value.hasPrefix("+") ? String(value.dropFirst()) : value
            return !s.isEmpty && s.isAsciiDigits
        }
        let hasValidN: Bool
        if let first = tail.first {
            if first == "-n" {
                hasValidN = tail.dropFirst().first.map(isTailCount) == true
            } else if first.hasPrefix("-n") {
                hasValidN = isTailCount(String(first.dropFirst(2)))
            } else {
                hasValidN = false
            }
        } else {
            hasValidN = false
        }
        if hasValidN {
            var candidates: [String] = []
            var i = 0
            while i < tail.count {
                if i == 0, tail[i] == "-n", i + 1 < tail.count, isTailCount(tail[i + 1]) {
                    i += 2
                    continue
                }
                candidates.append(tail[i])
                i += 1
            }
            if let path = candidates.first(where: { !$0.hasPrefix("-") }) {
                return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
            }
        }
        if tail.count == 1, !tail[0].hasPrefix("-") {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(tail[0]), path: tail[0])
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "awk":
        if let path = awkDataFileOperand(tail) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "nl":
        let candidates = skipFlagValues(tail, ["-s", "-w", "-v", "-i", "-b"])
        if let path = candidates.first(where: { !$0.hasPrefix("-") }) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    case "sed":
        if let path = sedReadPath(tail) {
            return .read(cmd: shlexJoin(mainCmd), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    default:
        if isPythonCommand(head) {
            if pythonWalksFiles(tail) {
                return .listFiles(cmd: shlexJoin(mainCmd), path: nil)
            }
            return .unknown(cmd: shlexJoin(mainCmd))
        }
        return .unknown(cmd: shlexJoin(mainCmd))
    }
}

private func isAbsLike(_ path: String) -> Bool {
    if path.hasPrefix("/") { return true }
    let chars = Array(path)
    if chars.count >= 3,
       chars[0].isASCII, chars[0].isLetter,
       chars[1] == ":",
       chars[2] == "\\" {
        return true
    }
    if chars.count >= 2, chars[0] == "\\", chars[1] == "\\" {
        return true
    }
    return false
}

private func joinPaths(_ base: String, _ rel: String) -> String {
    if isAbsLike(rel) { return rel }
    if base.isEmpty { return rel }
    return (base as NSString).appendingPathComponent(rel)
}

private func posixShlexQuote(_ token: String) -> String {
    if token.isEmpty { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./-_"))
    if token.unicodeScalars.allSatisfy({ safe.contains($0) }) { return token }
    return "'" + token.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

public func posixShlexSplit(_ input: String) -> [String]? {
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

private extension String {
    var isAsciiDigits: Bool {
        !isEmpty && allSatisfy { $0.isASCII && $0.isNumber }
    }
}
