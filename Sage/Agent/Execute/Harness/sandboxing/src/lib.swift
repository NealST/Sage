//
//  lib.swift
//  SageSandboxing
//
//  Port of codex-rs/sandboxing/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Re-exports live in their mapped files. Linux bwrap warning is `nil` on
//  macOS. `SandboxTransformError` → `SageErr` mapping is in this file.
//  Windows MXC / landlock symbols are omitted (`excluded(platform)`).
//

import SageProtocol

public func systemBwrapWarning(
    _ permissionProfile: PermissionProfile
) -> String? {
    nil
}

extension SageErr {
    public init(_ error: SandboxTransformError) {
        switch error {
        case .invalidCommandCwd, .invalidSandboxPolicyCwd:
            self = .invalidRequest(error.description)
        case .missingLinuxSandboxExecutable:
            self = .landlockSandboxExecutableNotProvided
        case .environmentNetworkProxy(let message),
             .windowsMxcPreparation(let message),
             .seatbeltPreparation(let message):
            self = .unsupportedOperation(message)
        }
    }
}
