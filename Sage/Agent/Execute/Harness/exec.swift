//
//  exec.swift
//  Sage
//
//  Port of codex-rs/core/src/exec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Unix execute loop, expiration, output cap, and sandbox-denial mapping.
//  Windows sandbox capture is excluded(platform). Tokio child I/O maps to
//  `utils/pty` AsyncStream + Task races. `StdoutStream` uses a callback
//  until `EventMsg.execCommandOutputDelta` is added to protocol.swift.
//

import CodexAsyncUtils
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

public let DEFAULT_EXEC_COMMAND_TIMEOUT_MS: UInt64 = 10_000
let SIGKILL_CODE: Int32 = 9
let TIMEOUT_CODE: Int32 = 64
let EXIT_CODE_SIGNAL_BASE: Int32 = 128
let EXEC_TIMEOUT_EXIT_CODE: Int32 = 124
let CANCELLATION_TERMINATION_GRACE_PERIOD = Duration.milliseconds(50)
let READ_CHUNK_SIZE = 8192
let AGGREGATE_BUFFER_INITIAL_CAPACITY = 8 * 1024
let EXEC_OUTPUT_MAX_BYTES = DEFAULT_OUTPUT_BYTES_CAP
let MAX_EXEC_OUTPUT_DELTAS_PER_CALL = 10_000
public let IO_DRAIN_TIMEOUT_MS: UInt64 = 2_000

public struct ExecParams: Sendable {
    public var command: [String]
    public var cwd: AbsolutePathBuf
    public var expiration: ExecExpiration
    public var capturePolicy: ExecCapturePolicy
    public var env: [String: String]
    public var network: NetworkProxy?
    public var networkEnvironmentId: String?
    public var sandboxPermissions: SandboxPermissions
    public var windowsSandboxLevel: WindowsSandboxLevel
    public var justification: String?
    public var arg0: String?

    public init(
        command: [String],
        cwd: AbsolutePathBuf,
        expiration: ExecExpiration,
        capturePolicy: ExecCapturePolicy = .shellTool,
        env: [String: String] = [:],
        network: NetworkProxy? = nil,
        networkEnvironmentId: String? = nil,
        sandboxPermissions: SandboxPermissions = .useDefault,
        windowsSandboxLevel: WindowsSandboxLevel = .disabled,
        justification: String? = nil,
        arg0: String? = nil
    ) {
        self.command = command
        self.cwd = cwd
        self.expiration = expiration
        self.capturePolicy = capturePolicy
        self.env = env
        self.network = network
        self.networkEnvironmentId = networkEnvironmentId
        self.sandboxPermissions = sandboxPermissions
        self.windowsSandboxLevel = windowsSandboxLevel
        self.justification = justification
        self.arg0 = arg0
    }
}

public enum ExecCapturePolicy: Equatable, Sendable {
    case shellTool
    case fullBuffer
    case fullBufferWithExpiration
    case sensitiveFullBuffer

    func retainedBytesCap() -> Int? {
        switch self {
        case .shellTool: return EXEC_OUTPUT_MAX_BYTES
        case .fullBuffer, .fullBufferWithExpiration, .sensitiveFullBuffer: return nil
        }
    }

    func ioDrainTimeout() -> Duration {
        .milliseconds(Int64(IO_DRAIN_TIMEOUT_MS))
    }

    func usesExpiration() -> Bool {
        switch self {
        case .shellTool, .fullBufferWithExpiration, .sensitiveFullBuffer: return true
        case .fullBuffer: return false
        }
    }
}

public enum ExecExpiration: Sendable {
    case timeout(Duration)
    case defaultTimeout
    case cancellation(CancellationToken)
    case timeoutOrCancellation(timeout: Duration, cancellation: CancellationToken)

