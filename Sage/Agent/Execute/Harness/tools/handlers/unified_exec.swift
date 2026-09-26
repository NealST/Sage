//
//  unified_exec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/unified_exec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session / environment selection wait for Phase 5. Command resolution is
//  faithful; execution is delegated through onMcpCall-style callbacks later
//  via UnifiedExecRuntime (ToolsRuntimes).
//

import CodexCore
import CodexProtocol
import CodexShellCommand

struct ExecCommandArgs: Decodable {
    var cmd: String
    var shell: String?
    var login: Bool?
    var tty: Bool
    var yieldTimeMs: UInt64
    var timeoutMs: UInt64?
    var maxOutputTokens: Int?
    var sandboxPermissions: CodexProtocol.SandboxPermissions?
    var additionalPermissions: AdditionalPermissionProfile?
    var justification: String?
    var prefixRule: [String]?

    enum CodingKeys: String, CodingKey {
        case cmd, shell, login, tty
        case yieldTimeMs = "yield_time_ms"
        case timeoutMs = "timeout_ms"
        case maxOutputTokens = "max_output_tokens"
        case sandboxPermissions = "sandbox_permissions"
        case additionalPermissions = "additional_permissions"
        case justification
        case prefixRule = "prefix_rule"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cmd = try container.decode(String.self, forKey: .cmd)
        shell = try container.decodeIfPresent(String.self, forKey: .shell)
        login = try container.decodeIfPresent(Bool.self, forKey: .login)
        tty = try container.decodeIfPresent(Bool.self, forKey: .tty) ?? false
        yieldTimeMs = try container.decodeIfPresent(UInt64.self, forKey: .yieldTimeMs) ?? 10_000
        timeoutMs = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMs)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        sandboxPermissions = try container.decodeIfPresent(
            CodexProtocol.SandboxPermissions.self, forKey: .sandboxPermissions
        )
        additionalPermissions = try container.decodeIfPresent(
            AdditionalPermissionProfile.self, forKey: .additionalPermissions
        )
        justification = try container.decodeIfPresent(String.self, forKey: .justification)
        prefixRule = try container.decodeIfPresent([String].self, forKey: .prefixRule)
    }
}

struct ResolvedCommand: Equatable, Sendable {
    var command: [String]
    var shellType: ShellType
}

func getCommand(
    args: ExecCommandArgs,
    sessionShell: Shell,
    shellMode: UnifiedExecShellMode,
    allowLoginShell: Bool,
    zshPath: String = "/bin/zsh"
) throws -> ResolvedCommand {
    let useLoginShell: Bool
    switch args.login {
    case true where !allowLoginShell:
        throw FunctionCallError.respondToModel(
            "login shell is disabled by config; omit `login` or set it to false."
        )
    case let .some(value):
        useLoginShell = value
    case nil:
        useLoginShell = allowLoginShell || shellMode == .login
    }

    switch shellMode {
    case .direct, .login:
        let shell = args.shell.map(getShellByModelProvidedPath) ?? sessionShell
        return ResolvedCommand(
            command: shell.deriveExecArgs(args.cmd, useLoginShell: useLoginShell),
            shellType: shell.shellType
        )
    case .zshFork:
        if args.shell != nil {
            throw FunctionCallError.respondToModel(
                "`shell` is not supported for local zsh-fork exec; omit `shell` to use zsh-fork, or target a remote environment where `shell` is supported."
            )
        }
        return ResolvedCommand(
            command: [
                zshPath,
                useLoginShell ? "-lc" : "-c",
                args.cmd,
            ],
            shellType: .zsh
        )
    }
}

struct ExecCommandHandlerOptions: Equatable, Sendable {
    var allowLoginShell: Bool
    var execPermissionApprovalsEnabled: Bool
    var includeEnvironmentId: Bool
    var includeShellParameter: Bool
}

struct ExecCommandHandler: CoreToolRuntime {
    var options: ExecCommandHandlerOptions
    var sessionShell: Shell
    var shellMode: UnifiedExecShellMode
    var onExec: (@Sendable (ResolvedCommand, ExecCommandArgs) async -> String)?

    init(
        options: ExecCommandHandlerOptions = ExecCommandHandlerOptions(
            allowLoginShell: true,
            execPermissionApprovalsEnabled: false,
            includeEnvironmentId: false,
            includeShellParameter: true
        ),
        sessionShell: Shell = defaultUserShell(),
        shellMode: UnifiedExecShellMode = .direct,
        onExec: (@Sendable (ResolvedCommand, ExecCommandArgs) async -> String)? = nil
    ) {
        self.options = options
        self.sessionShell = sessionShell
        self.shellMode = shellMode
        self.onExec = onExec
    }

    func toolName() -> ToolName { ToolName(plain: "exec_command") }
    func spec() -> ToolSpec {
        createExecCommandTool(
            options: CommandToolOptions(
                allowLoginShell: options.allowLoginShell,
                execPermissionApprovalsEnabled: options.execPermissionApprovalsEnabled
            ),
            includeEnvironmentId: options.includeEnvironmentId,
            includeShellParameter: options.includeShellParameter
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "exec_command handler received unsupported payload"
            )
        }
        let args: ExecCommandArgs = try parseArguments(arguments)
        let resolved = try getCommand(
            args: args,
            sessionShell: sessionShell,
            shellMode: shellMode,
            allowLoginShell: options.allowLoginShell
        )
        if let onExec {
            let output = await onExec(resolved, args)
            return boxedToolOutput(FunctionToolOutput.fromText(output, success: true))
        }
        throw FunctionCallError.respondToModel(
            "exec_command is not wired (Phase 5 Session / ToolsRuntimes)"
        )
    }
}

struct WriteStdinArgs: Decodable {
    var sessionId: UInt64
    var chars: String?
    var yieldTimeMs: UInt64?
    var maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case chars
        case yieldTimeMs = "yield_time_ms"
        case maxOutputTokens = "max_output_tokens"
    }
}

struct WriteStdinHandler: CoreToolRuntime {
    var onWrite: (@Sendable (WriteStdinArgs) async -> String)?

    func toolName() -> ToolName { ToolName(plain: "write_stdin") }
    func spec() -> ToolSpec { createWriteStdinTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "write_stdin handler received unsupported payload"
            )
        }
        let args: WriteStdinArgs = try parseArguments(arguments)
        if let onWrite {
            return boxedToolOutput(FunctionToolOutput.fromText(await onWrite(args), success: true))
        }
        throw FunctionCallError.respondToModel(
            "write_stdin is not wired (Phase 5 Session / ToolsRuntimes)"
        )
    }
}
