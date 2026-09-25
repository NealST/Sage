//
//  fsmonitor.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/fsmonitor.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

/// The safe `core.fsmonitor` override for an internal Git command.
public enum FsmonitorOverride: Equatable, Sendable {
    /// Disable repository-selected filesystem monitor helpers.
    case disabled
    /// Preserve Git's built-in filesystem monitor daemon.
    case builtIn

    /// Returns the complete Git configuration override.
    public var gitConfigArg: String {
        switch self {
        case .disabled: return "core.fsmonitor=false"
        case .builtIn: return "core.fsmonitor=true"
        }
    }
}

/// Executes the Git commands required by `detectFsmonitorOverride`.
///
/// Implementations must return stdout only when Git exits successfully.
/// Timeouts, spawn or transport failures, signal termination, and nonzero exit
/// statuses must return `nil`.
public protocol FsmonitorProbeRunner: Sendable {
    /// Runs one bounded probe in the target repository.
    mutating func runProbe(_ args: [String]) async -> [UInt8]?
}

/// Returns the safe filesystem monitor override for the target repository.
///
/// This intentionally probes every time. Effective Git configuration is
/// layered, may use conditional includes, and can change while Codex is
/// running.
public func detectFsmonitorOverride<Runner: FsmonitorProbeRunner>(
    _ runner: inout Runner
) async -> FsmonitorOverride {
    guard let configBytes = await runner.runProbe(["config", "--null", "--get", "core.fsmonitor"]) else {
        return .disabled
    }
    guard configBytes.last == 0 else {
        return .disabled
    }
    let stripped = configBytes.dropLast()
    if stripped.contains(0) {
        return .disabled
    }
    guard let config = String(bytes: stripped, encoding: .utf8) else {
        return .disabled
    }

    let configured: Bool
    if ["true", "yes", "on"].contains(where: { config.caseInsensitiveCompare($0) == .orderedSame }) {
        configured = true
    } else if ["false", "no", "off"].contains(where: { config.caseInsensitiveCompare($0) == .orderedSame }) {
        configured = false
    } else {
        let typedArgs = [
            "config",
            "--null",
            "--type=bool",
            "--fixed-value",
            "--get",
            "core.fsmonitor",
            config,
        ]
        configured = await runner.runProbe(typedArgs).map { $0 == Array("true\0".utf8) } ?? false
    }
    if !configured {
        return .disabled
    }

    guard let buildOptions = await runner.runProbe(["version", "--build-options"]) else {
        return .disabled
    }
    let lines = buildOptions.split(separator: 10, omittingEmptySubsequences: false)
    let feature = Array("feature: fsmonitor--daemon".utf8)
    if lines.contains(where: { Array($0).trimASCII() == feature }) {
        return .builtIn
    }
    return .disabled
}

extension Array where Element == UInt8 {
    fileprivate func trimASCII() -> [UInt8] {
        var start = 0
        var end = count
        while start < end && (self[start] == 9 || self[start] == 10 || self[start] == 13 || self[start] == 32) {
            start += 1
        }
        while end > start && (self[end - 1] == 9 || self[end - 1] == 10 || self[end - 1] == 13 || self[end - 1] == 32) {
            end -= 1
        }
        return Array(self[start..<end])
    }
}
