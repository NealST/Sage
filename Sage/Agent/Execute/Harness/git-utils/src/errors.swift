//
//  errors.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/errors.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `walkdir::Error` is folded into `io`. `ExitStatus` is an `Int32` exit
//  code. UTF-8 failures carry the command string without a nested
//  `FromUtf8Error`.
//

import Foundation

/// Errors returned while managing git worktree snapshots.
public enum GitToolingError: Error, Equatable {
    case gitCommand(command: String, status: Int32, stderr: String)
    case gitOutputUtf8(command: String)
    case notAGitRepository(path: String)
    case nonRelativePath(path: String)
    case pathEscapesRepository(path: String)
    case pathPrefix(String)
    case io(String)

    public var localizedDescription: String {
        switch self {
        case .gitCommand(let command, let status, let stderr):
            return "git command `\(command)` failed with status \(status): \(stderr)"
        case .gitOutputUtf8(let command):
            return "git command `\(command)` produced non-UTF-8 output"
        case .notAGitRepository(let path):
            return "\"\(path)\" is not a git repository"
        case .nonRelativePath(let path):
            return "path \"\(path)\" must be relative to the repository root"
        case .pathEscapesRepository(let path):
            return "path \"\(path)\" escapes the repository root"
        case .pathPrefix(let message):
            return message
        case .io(let message):
            return message
        }
    }
}
