//
//  deny_read_validator.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permissions/deny_read_validator.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Core's mandatory-denial validation, shared without resolving paths on
//  the controller. Checks raw concrete grants; policy application and
//  sandbox enforcement remain caller-owned.
//

import CodexUtils
import Foundation

/// Prepared mandatory rules reused when a caller replaces its selected profile.
public struct DenyReadValidator {
    var requiredEntries: [FileSystemSandboxEntry]
    var matcher: PreparedReadDenyMatcher?
}

/// Details needed to retain the caller's existing sourced constraint diagnostics.
public enum DenyReadViolation: Equatable, Error {
    case missingRequiredDeny
    case readablePath(PathUri)
}

extension DenyReadValidator {
    /// Prepares the strict matcher once, using the supplied executor facts.
    public init(required: FileSystemSandboxPolicy, context: FileSystemSandboxPolicyContext) throws {
        let matcher: PreparedReadDenyMatcher?
        if hasContextReadDenials(required, context: context) {
            matcher = try required.prepareDenyReadMatcher(
                context: context,
                invalidGlobBehavior: .returnError
            )
        } else {
            matcher = nil
        }
        self.requiredEntries = required.entries
        self.matcher = matcher
    }

    /// Preserves Core's entry-presence and raw readable-path checks.
    public func validate(
        _ selected: FileSystemSandboxPolicy,
        context: FileSystemSandboxPolicyContext
    ) throws {
        let missingRequiredDeny = requiredEntries.contains { !selected.entries.contains($0) }
        let violatingRoot = selected.entries
            .filter { $0.access.canRead() }
            .compactMap { entry -> PathUri? in
                guard case .path(let path) = entry.path else { return nil }
                if path.inferPathConvention() != context.cwd.inferPathConvention() {
                    return nil
                }
                guard let matcher,
                      FileSystemSandboxPolicy.matchesPreparedReadDeny(
                        path, context: context, prepared: matcher)
                else {
                    return nil
                }
                return path
            }
            .first
        if let path = violatingRoot {
            throw DenyReadViolation.readablePath(path)
        }
        if missingRequiredDeny {
            throw DenyReadViolation.missingRequiredDeny
        }
    }
}

func hasContextReadDenials(
    _ policy: FileSystemSandboxPolicy,
    context: FileSystemSandboxPolicyContext
) -> Bool {
    policy.kind == .restricted
        && policy.entries.contains { entry in
            entry.access == .deny
                && !isSlashTmpOnNonPosix(entry.path, cwd: context.cwd)
        }
}

private func isSlashTmpOnNonPosix(_ path: FileSystemPath, cwd: PathUri) -> Bool {
    if case .special(value: .slashTmp) = path {
        return cwd.inferPathConvention() != .posix
    }
    return false
}
