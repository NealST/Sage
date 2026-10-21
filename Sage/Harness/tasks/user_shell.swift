//
//  user_shell.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/user_shell.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `/shell` runs unsandboxed under the user's login shell. A standalone
//  command owns a turn. An auxiliary command injects into the active turn
//  and does not emit another TurnStarted. Turn environments do not carry a
//  shell yet, so this uses `defaultUserShell()` and that environment's cwd.
//  Stdout and stderr chunks are emitted as `ExecCommandOutputDelta` while
//  the command runs. When `shell_snapshot` is enabled, a snapshot file is
//  captured once per cwd and sourced before the command. A packaged
//  `sage-path` directory is prepended to PATH and replayed after that
//  snapshot. When `SAGE_NETWORK_PROXY_ACTIVE` is set, managed proxy
//  variables are removed before launch. The recorded command stays the
//  login shell. Managed CA bundle hashing stays out. The exec environment
//  starts from the process environment.
//

import SageAsyncUtils
import SageCore
import SageProtocol
import SageShellCommand
import SageUtils
import Foundation
import ToolsRuntimes

let userShellTimeoutMs: UInt64 = 60 * 60 * 1_000

enum UserShellCommandMode: Equatable, Sendable {
    case standaloneTurn
    case activeTurnAuxiliary
}

final class UserShellCommandTask: SessionTask, @unchecked Sendable {
    var command: String
    var timeoutMs: UInt64?
    var kind: TaskKind { .regular }

    init(command: String, timeoutMs: UInt64? = nil) {
        self.command = command
        self.timeoutMs = timeoutMs
    }

    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String? {
        _ = input
        await executeUserShellCommand(UserShellCommandRequest(
            session: session,
            turnContext: context,
            command: command,
            timeoutMs: timeoutMs,
            cancellationToken: cancellationToken,
            mode: .standaloneTurn
        ))
        return nil
    }
}

struct UserShellCommandRequest {
    var session: Session
    var turnContext: TurnContext
    var command: String
    var timeoutMs: UInt64?
    var cancellationToken: CancellationToken
    var mode: UserShellCommandMode
}

func executeUserShellCommand(_ request: UserShellCommandRequest) async {
    if request.mode == .standaloneTurn {
        request.session.emitTurnStarted(request.turnContext)
    }
    if let path = await ensureUserShellSnapshot(request) {
        request.turnContext.environment.shellSnapshotPath = path
    }
    guard let launch = userShellLaunch(request) else { return }
    request.session.emitTurnItemStarted(
        request.turnContext,
        .commandExecution(
            userShellItem(launch, output: nil, status: .inProgress, truncationPolicy: .bytes(10_000))
        )
    )
    finishUserShell(request, launch, await userShellOutput(request, launch))
}

struct CapturedShellSnapshot: Equatable, Sendable {
    var cwd: String
    var path: String
}

private func ensureUserShellSnapshot(_ request: UserShellCommandRequest) async -> String? {
    let environment = request.turnContext.environment
    guard request.turnContext.config.features.enabled(.shellSnapshot) else { return nil }
    guard environment.shellSnapshotPath == nil else { return nil }
    if let cached = request.session.capturedShellSnapshot,
       cached.cwd == environment.cwd,
       FileManager.default.fileExists(atPath: cached.path) {
        return cached.path
    }
    guard let cwd = try? AbsolutePathBuf.fromAbsolutePathChecked(environment.cwd),
          let home = try? AbsolutePathBuf.fromAbsolutePathChecked(
            request.session.state.sessionConfiguration.sageHome
          )
    else { return nil }
    let shell = SageCore.defaultUserShell()
    guard !shell.shellPath.isEmpty else { return nil }
    guard let path = await captureLoginShellSnapshot(
        sageHome: home,
        sessionId: request.turnContext.threadId,
        cwd: cwd,
        shell: shell
    ) else { return nil }
    request.session.capturedShellSnapshot = CapturedShellSnapshot(cwd: environment.cwd, path: path)
    return path
}

