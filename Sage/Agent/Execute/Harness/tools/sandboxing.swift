//
//  sandboxing.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/sandboxing.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Shared approval + sandbox traits for tool runtimes. Guardian, Windows
//  Landlock, and the network proxy stay out; Mac Seatbelt + PathGuard remain
//  the process isolation.
//

import ApplyPatch
import Foundation

/// Permission bits the orchestrator turns into a Seatbelt profile.
/// Model-facing `allow_writes` / `allow_network` / `allow_protected_metadata_writes`
/// land here instead of branching inside the shell tool.
struct SandboxPermissionBits: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    static let writes = Self(rawValue: 1 << 0)
    static let network = Self(rawValue: 1 << 1)
    static let protectedMetadataWrites = Self(rawValue: 1 << 2)

    var requiresEscalatedPermissions: Bool {
        contains(.network) || contains(.protectedMetadataWrites)
    }
}

enum SandboxPermissions: Sendable, Equatable {
    case useDefault
    case requireEscalated
}

enum SandboxablePreference: Sendable, Equatable {
    case auto
    case require
    case forbid
}

enum SandboxType: Sendable, Equatable {
    case none
    case seatbelt
}

enum SandboxOverride: Sendable, Equatable {
    case noOverride
    case bypassSandboxFirstAttempt
}

enum FileSystemSandboxKind: Sendable, Equatable {
    case unrestricted
    case restricted
}

struct FileSystemSandboxPolicy: Sendable, Equatable {
    var kind: FileSystemSandboxKind
    /// Absolute roots the sandbox must keep unreadable (Project home denial).
    var deniedReadRoots: [String]

    var hasDeniedReadRestrictions: Bool {
        !deniedReadRoots.isEmpty
    }

    static func sage(_ policy: PathGuard.Policy) -> Self {
        switch policy {
        case .home:
            return Self(kind: .restricted, deniedReadRoots: [])

        case .project:
            return Self(kind: .restricted, deniedReadRoots: [PathGuard.resolvedHomePath])
        }
    }
}

enum AskForApproval: Sendable, Equatable {
    case never
    case onRequest
    case unlessTrusted
}

enum ExecApprovalRequirement: Sendable, Equatable {
    case skip(bypassSandbox: Bool)
    case needsApproval(reason: String?)
    case forbidden(reason: String)
}

func defaultExecApprovalRequirement(
    _ policy: AskForApproval,
    fileSystem: FileSystemSandboxPolicy
) -> ExecApprovalRequirement {
    let needsApproval = switch policy {
    case .never:
        false

    case .onRequest:
        fileSystem.kind == .restricted

    case .unlessTrusted:
        true
    }

    if needsApproval {
        return .needsApproval(reason: nil)
    }
    return .skip(bypassSandbox: false)
}

func sandboxOverrideForFirstAttempt(
    _ sandboxPermissions: SandboxPermissions,
    execApprovalRequirement: ExecApprovalRequirement,
    fileSystem: FileSystemSandboxPolicy
) -> SandboxOverride {
    if !unsandboxedExecutionAllowed(fileSystem) {
        return .noOverride
    }
    if case .skip(let bypass) = execApprovalRequirement, bypass {
        return .bypassSandboxFirstAttempt
    }
    if sandboxPermissions == .requireEscalated {
        return .bypassSandboxFirstAttempt
    }
    return .noOverride
}

/// Denied reads only exist inside the sandbox. Dropping Seatbelt in Project
/// mode would silently re-open `~`.
func unsandboxedExecutionAllowed(_ fileSystem: FileSystemSandboxPolicy) -> Bool {
    !fileSystem.hasDeniedReadRestrictions
}

enum HarnessToolError: Error, Equatable, LocalizedError {
    case rejected(String)
    case sandboxDenied(output: String)
    /// Seatbelt denied the command and dropping the sandbox needs a fresh user card.
    case needsEscalationApproval(reason: String)

    var errorDescription: String? {
        switch self {
        case .rejected(let reason):
            return reason

        case .sandboxDenied(let output):
            return output

        case .needsEscalationApproval(let reason):
            return reason
        }
    }

    static func isSandboxDenial(exitCode: Int32, output: String) -> Bool {
        if exitCode == 0 { return false }
        let needles = [
            "operation not permitted",
            "permission denied",
            "sandbox",
        ]
        let lowered = output.lowercased()
        return needles.contains { lowered.contains($0) }
    }
}

struct ToolCtx: Sendable {
    var callID: String
    var toolName: String
    var pathGuardPolicy: PathGuard.Policy
    var workPlanKind: WorkPlan.Kind?
    var approvalPolicy: AskForApproval
    var fileSystemPolicy: FileSystemSandboxPolicy
    var readAllowlist: [String]
    var extraReadableRoots: [URL]
    /// User already approved dropping Seatbelt for this call.
    var allowUnsandboxedRetry = false