    public func waitWithOutcome() async -> ExecExpirationOutcome {
        switch self {
        case .timeout(let duration):
            try? await Task.sleep(for: duration)
            return .timedOut
        case .defaultTimeout:
            try? await Task.sleep(for: .milliseconds(Int64(DEFAULT_EXEC_COMMAND_TIMEOUT_MS)))
            return .timedOut
        case .cancellation(let cancel):
            await cancel.waitForCancellation()
            return .cancelled
        case .timeoutOrCancellation(let timeout, let cancellation):
            return await withTaskGroup(of: ExecExpirationOutcome.self) { group in
                group.addTask {
                    await cancellation.waitForCancellation()
                    return .cancelled
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                group.cancelAll()
                return first
            }
        }
    }

    func cancellationToken() -> CancellationToken? {
        switch self {
        case .timeout, .defaultTimeout: return nil
        case .cancellation(let token), .timeoutOrCancellation(_, let token):
            return token
        }
    }

    func withCancellation(_ cancellation: CancellationToken) -> ExecExpiration {
        switch self {
        case .timeout(let timeout):
            return .timeoutOrCancellation(timeout: timeout, cancellation: cancellation)
        case .defaultTimeout:
            return .timeoutOrCancellation(
                timeout: .milliseconds(Int64(DEFAULT_EXEC_COMMAND_TIMEOUT_MS)),
                cancellation: cancellation
            )
        case .cancellation(let existing):
            return .cancellation(cancelWhenEither(existing, cancellation))
        case .timeoutOrCancellation(let timeout, let existing):
            return .timeoutOrCancellation(
                timeout: timeout,
                cancellation: cancelWhenEither(existing, cancellation)
            )
        }
    }
}

public enum ExecExpirationOutcome: Equatable, Sendable {
    case timedOut
    case cancelled
}

func cancelWhenEither(_ first: CancellationToken, _ second: CancellationToken) -> CancellationToken {
    let combined = first.childToken()
    if combined.isCancelled || second.isCancelled {
        combined.cancel()
        return combined
    }
    let cancel = combined
    Task {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await second.waitForCancellation() }
            group.addTask { await cancel.waitForCancellation() }
            _ = await group.next()
            group.cancelAll()
        }
        cancel.cancel()
    }
    return combined
}

enum ExecOutputStream: Equatable, Sendable {
    case stdout
    case stderr
}

struct ExecCommandOutputDeltaEvent: Sendable {
    var callId: String
    var stream: ExecOutputStream
    var chunk: Data
}

public struct StdoutStream: Sendable {
    var subId: String
    var callId: String
    var emit: @Sendable (ExecCommandOutputDeltaEvent) -> Void
}

func selectProcessExecToolSandboxType(
    permissionProfile: PermissionProfile,
    windowsSandboxType: SandboxType,
    enforceManagedNetwork: Bool
) -> SandboxType {
    SandboxManager().selectInitial(
        permissionProfile: permissionProfile,
        pref: .auto,
        windowsSandboxType: windowsSandboxType,
        hasManagedNetworkRequirements: enforceManagedNetwork
    )
}

func networkProxyEnvironmentError(_ networkEnvironmentId: String?, _ err: Error) -> CodexErr {
    let environmentId = networkEnvironmentId ?? "default"
    return .io("failed to prepare network proxy for environment `\(environmentId)`: \(err)")
}

public func processExecToolCall(
    _ params: ExecParams,
    permissionProfile: PermissionProfile,
    sandboxCwd: AbsolutePathBuf,
    windowsSandboxWorkspaceRoots: [AbsolutePathBuf] = [],
    codexLinuxSandboxExe: String? = nil,
    codexSelfExe: String? = nil,
    useLegacyLandlock: Bool = false,
    stdoutStream: StdoutStream? = nil
) async -> CodexResult<ExecToolCallOutput> {
    let windowsSandboxType: SandboxType = params.windowsSandboxLevel == .disabled
        ? .none
        : .windowsRestrictedToken
    let roots = windowsSandboxWorkspaceRoots.map(PathUri.fromAbsPath)
    do {
        let execReq = try buildExecRequest(
            params,
            permissionProfile: permissionProfile,
            sandboxCwd: sandboxCwd,
            windowsSandboxWorkspaceRoots: roots,
            codexLinuxSandboxExe: codexLinuxSandboxExe,
            codexSelfExe: codexSelfExe,
            windowsSandboxType: windowsSandboxType,
            useLegacyLandlock: useLegacyLandlock
        )
        return await executeEnv(execReq, stdoutStream: stdoutStream)
    } catch let error as CodexErr {
        return .failure(error)
    } catch {
        return .failure(.io(String(describing: error)))
    }
}

