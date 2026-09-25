//
//  sandbox.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/sandbox.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Identifies the platform sandbox implementation selected for execution.
//  `effective_windows_sandbox_type` preserves MXC selection while honoring
//  legacy runtime level updates. WindowsSandboxLevel is forward-referenced
//  from config_types (ported in Phase 1 config_types.swift).
//

import Foundation

/// Wire: `#[serde(rename_all = "camelCase")]`.
public enum SandboxType: String, Codable, Equatable, Sendable {
    case none
    case macosSeatbelt
    case linuxSeccomp
    case windowsRestrictedToken
    case windowsMxc

    public var metricTag: String {
        switch self {
        case .none: "none"
        case .macosSeatbelt: "seatbelt"
        case .linuxSeccomp: "seccomp"
        case .windowsRestrictedToken: "windows_sandbox"
        case .windowsMxc: "windows_mxc"
        }
    }
}

/// Preserves explicit MXC selection while honoring legacy runtime level updates.
public func effectiveWindowsSandboxType(
    sandboxType: SandboxType,
    sandboxLevel: WindowsSandboxLevel
) -> SandboxType {
    switch (sandboxType, sandboxLevel) {
    case (.windowsMxc, _):
        return .windowsMxc
    case (_, .disabled):
        return .none
    case (_, .restrictedToken), (_, .elevated):
        return .windowsRestrictedToken
    }
}
