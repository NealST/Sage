//
//  command_runner.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/command_runner.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Foundation.Process stands in for tokio::process. Child `pre_exec`
//  detach-from-tty is omitted; timeout kills the spawned pid only so we
//  do not signal the test-runner process group.
//

import CodexProtocol
import CodexUtils
import Darwin
import Foundation

let maxConcurrentAsyncHooks = 8

/// Unbounded mailbox for completed async hook events.
public final class HookCompletedMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var buffer: [HookCompletedEvent] = []

    public init() {}

    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    public func trySend(_ event: HookCompletedEvent) {
        lock.lock()
        defer { lock.unlock() }
        if !closed {
            buffer.append(event)
        }
    }

    public func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }

    public func drain() -> [HookCompletedEvent] {
        lock.lock()
        defer { lock.unlock() }
        let items = buffer
        buffer.removeAll()
        return items
    }
}

/// Owns command execution and bounded asynchronous work for one session.
public final class CommandHookRuntime: @unchecked Sendable {
    public var shell: CommandShell
    public var environment: [(String, String)]
    public let resultSender: HookCompletedMailbox
    public let outputSpiller: HookOutputSpiller
    private let state: CommandHookRuntimeState

    public init(
        shell: CommandShell,
        environment: [(String, String)] = [],
        threadId: ThreadId = ThreadId(),
        resultSender: HookCompletedMailbox = HookCompletedMailbox()
    ) {
        self.shell = shell
        self.environment = environment
        self.resultSender = resultSender
        self.outputSpiller = HookOutputSpiller(threadId: threadId)
        self.state = CommandHookRuntimeState()
    }

    init(
        shell: CommandShell,
        environment: [(String, String)],
        resultSender: HookCompletedMailbox,
        outputSpiller: HookOutputSpiller,
        state: CommandHookRuntimeState
    ) {
        self.shell = shell
        self.environment = environment
        self.resultSender = resultSender
        self.outputSpiller = outputSpiller
        self.state = state
    }

    public func reconfigured(_ shell: CommandShell) -> CommandHookRuntime {
        CommandHookRuntime(
            shell: shell,
            environment: environment,
            resultSender: resultSender,
            outputSpiller: outputSpiller,
            state: state
        )
    }

    public func scheduleAsyncHook<T: Sendable>(
        handler: ConfiguredHandler,
        inputJSON: String,
        cwd: String,
        turnId: String?,
        parse: @escaping @Sendable (ConfiguredHandler, HandlerRunResult, String?) -> ParsedHandler<T>
    ) {
        if resultSender.isClosed { return }
        let runtime = self
        scheduleAsyncTask {
            let result: HandlerRunResult
            switch handler.kind {
            case .command(let command, let env, _):
                result = await runCommand(
                    runtime: runtime,
                    handler: handler,
                    command: command,
                    env: env,
                    inputJSON: inputJSON,
                    cwd: cwd
                )
            case .mcpTool:
                return
            }
            var hookResult = parse(handler, result, turnId).completed
            var entries: [HookOutputEntry] = []
            var warnings: [HookOutputEntry] = []
            let original = hookResult.run.entries
            hookResult.run.entries = []
            for entry in original {
                switch entry.kind {
                case .context:
                    let spilled = await runtime.outputSpiller.maybeSpillAdditionalContexts([
                        AdditionalContext(text: entry.text, limit: handler.additionalContextLimit)
                    ])
                    if let text = spilled.first {
                        entries.append(HookOutputEntry(kind: .context, text: text))
                    }
                case .warning:
                    warnings.append(entry)
                case .error:
                    entries.append(entry)
                case .stop, .feedback:
                    break
                }
            }
            entries.append(contentsOf: warnings)
            hookResult.run.entries = entries
            runtime.resultSender.trySend(hookResult)
        }
    }

    public func scheduleAsyncTask(_ work: @escaping @Sendable () async -> Void) {
        if state.isClosed { return }
        let limiter = state.limiter
        let task = Task {
            await limiter.acquire()
            defer { Task { await limiter.release() } }
            await work()
        }
        state.add(task)
    }

    public func shutdown() async {
        state.close()
        for task in state.takeTasks() {
            task.cancel()
            _ = await task.result
        }
        resultSender.close()
    }
}