func buildExecRequest(
    _ params: ExecParams,
    permissionProfile: PermissionProfile,
    sandboxCwd: AbsolutePathBuf,
    windowsSandboxWorkspaceRoots: [PathUri],
    codexLinuxSandboxExe: String?,
    codexSelfExe: String?,
    windowsSandboxType: SandboxType,
    useLegacyLandlock: Bool
) throws -> ExecRequest {
    var env = params.env
    let enforceManagedNetwork = params.network != nil
    let sandboxType = selectProcessExecToolSandboxType(
        permissionProfile: permissionProfile,
        windowsSandboxType: windowsSandboxType,
        enforceManagedNetwork: enforceManagedNetwork
    )
    if let network = params.network {
        do {
            try network.applyToEnvForOptionalEnvironment(
                &env,
                environmentId: params.networkEnvironmentId
            )
        } catch {
            throw networkProxyEnvironmentError(params.networkEnvironmentId, error)
        }
    }
    guard let program = params.command.first else {
        throw CodexErr.io("command args are empty")
    }
    let args = Array(params.command.dropFirst())
    let cwd = PathUri.fromAbsPath(params.cwd)
    let sandboxPolicyCwd = PathUri.fromAbsPath(sandboxCwd)
    let manager = SandboxManager()
    let command = SandboxCommand(
        program: program,
        args: args,
        cwd: cwd,
        env: env
    )
    let transformed: SandboxExecRequest
    do {
        transformed = try manager.transform(
            SandboxTransformRequest(
                command: command,
                permissions: permissionProfile,
                sandbox: sandboxType,
                enforceManagedNetwork: enforceManagedNetwork,
                environmentId: params.networkEnvironmentId,
                network: params.network,
                sandboxPolicyCwd: sandboxPolicyCwd,
                sandboxExe: codexLinuxSandboxExe ?? codexSelfExe,
                useLegacyLandlock: useLegacyLandlock,
                windowsSandboxLevel: params.windowsSandboxLevel
            )
        )
    } catch let error as SandboxTransformError {
        throw CodexErr(error)
    }
    let windowsRoots: [AbsolutePathBuf]
    if sandboxType == .windowsRestrictedToken {
        if windowsSandboxWorkspaceRoots.isEmpty {
            windowsRoots = [sandboxCwd]
        } else {
            windowsRoots = try windowsSandboxWorkspaceRoots.map { try $0.toAbsPath() }
        }
    } else {
        windowsRoots = []
    }
    return try ExecRequest.fromSandboxExecRequest(
        transformed,
        options: ExecOptions(expiration: params.expiration, capturePolicy: params.capturePolicy),
        windowsSandboxWorkspaceRoots: windowsRoots
    )
}

func executeExecRequest(
    _ execRequest: ExecRequest,
    stdoutStream: StdoutStream?,
    afterSpawn: (() -> Void)?
) async -> CodexResult<ExecToolCallOutput> {
    let cwd: AbsolutePathBuf
    let windowsSandboxPolicyCwd: AbsolutePathBuf
    do {
        cwd = try execRequest.cwd.toAbsPath()
        windowsSandboxPolicyCwd = try execRequest.windowsSandboxPolicyCwd.toAbsPath()
    } catch {
        return .failure(.invalidRequest("invalid exec cwd: \(error)"))
    }
    let params = ExecParams(
        command: execRequest.command,
        cwd: cwd,
        expiration: execRequest.expiration,
        capturePolicy: execRequest.capturePolicy,
        env: execRequest.env,
        network: execRequest.network,
        networkEnvironmentId: execRequest.networkEnvironmentId,
        sandboxPermissions: .useDefault,
        windowsSandboxLevel: execRequest.windowsSandboxLevel,
        justification: nil,
        arg0: execRequest.arg0
    )
    let start = ContinuousClock.now
    let raw = await getRawOutputResult(
        params,
        networkSandboxPolicy: execRequest.permissionProfile.networkSandboxPolicy(),
        stdoutStream: stdoutStream,
        afterSpawn: afterSpawn,
        sandbox: execRequest.sandbox
    )
    let duration = start.duration(to: .now)
    _ = windowsSandboxPolicyCwd
    return finalizeExecResult(raw, sandboxType: execRequest.sandbox, duration: duration, capturePolicy: execRequest.capturePolicy)
}

private func getRawOutputResult(
    _ params: ExecParams,
    networkSandboxPolicy: NetworkSandboxPolicy,
    stdoutStream: StdoutStream?,
    afterSpawn: (() -> Void)?,
    sandbox: SandboxType
) async -> Result<RawExecToolCallOutput, CodexErr> {
    if sandbox == .windowsRestrictedToken {
        return .failure(.unsupportedOperation("Windows sandbox exec is unavailable on this platform"))
    }
    return await exec(params, networkSandboxPolicy: networkSandboxPolicy, stdoutStream: stdoutStream, afterSpawn: afterSpawn)
}

private struct RawExecToolCallOutput {
    var exitCode: Int32
    var unixSignal: Int32?
    var stdout: StreamOutput<Data>
    var stderr: StreamOutput<Data>
    var aggregatedOutput: StreamOutput<Data>
    var timedOut: Bool
}