    static func sage(
        request: ToolInvocationRequest,
        callID: String? = nil
    ) -> Self {
        let allowlist = SkillToolExecutor.readAllowlist(
            activatedSkillNames: request.activatedSkillNames,
            enabledSkills: request.enabledSkills
        ) + request.extraReadAllowlist
        return Self(
            callID: callID ?? request.toolCallID,
            toolName: request.name,
            pathGuardPolicy: request.pathGuardPolicy,
            workPlanKind: request.workPlanKind,
            approvalPolicy: .unlessTrusted,
            fileSystemPolicy: .sage(request.pathGuardPolicy),
            readAllowlist: allowlist,
            extraReadableRoots: [],
            allowUnsandboxedRetry: request.allowUnsandboxedRetry
        )
    }

    var workspaceRoot: URL {
        pathGuardPolicy.defaultWorkingDirectory
    }
}

struct SandboxAttempt: Sendable, Equatable {
    var sandbox: SandboxType
    var sandboxRequested: Bool
    var permissionBits: SandboxPermissionBits
    var sandboxCwd: URL
    var workspaceRoot: URL
    var profile: SeatbeltSandbox.Profile
    var fileSystemPolicy: FileSystemSandboxPolicy

    var isEscalated: Bool {
        sandbox == .none && sandboxRequested
    }

    static func make(
        sandbox: SandboxType,
        sandboxRequested: Bool,
        bits: SandboxPermissionBits,
        cwd: URL,
        ctx: ToolCtx
    ) -> Self {
        let profileBits: SandboxPermissionBits = sandbox == .none
            ? bits.union([.writes, .network, .protectedMetadataWrites])
            : bits
        return Self(
            sandbox: sandbox,
            sandboxRequested: sandboxRequested,
            permissionBits: bits,
            sandboxCwd: cwd,
            workspaceRoot: ctx.workspaceRoot,
            profile: SeatbeltSandbox.workspaceWriteProfile(
                policy: ctx.pathGuardPolicy,
                bits: profileBits,
                readAllowlist: ctx.readAllowlist,
                extraReadableRoots: ctx.extraReadableRoots
            ),
            fileSystemPolicy: ctx.fileSystemPolicy
        )
    }
}

protocol Approvable: Sendable {
    associatedtype Request: Sendable

    func sandboxPermissions(_ request: Request) -> SandboxPermissions
    func shouldBypassApproval(policy: AskForApproval, alreadyApproved: Bool) -> Bool
    func execApprovalRequirement(_ request: Request) -> ExecApprovalRequirement?
    func wantsNoSandboxApproval(policy: AskForApproval) -> Bool
    func approvalAction(_ request: Request, callID: String) -> ApprovalAction
}

extension Approvable {
    func sandboxPermissions(_ request: Request) -> SandboxPermissions {
        .useDefault
    }

    func shouldBypassApproval(policy: AskForApproval, alreadyApproved: Bool) -> Bool {
        if alreadyApproved { return true }
        return policy == .never
    }

    func execApprovalRequirement(_ request: Request) -> ExecApprovalRequirement? {
        nil
    }

    func wantsNoSandboxApproval(policy: AskForApproval) -> Bool {
        switch policy {
        case .unlessTrusted:
            return true

        case .never, .onRequest:
            return false
        }
    }
}

protocol Sandboxable: Sendable {
    func sandboxPreference() -> SandboxablePreference
    func escalateOnFailure() -> Bool
}

extension Sandboxable {
    func escalateOnFailure() -> Bool { true }
}

protocol ToolRuntime: Approvable, Sandboxable {
    associatedtype Output: Sendable

    func sandboxCwd(_ request: Request) -> URL?
    func run(
        _ request: Request,
        attempt: SandboxAttempt,
        ctx: ToolCtx
    ) async throws -> Output
}

extension ToolRuntime {
    func sandboxCwd(_ request: Request) -> URL? { nil }
}

enum ExecSandbox {
    static func selectInitial(
        preference: SandboxablePreference,
        override: SandboxOverride
    ) -> (sandbox: SandboxType, requested: Bool) {
        if preference == .forbid {
            return (.none, false)
        }
        let requested = override != .bypassSandboxFirstAttempt
        if !requested {
            return (.none, false)
        }
        return (SeatbeltSandbox.isAvailable ? .seatbelt : .none, requested)
    }

    static func selectRetry(
        fileSystem: FileSystemSandboxPolicy,
        preference: SandboxablePreference
    ) -> SandboxType {
        if unsandboxedExecutionAllowed(fileSystem) {
            return .none
        }
        if preference == .forbid {
            return .none
        }
        return SeatbeltSandbox.isAvailable ? .seatbelt : .none
    }
}

/// Parsed `run_shell_command` arguments. Shared by the handler and orchestrator.
struct ShellExecRequest: Sendable {
    var command: String
    var workingDirectory: URL
    var timeoutSeconds: Int
    var permissionBits: SandboxPermissionBits
    var allowedSensitiveReadRoots: [URL]

    private struct Args: Decodable {
        let command: String
        let workingDirectory: String?
        let timeoutSeconds: Int?
        let allowWrites: Bool?
        let allowNetwork: Bool?
        let allowProtectedMetadataWrites: Bool?
        let sensitiveReadPath: String?
    }

