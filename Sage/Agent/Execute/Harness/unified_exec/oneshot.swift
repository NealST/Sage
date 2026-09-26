//
//  oneshot.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/oneshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session-free completion wait. The rust path talks to Session.services;
//  Sage waits on the local process handle and cancellation token.
//

import CodexAsyncUtils
import CodexProtocol
import Foundation

struct Completion {
    var timeout: Duration
    var timedOut = false
    var process: UnifiedExecProcess?
}

struct OneshotExecResult {
    var exitCode: Int32?
    var timedOut: Bool
    var output: Data
    var processId: Int32?
}

extension UnifiedExecProcessManager {
    func execCommandToCompletion(
        request: ExecCommandRequest,
        context: UnifiedExecContext,
        timeout: Duration,
        sandboxType: SandboxType,
        env: [String: String]
    ) async throws -> OneshotExecResult {
        let child = context.cancellationToken.childToken()
        let processId = request.processId
        var completion = Completion(timeout: timeout)
        do {
            let entry = try await spawnLocal(
                request: request,
                sandboxType: sandboxType,
                env: env,
                context: UnifiedExecContext(cancellationToken: child, callId: context.callId)
            )
            completion.process = entry.process
            let result = try await waitForCompletion(
                process: entry.process,
                timeout: timeout,
                cancellation: child,
                completion: &completion
            )
            if completion.timedOut {
                releaseProcessId(processId)
            }
            return result
        } catch {
            releaseProcessId(processId)
            throw error
        }
    }

    private func waitForCompletion(
        process: UnifiedExecProcess,
        timeout: Duration,
        cancellation: CancellationToken,
        completion: inout Completion
    ) async throws -> OneshotExecResult {
        enum Outcome {
            case cancelled
            case timedOut
            case exited
        }
        let outcome: Outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                await cancellation.waitForCancellation()
                return .cancelled
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            group.addTask {
                while !process.hasExited() {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                return .exited
            }
            let first = await group.next() ?? .exited
            group.cancelAll()
            return first
        }
        switch outcome {
        case .cancelled:
            try await process.terminateConfirmed()
            throw UnifiedExecError.processFailed("command cancelled")
        case .timedOut:
            completion.timedOut = true
            process.markTimedOut()
            try await process.terminateConfirmed()
            return OneshotExecResult(
                exitCode: 124,
                timedOut: true,
                output: process.snapshotOutput(),
                processId: nil
            )
        case .exited:
            try process.checkForSandboxDenial()
            return OneshotExecResult(
                exitCode: process.exitCode(),
                timedOut: false,
                output: process.snapshotOutput(),
                processId: nil
            )
        }
    }
}