private func finalizeExecResult(
    _ rawOutputResult: Result<RawExecToolCallOutput, CodexErr>,
    sandboxType: SandboxType,
    duration: Duration,
    capturePolicy: ExecCapturePolicy
) -> CodexResult<ExecToolCallOutput> {
    switch rawOutputResult {
    case .success(let raw):
        var timedOut = raw.timedOut
        if let signal = raw.unixSignal {
            if signal == TIMEOUT_CODE {
                timedOut = true
            } else {
                return .failure(.sandbox(.signal(signal)))
            }
        }
        var exitCode = raw.exitCode
        if timedOut {
            exitCode = EXEC_TIMEOUT_EXIT_CODE
        }
        let execOutput = ExecToolCallOutput(
            exitCode: exitCode,
            stdout: raw.stdout.fromUTF8Lossy(),
            stderr: raw.stderr.fromUTF8Lossy(),
            aggregatedOutput: raw.aggregatedOutput.fromUTF8Lossy(),
            duration: duration,
            timedOut: timedOut
        )
        if timedOut {
            return .failure(.sandbox(.timeout(output: execOutput)))
        }
        if isLikelySandboxDenied(sandboxType: sandboxType, execOutput: execOutput) {
            if capturePolicy != .sensitiveFullBuffer {
                _ = recordFilesystemSandboxViolation(sandboxType: sandboxType, execOutput: execOutput)
            }
            return .failure(.sandbox(.denied(output: execOutput, networkPolicyDecision: nil)))
        }
        return .success(execOutput)
    case .failure(let error):
        return .failure(error)
    }
}

private func appendCapped(_ dst: inout Data, _ src: Data, maxBytes: Int) {
    if dst.count >= maxBytes { return }
    let remaining = maxBytes - dst.count
    dst.append(src.prefix(remaining))
}

private func aggregateOutput(
    _ stdout: StreamOutput<Data>,
    _ stderr: StreamOutput<Data>,
    maxBytes: Int?
) -> StreamOutput<Data> {
    guard let maxBytes else {
        var aggregated = stdout.text
        aggregated.append(stderr.text)
        return StreamOutput(text: aggregated)
    }
    let total = stdout.text.count + stderr.text.count
    if total <= maxBytes {
        var aggregated = stdout.text
        aggregated.append(stderr.text)
        return StreamOutput(text: aggregated)
    }
    let wantStdout = min(stdout.text.count, maxBytes / 3)
    let stderrTake = min(stderr.text.count, maxBytes - wantStdout)
    let remaining = maxBytes - wantStdout - stderrTake
    let stdoutTake = wantStdout + min(remaining, max(0, stdout.text.count - wantStdout))
    var aggregated = stdout.text.prefix(stdoutTake)
    aggregated.append(stderr.text.prefix(stderrTake))
    return StreamOutput(text: Data(aggregated))
}

private func exec(
    _ params: ExecParams,
    networkSandboxPolicy: NetworkSandboxPolicy,
    stdoutStream: StdoutStream?,
    afterSpawn: (() -> Void)?
) async -> Result<RawExecToolCallOutput, CodexErr> {
    var env = params.env
    if let network = params.network {
        do {
            try network.applyToEnvForOptionalEnvironment(
                &env,
                environmentId: params.networkEnvironmentId
            )
        } catch {
            return .failure(networkProxyEnvironmentError(params.networkEnvironmentId, error))
        }
    }
    guard let program = params.command.first else {
        return .failure(.io("command args are empty"))
    }
    let args = Array(params.command.dropFirst())
    let spawned: SpawnedProcess
    do {
        spawned = try await spawnChild(
            SpawnChildRequest(
                program: program,
                args: args,
                arg0: params.arg0,
                cwd: params.cwd,
                networkSandboxPolicy: networkSandboxPolicy,
                network: nil,
                stdioPolicy: .redirectForShellTool,
                env: env
            )
        )
    } catch {
        return .failure(.io(String(describing: error)))
    }
    afterSpawn?()
    return await consumeOutput(
        spawned,
        expiration: params.expiration,
        capturePolicy: params.capturePolicy,
        stdoutStream: stdoutStream
    )
}