func runCommand(
    runtime: CommandHookRuntime,
    handler: ConfiguredHandler,
    command: String,
    env: [String: String],
    inputJSON: String,
    cwd: String
) async -> HandlerRunResult {
    let startedAt = Int64(Date().timeIntervalSince1970)
    let started = ContinuousClock.now
    let spec = buildCommand(
        shell: runtime.shell,
        commandLine: command,
        environment: runtime.environment,
        env: env
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: spec.program)
    process.arguments = spec.arguments
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    process.environment = spec.environment
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return finishCommandRun(
            startedAt: startedAt,
            started: started,
            completion: CommandRunCompletion(
                exitCode: nil, stdout: "", stderr: "",
                error: error.localizedDescription, outcome: "spawn_error"
            )
        )
    }

    let writeTask = Task {
        do {
            stdin.fileHandleForWriting.write(Data(inputJSON.utf8))
            try stdin.fileHandleForWriting.close()
        } catch {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == Int(EPIPE) {
                return
            }
        }
    }
    async let stdoutText = readPipe(stdout)
    async let stderrText = readPipe(stderr)
    let finished = await waitUntilExit(process, seconds: handler.timeoutSec)
    if !finished {
        writeTask.cancel()
        process.terminate()
        try? await Task.sleep(for: .milliseconds(50))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        _ = await writeTask.result
        _ = await (stdoutText, stderrText)
        return finishCommandRun(
            startedAt: startedAt,
            started: started,
            completion: CommandRunCompletion(
                exitCode: nil, stdout: "", stderr: "",
                error: "hook timed out after \(handler.timeoutSec)s",
                outcome: "timeout"
            )
        )
    }
    _ = await writeTask.result
    return finishCommandRun(
        startedAt: startedAt,
        started: started,
        completion: CommandRunCompletion(
            exitCode: process.terminationStatus,
            stdout: await stdoutText,
            stderr: await stderrText,
            error: nil,
            outcome: "completed"
        )
    )
}

struct HookProcessSpec: Equatable {
    var program: String
    var arguments: [String]
    var environment: [String: String]
}

func buildCommand(
    shell: CommandShell,
    commandLine: String,
    environment: [(String, String)],
    env: [String: String]
) -> HookProcessSpec {
    let program: String
    let arguments: [String]
    if shell.program.isEmpty {
        program = environment.first { $0.0 == "SHELL" }?.1 ?? "/bin/sh"
        arguments = ["-lc", commandLine]
    } else {
        program = shell.program
        arguments = shell.args + [commandLine]
    }
    var merged: [String: String] = [:]
    for (key, value) in environment {
        merged[key] = value
    }
    for (key, value) in env {
        merged[key] = value
    }
    scrubNonInheritableEnvVars(&merged)
    return HookProcessSpec(program: program, arguments: arguments, environment: merged)
}

private struct CommandRunCompletion {
    var exitCode: Int32?
    var stdout: String
    var stderr: String
    var error: String?
    var outcome: String
}

private func finishCommandRun(
    startedAt: Int64,
    started: ContinuousClock.Instant,
    completion: CommandRunCompletion
) -> HandlerRunResult {
    let duration = started.duration(to: .now)
    let durationMs = Int64(duration.components.seconds * 1000)
        + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
    return HandlerRunResult(
        startedAt: startedAt,
        completedAt: Int64(Date().timeIntervalSince1970),
        durationMs: max(durationMs, 0),
        exitCode: completion.exitCode,
        stdout: completion.stdout,
        stderr: completion.stderr,
        error: completion.error
    )
}

private func waitUntilExit(_ process: Process, seconds: UInt64) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while process.isRunning {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

private func readPipe(_ pipe: Pipe) async -> String {
    await Task.detached {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }.value
}

final class CommandHookRuntimeState: @unchecked Sendable {
    let limiter = AsyncHookLimiter(limit: maxConcurrentAsyncHooks)
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []
    private var closed = false

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func add(_ task: Task<Void, Never>) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    func takeTasks() -> [Task<Void, Never>] {
        lock.lock()
        defer { lock.unlock() }
        let items = tasks
        tasks.removeAll()
        return items
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        Task { await limiter.close() }
    }
}

actor AsyncHookLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var closed = false

    init(limit: Int) {
        available = limit
    }

    func acquire() async {
        if closed { return }
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if closed { return }
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            available += 1
        }
    }

    func close() {
        closed = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