private func userShellLaunch(_ request: UserShellCommandRequest) -> UserShellLaunch? {
    let shell = SageCore.defaultUserShell()
    guard !shell.shellPath.isEmpty else {
        sendUserShellError(request, "shell is unavailable in this session")
        return nil
    }
    guard let cwd = try? AbsolutePathBuf.fromAbsolutePathChecked(request.turnContext.environment.cwd) else {
        sendUserShellError(request, "shell working directory is not native to the Sage host")
        return nil
    }
    let displayCommand = shell.deriveExecArgs(request.command, useLoginShell: true)
    let plan = userShellExecPlan(UserShellExecRequest(
        displayCommand: displayCommand,
        sessionShellPath: shell.shellPath,
        snapshotPath: request.turnContext.environment.shellSnapshotPath,
        featureEnabled: request.turnContext.config.features.enabled(.shellSnapshot),
        packagePathDir: sagePackagePathDir(executablePath: Bundle.main.executablePath ?? ""),
        baseEnv: ProcessInfo.processInfo.environment
    ))
    return UserShellLaunch(
        callId: UUID().uuidString,
        rawCommand: request.command,
        displayCommand: displayCommand,
        execCommand: plan.command,
        env: plan.env,
        cwd: cwd
    )
}

struct UserShellExecRequest {
    var displayCommand: [String]
    var sessionShellPath: String
    var snapshotPath: String?
    var featureEnabled: Bool
    var packagePathDir: String?
    var baseEnv: [String: String]
}

struct UserShellExecPlan: Equatable {
    var command: [String]
    var env: [String: String]
}

func userShellExecPlan(_ request: UserShellExecRequest) -> UserShellExecPlan {
    var env = request.baseEnv
    if env[PROXY_ACTIVE_ENV_KEY] != nil {
        env = stripManagedProxyEnv(env)
    }
    var prepends = RuntimePathPrepends()
    if let packagePathDir = request.packagePathDir {
        prepends.prepend(&env, pathEntry: packagePathDir)
    }
    let pathExports = prepends.shellExportsAfterSnapshot(explicitEnvOverrides: [:])
    let command = wrappedUserShellCommand(request, pathExports: pathExports)
    return UserShellExecPlan(command: command, env: env)
}

private func wrappedUserShellCommand(_ request: UserShellExecRequest, pathExports: String) -> [String] {
    guard request.featureEnabled, let snapshotPath = request.snapshotPath else {
        return request.displayCommand
    }
    return wrapShellLoginCommandWithSnapshot(
        command: request.displayCommand,
        sessionShellPath: request.sessionShellPath,
        snapshotPath: snapshotPath,
        pathExports: pathExports
    )
}

private func wrapShellLoginCommandWithSnapshot(
    command: [String],
    sessionShellPath: String,
    snapshotPath: String,
    pathExports: String
) -> [String] {
    guard command.count >= 3, command[1] == "-lc" else { return command }
    guard FileManager.default.fileExists(atPath: snapshotPath) else { return command }
    let originalShell = quotedShellLiteral(command[0])
    let snapshot = quotedShellLiteral(snapshotPath)
    let script = quotedShellLiteral(command[2])
    let trailing = command.dropFirst(3).map { " '\(quotedShellLiteral($0))'" }.joined()
    var lines = ["if . '\(snapshot)' >/dev/null 2>&1; then :; fi", ""]
    if !pathExports.isEmpty {
        lines.append(pathExports)
        lines.append("")
    }
    lines.append("exec '\(originalShell)' -c '\(script)'\(trailing)")
    return [sessionShellPath, "-c", lines.joined(separator: "\n")]
}

private func quotedShellLiteral(_ input: String) -> String {
    input.replacingOccurrences(of: "'", with: "'\"'\"'")
}

private func userShellOutput(
    _ request: UserShellCommandRequest,
    _ launch: UserShellLaunch
) async -> ExecToolCallOutput {
    if request.cancellationToken.isCancelled { return abortedUserShellOutput() }
    let timeout = Duration.milliseconds(Int64(request.timeoutMs ?? userShellTimeoutMs))
    let execRequest = ExecRequest(
        command: launch.execCommand,
        cwd: launch.cwd,
        env: launch.env,
        network: nil,
        networkEnvironmentId: nil,
        expiration: .timeoutOrCancellation(timeout: timeout, cancellation: request.cancellationToken),
        capturePolicy: .shellTool,
        sandbox: SageProtocol.SandboxType.none,
        windowsSandboxWorkspaceRoots: [],
        windowsSandboxLevel: .disabled,
        permissionProfile: .disabled,
        arg0: nil
    )
    let result = await executeExecRequest(
        execRequest,
        stdoutStream: userShellStdoutStream(
            request.session,
            subId: request.turnContext.subId,
            callId: launch.callId
        ),
        afterSpawn: nil
    )
    if request.cancellationToken.isCancelled { return abortedUserShellOutput() }
    switch result {
    case .success(let output):
        return output

    case .failure(let error):
        return failedUserShellOutput("execution error: \(String(describing: error))")
    }
}