private func consumeOutput(
    _ spawned: SpawnedProcess,
    expiration: ExecExpiration,
    capturePolicy: ExecCapturePolicy,
    stdoutStream: StdoutStream?
) async -> Result<RawExecToolCallOutput, CodexErr> {
    let retainedBytesCap = capturePolicy.retainedBytesCap()
    let stdoutTask = Task {
        await readOutput(spawned.stdout, stream: stdoutStream, isStderr: false, maxBytes: retainedBytesCap)
    }
    let stderrTask = Task {
        await readOutput(spawned.stderr, stream: stdoutStream, isStderr: true, maxBytes: retainedBytesCap)
    }

    enum WaitKind {
        case exit(Int32)
        case expiration(ExecExpirationOutcome)
    }

    let expirationTask: Task<ExecExpirationOutcome, Never>? = capturePolicy.usesExpiration()
        ? Task { await expiration.waitWithOutcome() }
        : nil

    let winner: WaitKind = await withTaskGroup(of: WaitKind.self) { group in
        group.addTask { .exit(await spawned.exit.value) }
        if let expirationTask {
            group.addTask { .expiration(await expirationTask.value) }
        }
        let first = await group.next() ?? .exit(-1)
        group.cancelAll()
        return first
    }

    var exitCode: Int32
    var unixSignal: Int32?
    var timedOut = false
    let processGroupId = spawned.processGroupId ?? spawned.session.processGroupId()

    switch winner {
    case .exit(let code):
        if code >= EXIT_CODE_SIGNAL_BASE {
            unixSignal = code - EXIT_CODE_SIGNAL_BASE
        }
        exitCode = code
    case .expiration(.timedOut):
        if let processGroupId {
            try? killChildProcessGroup(processGroupId)
        }
        spawned.session.requestTerminate()
        timedOut = true
        unixSignal = TIMEOUT_CODE
        exitCode = EXIT_CODE_SIGNAL_BASE + TIMEOUT_CODE
    case .expiration(.cancelled):
        var shouldEscalate = false
        if let processGroupId {
            shouldEscalate = (try? terminateProcessGroup(processGroupId)) ?? false
        }
        let finished = await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await spawned.exit.value }
            group.addTask {
                try? await Task.sleep(for: CANCELLATION_TERMINATION_GRACE_PERIOD)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if finished == nil, let processGroupId {
            try? killProcessGroup(processGroupId)
            spawned.session.requestTerminate()
        } else if shouldEscalate, let processGroupId {
            try? killProcessGroup(processGroupId)
        }
        _ = finished
        exitCode = 1
        unixSignal = nil
    }

    let drainTimeout = capturePolicy.ioDrainTimeout()
    let (stdout, stderr) = await drainOutputs(
        stdoutTask: stdoutTask,
        stderrTask: stderrTask,
        timeout: drainTimeout
    )
    expirationTask?.cancel()
    let aggregated = aggregateOutput(stdout, stderr, maxBytes: retainedBytesCap)
    return .success(
        RawExecToolCallOutput(
            exitCode: exitCode,
            unixSignal: unixSignal,
            stdout: stdout,
            stderr: stderr,
            aggregatedOutput: aggregated,
            timedOut: timedOut
        )
    )
}

private func drainOutputs(
    stdoutTask: Task<StreamOutput<Data>, Never>,
    stderrTask: Task<StreamOutput<Data>, Never>,
    timeout: Duration
) async -> (StreamOutput<Data>, StreamOutput<Data>) {
    let empty = StreamOutput(text: Data())
    let finished = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            _ = await stdoutTask.value
            _ = await stderrTask.value
            return true
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    if finished {
        return await (stdoutTask.value, stderrTask.value)
    }
    stdoutTask.cancel()
    stderrTask.cancel()
    return (empty, empty)
}

private func readOutput(
    _ stream: AsyncStream<Data>,
    stream stdoutStream: StdoutStream?,
    isStderr: Bool,
    maxBytes: Int?
) async -> StreamOutput<Data> {
    var buf = Data()
    buf.reserveCapacity(maxBytes.map { min(AGGREGATE_BUFFER_INITIAL_CAPACITY, $0) } ?? AGGREGATE_BUFFER_INITIAL_CAPACITY)
    var emittedDeltas = 0
    for await chunk in stream {
        if let stdoutStream, emittedDeltas < MAX_EXEC_OUTPUT_DELTAS_PER_CALL {
            stdoutStream.emit(
                ExecCommandOutputDeltaEvent(
                    callId: stdoutStream.callId,
                    stream: isStderr ? .stderr : .stdout,
                    chunk: chunk
                )
            )
            emittedDeltas += 1
        }
        if let maxBytes {
            appendCapped(&buf, chunk, maxBytes: maxBytes)
        } else {
            buf.append(chunk)
        }
    }
    return StreamOutput(text: buf)
}
