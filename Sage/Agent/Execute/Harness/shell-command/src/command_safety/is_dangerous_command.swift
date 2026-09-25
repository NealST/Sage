//
//  is_dangerous_command.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/command_safety/is_dangerous_command.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  POSIX forced-rm / sudo / env / trap classification. Windows dangerous
//  commands are consulted only when the platform is Windows.
//

public enum DangerousCommandPlatform: Equatable, Sendable {
    case posix
    case windows

    public static func host() -> DangerousCommandPlatform {
        .posix
    }
}

public enum DangerousCommandMatch: Equatable, Sendable {
    case forcedRm
    case other
}

let MAX_DANGEROUS_COMMAND_WRAPPER_DEPTH = 8

public func dangerousCommandMatch(_ command: [String]) -> DangerousCommandMatch? {
    dangerousCommandMatchForPlatform(command, DangerousCommandPlatform.host())
}

public func dangerousCommandMatchForPlatform(
    _ command: [String],
    _ platform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    dangerousCommandMatchWithDepth(command, wrapperDepth: 0, platform: platform)
}

public func dangerousPowershellWordsMatch(
    _ command: [String],
    _ platform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    if platform == .windows {
        return isDangerousPowershellWords(command) ? .other : nil
    }
    return nil
}

private func dangerousCommandMatchWithDepth(
    _ command: [String],
    wrapperDepth: Int,
    platform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    if wrapperDepth > MAX_DANGEROUS_COMMAND_WRAPPER_DEPTH {
        return .other
    }
    if let match = dangerousCommandMatchForExec(command, wrapperDepth: wrapperDepth, platform: platform) {
        return match
    }
    if let commands = parseShellLcLiteralCommands(command) {
        for nested in commands {
            if let match = dangerousCommandMatchWithDepth(
                nested,
                wrapperDepth: wrapperDepth + 1,
                platform: platform
            ) {
                return match
            }
        }
    }
    if platform == .windows && isDangerousCommandWindows(command) {
        return .other
    }
    return nil
}

private func executableNameLookupKey(_ raw: String, platform: DangerousCommandPlatform) -> String? {
    switch platform {
    case .posix:
        let name = raw.split(separator: "/").last.map(String.init)
        return name.flatMap { $0.isEmpty ? nil : $0 }
    case .windows:
        let name = raw.split { $0 == "/" || $0 == "\\" }.last.map(String.init)
        guard var name, !name.isEmpty else { return nil }
        let bytes = Array(name.utf8)
        if bytes.count >= 2, (65...90).contains(bytes[0]) || (97...122).contains(bytes[0]), bytes[1] == 58 {
            name = String(name.dropFirst(2))
        }
        let lower = name.lowercased()
        for suffix in [".exe", ".cmd", ".bat", ".com"] {
            if let stripped = lower.stripSuffix(suffix) { return stripped }
        }
        return lower.isEmpty ? nil : lower
    }
}

private func dangerousCommandMatchForExec(
    _ command: [String],
    wrapperDepth: Int,
    platform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    let cmd0 = command.first.flatMap { executableNameLookupKey($0, platform: platform) }
    switch cmd0 {
    case "rm" where rmArgsIncludeForceOption(Array(command.dropFirst())):
        return .forcedRm
    case "sudo":
        return dangerousCommandMatchWithDepth(
            Array(command.dropFirst()),
            wrapperDepth: wrapperDepth + 1,
            platform: platform
        )
    case "env":
        return dangerousCommandMatchForEnv(command, wrapperDepth: wrapperDepth, platform: platform)
    case "trap":
        return dangerousCommandMatchForTrap(command, wrapperDepth: wrapperDepth, platform: platform)
    default:
        return nil
    }
}

private func dangerousCommandMatchForEnv(
    _ command: [String],
    wrapperDepth: Int,
    platform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    var commandIndex = 1
    while commandIndex < command.count {
        let argument = command[commandIndex]
        if argument == "--" {
            commandIndex += 1
            break
        }
        if argument == "-i" || argument == "--ignore-environment"
            || argument.split(separator: "=", maxSplits: 1).count == 2
            && !argument.hasPrefix("-")
            && !argument.split(separator: "=", maxSplits: 1)[0].isEmpty {
            commandIndex += 1
            continue
        }
        break
    }
    return dangerousCommandMatchWithDepth(
        Array(command.dropFirst(commandIndex)),
        wrapperDepth: wrapperDepth + 1,
        platform: platform
    )
}

private func dangerousCommandMatchForTrap(
    _ command: [String],
    wrapperDepth: Int,
    platform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    var actionIndex = 1
    if command.indices.contains(actionIndex), command[actionIndex] == "--" {
        actionIndex += 1
    }
    guard actionIndex < command.count, !command[actionIndex].hasPrefix("-") else { return nil }
    let shellCommand = ["sh", "-c", command[actionIndex]]
    return dangerousCommandMatchWithDepth(shellCommand, wrapperDepth: wrapperDepth + 1, platform: platform)
}

private func rmArgsIncludeForceOption(_ args: [String]) -> Bool {
    args.prefix(while: { $0 != "--" }).contains { arg in
        arg == "--force"
            || (arg.hasPrefix("-") && !arg.hasPrefix("--") && arg.contains("f"))
    }
}

private extension String {
    func stripSuffix(_ suffix: String) -> String? {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : nil
    }
}
