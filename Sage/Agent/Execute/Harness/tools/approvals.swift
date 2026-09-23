//
//  approvals.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/approvals.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Orchestrator-stage approval types. User-facing cards stay on
//  `SessionToolAllowlist` + HUD; this file caches decisions so an already
//  approved command is not asked again on sandbox escalate.
//

import Foundation

enum ReviewDecision: Sendable, Equatable {
    case approved
    case approvedForSession
    case denied(reason: String)
    case abort
}

struct ApprovalContext: Sendable, Equatable {
    var callID: String
    var toolName: String
    var approvalReason: String?
    var retryReason: String?
}

enum ApprovalAction: Sendable, Equatable {
    case execCommand(
        id: String,
        command: String,
        cwd: URL,
        permissionBits: SandboxPermissionBits
    )
    case applyPatch(
        id: String,
        cwd: URL,
        files: [URL],
        patch: String
    )

    var cacheKey: String {
        switch self {
        case .execCommand(_, let command, let cwd, let bits):
            return [
                "exec",
                command,
                cwd.standardizedFileURL.path,
                String(bits.rawValue),
            ].joined(separator: "\n")

        case .applyPatch(_, let cwd, let files, _):
            let paths = files
                .map { $0.standardizedFileURL.path }
                .sorted()
                .joined(separator: ",")
            return ["apply_patch", cwd.standardizedFileURL.path, paths].joined(separator: "\n")
        }
    }
}

/// Serialized-key cache matching Codex `ApprovalStore`.
@MainActor
final class ApprovalStore {
    private var map: [String: ReviewDecision] = [:]

    func get(_ key: String) -> ReviewDecision? {
        map[key]
    }

    func put(_ key: String, _ value: ReviewDecision) {
        map[key] = value
    }

    func reset() {
        map.removeAll()
    }
}

@MainActor
func withCachedApproval(
    store: ApprovalStore,
    keys: [String],
    fetch: () async throws -> ReviewDecision
) async throws -> ReviewDecision {
    if !keys.isEmpty,
       keys.allSatisfy({ store.get($0) == .approvedForSession }) {
        return .approvedForSession
    }

    let decision = try await fetch()
    if decision == .approvedForSession {
        for key in keys {
            store.put(key, decision)
        }
    }
    return decision
}

protocol ApprovalRequesting: Sendable {
    func requestApproval(
        action: ApprovalAction,
        context: ApprovalContext
    ) async throws -> ReviewDecision
}

enum SandboxEscalation {
    static let titlePrefix = "Sandbox denied this command."

    static func title(reason: String, original: String) -> String {
        "\(titlePrefix) \(reason)\n\(original)"
    }

    static func isEscalation(_ title: String) -> Bool {
        title.hasPrefix(titlePrefix)
    }
}

/// Turns Sage's existing capability evidence into an orchestrator decision.
struct InvocationApprover: ApprovalRequesting {
    var authorization: ToolAuthorizationRequirement?
    var evidence: ToolInvocationAuthorizationEvidence?

    func requestApproval(
        action _: ApprovalAction,
        context: ApprovalContext
    ) async throws -> ReviewDecision {
        if let retryReason = context.retryReason {
            throw HarnessToolError.needsEscalationApproval(reason: retryReason)
        }
        guard let authorization else {
            return .approved
        }
        guard evidence?.requirementKey == authorization.stableKey else {
            throw HarnessToolError.rejected("This tool call requires authorization.")
        }
        return .approved
    }
}
