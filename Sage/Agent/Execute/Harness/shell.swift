//
//  shell.swift
//  Sage
//
//  Port of codex-rs/core/src/shell.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Wraps `CodexShellCommand` detection. `ShellInfo` from exec-server is
//  accepted as name + path until that crate is ported.
//

import CodexShellCommand
import Foundation

public struct Shell: Equatable, Sendable, Codable {
    public var shellType: ShellType
    public var shellPath: String

    public init(shellType: ShellType, shellPath: String) {
        self.shellType = shellType
        self.shellPath = shellPath
    }

    public func name() -> String { shellType.name() }

    public func deriveExecArgs(_ command: String, useLoginShell: Bool) -> [String] {
        switch shellType {
        case .zsh, .bash, .sh:
            return [shellPath, useLoginShell ? "-lc" : "-c", command]
        case .powerShell:
            var args = [shellPath]
            if !useLoginShell { args.append("-NoProfile") }
            args.append("-Command")
            args.append(command)
            return args
        case .cmd:
            return [shellPath, "/c", command]
        }
    }

    public init(_ detected: DetectedShell) {
        self.init(shellType: detected.shellType, shellPath: detected.shellPath)
    }

    public static func fromEnvironmentShellInfo(name: String, path: String) throws -> Shell {
        let shellType: ShellType
        switch name {
        case "zsh": shellType = .zsh
        case "bash": shellType = .bash
        case "powershell": shellType = .powerShell
        case "sh": shellType = .sh
        case "cmd": shellType = .cmd
        default:
            throw CodexShellLookupError.unknownEnvironmentShell(name)
        }
        return Shell(shellType: shellType, shellPath: path)
    }
}

public enum CodexShellLookupError: Error, Equatable, CustomStringConvertible {
    case unknownEnvironmentShell(String)

    public var description: String {
        switch self {
        case .unknownEnvironmentShell(let name):
            return "unknown environment shell `\(name)`"
        }
    }
}

public func getShellByModelProvidedPath(_ shellPath: String) -> Shell {
    Shell(CodexShellCommand.getShellByModelProvidedPath(shellPath))
}

public func getShell(_ shellType: ShellType) -> Shell? {
    CodexShellCommand.getShell(shellType).map(Shell.init)
}

public func defaultUserShell() -> Shell {
    Shell(CodexShellCommand.defaultUserShell())
}