private struct UserShellLaunch {
    var callId: String
    var rawCommand: String
    var displayCommand: [String]
    var execCommand: [String]
    var env: [String: String]
    var cwd: AbsolutePathBuf

    var parsedCmd: [ParsedCommand] { parseCommand(displayCommand) }
    var cwdUri: PathUri { PathUri.fromAbsPath(cwd) }
}

private func finishUserShell(
    _ request: UserShellCommandRequest,
    _ launch: UserShellLaunch,
    _ output: ExecToolCallOutput
) {
    let policy = TruncationPolicy(request.turnContext.modelInfoValue().truncationPolicy)
    let status: CommandExecutionStatus = output.exitCode == 0 ? .completed : .failed
    request.session.emitTurnItemCompleted(
        request.turnContext,
        .commandExecution(userShellItem(launch, output: output, status: status, truncationPolicy: policy))
    )
    persistUserShellOutput(request, launch.rawCommand, output, truncationPolicy: policy)
}

private func persistUserShellOutput(
    _ request: UserShellCommandRequest,
    _ command: String,
    _ output: ExecToolCallOutput,
    truncationPolicy: TruncationPolicy
) {
    let truncated = formatExecOutputStr(output, truncationPolicy: truncationPolicy)
    let item = ContextUserShellCommand(
        command: command,
        exitCode: output.exitCode,
        duration: durationSecondsValue(output.duration),
        output: truncated
    ).asResponseItem()
    if request.mode == .standaloneTurn {
        request.session.recordConversationItems(request.turnContext, items: [item])
        return
    }
    request.session.injectNoNewTurn([item], currentTurnContext: request.turnContext)
}

private func userShellItem(
    _ launch: UserShellLaunch,
    output: ExecToolCallOutput?,
    status: CommandExecutionStatus,
    truncationPolicy: TruncationPolicy
) -> CommandExecutionItem {
    let formatted = output.map { formatExecOutputStr($0, truncationPolicy: truncationPolicy) }
    return CommandExecutionItem(
        id: launch.callId,
        command: launch.displayCommand,
        cwd: launch.cwdUri,
        parsedCmd: launch.parsedCmd,
        source: .userShell,
        status: status,
        stdout: output?.stdout.text,
        stderr: output?.stderr.text,
        aggregatedOutput: output?.aggregatedOutput.text,
        exitCode: output?.exitCode,
        duration: output?.duration,
        formattedOutput: formatted
    )
}

private func userShellStdoutStream(_ session: Session, subId: String, callId: String) -> StdoutStream {
    makeExecStdoutStream(subId: subId, callId: callId) { deltaCallId, isStderr, chunk in
        let delta = SageProtocol.ExecCommandOutputDeltaEvent(
            callId: deltaCallId,
            stream: isStderr
                ? SageProtocol.ExecOutputStream.stderr
                : SageProtocol.ExecOutputStream.stdout,
            chunk: chunk
        )
        Task { @MainActor in
            session.sendEventRaw(Event(id: subId, msg: .execCommandOutputDelta(delta)))
        }
    }
}

private func abortedUserShellOutput() -> ExecToolCallOutput {
    failedUserShellOutput("command aborted by user")
}

private func failedUserShellOutput(_ message: String) -> ExecToolCallOutput {
    ExecToolCallOutput(
        exitCode: -1,
        stdout: .new(""),
        stderr: .new(message),
        aggregatedOutput: .new(message),
        duration: .zero,
        timedOut: false
    )
}

private func sendUserShellError(_ request: UserShellCommandRequest, _ message: String) {
    request.session.sendEvent(request.turnContext, .error(ErrorEvent(message: message)))
}
