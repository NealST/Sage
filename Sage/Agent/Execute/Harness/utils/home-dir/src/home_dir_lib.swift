//
//  home_dir_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/home-dir/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `dirs::home_dir` maps to `AbsolutePathBufGuard.homeDirectory()` ($HOME ??
//  NSHomeDirectory, same mapping as absolute-path). `fs::metadata` maps to
//  `FileManager.attributesOfItem` (follows symlinks, like `fs::metadata`).
//  `path.canonicalize()` maps to `realpathString` (absolute-path's
//  `fs::canonicalize` stand-in). `{val:?}` maps to a Rust-debug-style quoted
//  string.
//
//  R4a: upstream `lib.rs` maps to `home_dir_lib.swift` because
//  `utils/absolute-path/src/lib.swift` claimed the basename first (plan §5.1).
//

import Foundation

/// Returns the path to the Codex configuration directory, which can be
/// specified by the `CODEX_HOME` environment variable. If not set, defaults to
/// `~/.codex`.
///
/// - If `CODEX_HOME` is set, the value must exist and be a directory. The
///   value will be canonicalized and this function will throw otherwise.
/// - If `CODEX_HOME` is not set, this function does not verify that the
///   directory exists.
public func findCodexHome() throws -> AbsolutePathBuf {
    let codexHomeEnv = ProcessInfo.processInfo.environment["CODEX_HOME"]
        .flatMap { $0.isEmpty ? nil : $0 }
    return try findCodexHomeFromEnv(codexHomeEnv)
}

/// `{val:?}` — Rust's debug formatting of a string literal.
private func rustDebugQuoted(_ value: String) -> String {
    var out = "\""
    for ch in value {
        switch ch {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default: out.append(ch)
        }
    }
    out += "\""
    return out
}

func findCodexHomeFromEnv(_ codexHomeEnv: String?) throws -> AbsolutePathBuf {
    // Honor the `CODEX_HOME` environment variable when it is set to allow
    // users (and tests) to override the default location.
    switch codexHomeEnv {
    case .some(let val):
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: val)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError {
                throw IOError.notFound(
                    "CODEX_HOME points to \(rustDebugQuoted(val)), but that path does not exist"
                )
            }
            let kind: IOError.Kind =
                error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
                ? .permissionDenied : .other
            throw IOError(
                kind: kind,
                "failed to read CODEX_HOME \(rustDebugQuoted(val)): \(error)"
            )
        }

        guard let type = attributes[.type] as? FileAttributeType, type == .typeDirectory else {
            throw IOError.invalidInput(
                "CODEX_HOME points to \(rustDebugQuoted(val)), but that path is not a directory"
            )
        }
        do {
            let canonical = try realpathString(val)
            return try AbsolutePathBuf.fromAbsolutePath(canonical)
        } catch let error as IOError {
            throw IOError(
                kind: error.kind,
                "failed to canonicalize CODEX_HOME \(rustDebugQuoted(val)): \(error)"
            )
        }
    case .none:
        guard let home = AbsolutePathBufGuard.homeDirectory() else {
            throw IOError.notFound("Could not find home directory")
        }
        return try AbsolutePathBuf.fromAbsolutePath(home + "/.codex")
    }
}
