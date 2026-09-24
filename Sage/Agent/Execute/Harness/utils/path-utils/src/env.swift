//
//  env.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-utils/src/env.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  The Linux branch is `cfg(target_os = "linux")`-gated upstream; it is kept
//  under `#if os(Linux)` so the macOS build always returns false, exactly
//  like upstream's `cfg(not(target_os = "linux"))` branch.
//

import Foundation

/// Returns true if the current process is running under Windows Subsystem for
/// Linux.
public func isWsl() -> Bool {
    #if os(Linux)
        if ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"] != nil {
            return true
        }
        guard let version = try? String(contentsOfFile: "/proc/version", encoding: .utf8) else {
            return false
        }
        return version.lowercased().contains("microsoft")
    #else
        return false
    #endif
}
