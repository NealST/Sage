//
//  standalone_executable.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/standalone_executable.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upstream is the argv/stdin entry for a standalone `apply_patch` binary
//  (`tokio` runtime + `codex_exec_server::LOCAL_FS`). Sage applies patches
//  in-process via `ApplyPatchRuntime`; this file keeps the argument-parsing
//  and exit-code contract so callers can invoke the same CLI shape without
//  spawning a second executable.
//

import Foundation

/// Exit codes match upstream `run_main`.
public enum ApplyPatchStandaloneExit {
    public static let success: Int32 = 0
    public static let error: Int32 = 1
    public static let usage: Int32 = 2
}

/// Parse a standalone `apply_patch` invocation.
///
/// - One UTF-8 positional argument is the patch payload.
/// - No argument means the caller should read stdin (this helper does not
///   touch stdin itself — return `.readStdin`).
/// - Extra arguments are usage errors.
public enum ApplyPatchStandaloneInput: Equatable, Sendable {
    case patch(String)
    case readStdin
    case failed(message: String, exitCode: Int32)
}

public func parseApplyPatchStandaloneArguments(_ arguments: [String]) -> ApplyPatchStandaloneInput {
    // `arguments` is argv without argv0, matching rust after `args.next()`.
    switch arguments.count {
    case 0:
        return .readStdin
    case 1:
        return .patch(arguments[0])
    default:
        return .failed(
            message: "Error: apply_patch accepts exactly one argument.",
            exitCode: ApplyPatchStandaloneExit.usage
        )
    }
}

/// Resolve stdin contents for the no-argument form. Empty stdin is a usage error.
public func applyPatchStandalonePatchFromStdin(_ text: String) -> ApplyPatchStandaloneInput {
    if text.isEmpty {
        return .failed(
            message: "Usage: apply_patch 'PATCH'\n       echo 'PATCH' | apply_patch",
            exitCode: ApplyPatchStandaloneExit.usage
        )
    }
    return .patch(text)
}