    static func parse(
        _ argumentsJSON: String,
        policy: PathGuard.Policy
    ) throws -> Self {
        try PathGuard.$policy.withValue(policy) {
            let args = try decodeToolArgs(argumentsJSON, as: Args.self)
            let command = args.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw ToolError.invalidArguments("Command cannot be empty.")
            }

            let workDir: URL
            if let dir = args.workingDirectory {
                workDir = try PathGuard.resolveAllowed(dir, policy: policy, access: .read)
            } else {
                workDir = policy.defaultWorkingDirectory
            }
            guard FileManager.default.fileExists(atPath: workDir.path) else {
                throw ToolError.operationFailed(
                    """
                    Working directory does not exist: \(args.workingDirectory ?? workDir.path). \
                    Use create_directory first.
                    """
                )
            }

            var bits = SandboxPermissionBits()
            if args.allowWrites == true { bits.insert(.writes) }
            if args.allowNetwork == true { bits.insert(.network) }
            if args.allowProtectedMetadataWrites == true { bits.insert(.protectedMetadataWrites) }

            return Self(
                command: command,
                workingDirectory: workDir,
                timeoutSeconds: min(max(args.timeoutSeconds ?? 30, 1), 120),
                permissionBits: bits,
                allowedSensitiveReadRoots: try allowedSensitiveRoots(
                    for: args.sensitiveReadPath,
                    policy: policy
                )
            )
        }
    }

    private static func allowedSensitiveRoots(
        for rawPath: String?,
        policy: PathGuard.Policy
    ) throws -> [URL] {
        guard let rawPath else { return [] }
        let url = try PathGuard.resolveAllowed(rawPath, policy: policy, access: .read)
        guard let root = SensitiveResourcePolicy.containingRoot(for: url) else {
            throw ToolError.invalidArguments(
                "sensitive_read_path must identify a protected sensitive directory."
            )
        }
        return [root]
    }
}

struct ShellRuntime: ToolRuntime {
    func sandboxPreference() -> SandboxablePreference { .auto }

    func escalateOnFailure() -> Bool { true }

    func sandboxPermissions(_ request: ShellExecRequest) -> SandboxPermissions {
        request.permissionBits.requiresEscalatedPermissions ? .requireEscalated : .useDefault
    }

    func execApprovalRequirement(_ request: ShellExecRequest) -> ExecApprovalRequirement? {
        if request.permissionBits.isEmpty {
            return .skip(bypassSandbox: false)
        }
        return .needsApproval(reason: nil)
    }

    func wantsNoSandboxApproval(policy: AskForApproval) -> Bool {
        switch policy {
        case .unlessTrusted:
            return true

        case .never, .onRequest:
            return false
        }
    }

    func approvalAction(_ request: ShellExecRequest, callID: String) -> ApprovalAction {
        .execCommand(
            id: callID,
            command: request.command,
            cwd: request.workingDirectory,
            permissionBits: request.permissionBits
        )
    }

    func sandboxCwd(_ request: ShellExecRequest) -> URL? {
        request.workingDirectory
    }

    func run(
        _ request: ShellExecRequest,
        attempt: SandboxAttempt,
        ctx: ToolCtx
    ) async throws -> String {
        try ShellCommandPolicy.validate(request.command)
        if let patch = ApplyPatchInvocation.patchDocument(inShellCommand: request.command) {
            return try ApplyPatchToolRuntime.applyEmbedded(
                patch: patch,
                cwd: request.workingDirectory,
                attempt: attempt,
                policy: ctx.pathGuardPolicy
            )
        }
        let invocation: SeatbeltInvocation
        switch attempt.sandbox {
        case .seatbelt:
            invocation = SeatbeltSandbox.invocation(
                command: request.command,
                profile: attempt.profile
            )

        case .none:
            invocation = SeatbeltInvocation(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-f", "-c", request.command],
                environment: nil
            )
        }

        let result = try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: request.workingDirectory,
            timeout: .seconds(request.timeoutSeconds),
            environment: invocation.environment ?? ChildProcessEnvironment.sanitized()
        )
        let output: String
        if result.timedOut {
            output = result.output + "\n… (command timed out after \(request.timeoutSeconds)s)"
        } else {
            output = result.output
        }
        let formatted = Self.format(exitCode: result.exitCode, output: output)
        if attempt.sandbox == .seatbelt,
           HarnessToolError.isSandboxDenial(exitCode: result.exitCode, output: formatted) {
            throw HarnessToolError.sandboxDenied(output: formatted)
        }
        return formatted
    }

    static func format(exitCode: Int32, output: String) -> String {
        let truncated = output.count > 50_000
        let display: String
        if truncated {
            display = String(output.prefix(50_000))
                + "\n… (output truncated at 50000 bytes)"
        } else {
            display = output
        }
        if exitCode == 0 {
            return display.isEmpty ? "[exit 0] (no output)" : "[exit 0]\n\(display)"
        }
        return "[exit \(exitCode)]\n\(display)"
    }
}
