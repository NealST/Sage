//
//  parallel.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/parallel.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Codex admits tools through an RWLock: parallel-capable calls take a
//  read lock, serial calls take a write lock. Sage already schedules by
//  wave (`ToolBatchWave`). This file owns the policy that wave uses —
//  observations may share a wave; apply_patch / shell / MCP / todo /
//  explore / skill mutations / Mac mutations stay serial — and a
//  generic runner for isolated batches (Explore).
//

import Foundation

enum ParallelToolRuntime {
    /// Names that stay serial even if they look like observations.
    static let alwaysSerial: Set<String> = [
        "apply_patch",
        "run_shell_command",
        "write_text_file",
        "manage_todo_list",
        ExploreSubagentTool.name,
        "save_skill",
        "run_skill_script",
    ]

    /// Codex `tool_supports_parallel`. Reads and context loads share a wave.
    static func supportsParallel(_ toolName: String) -> Bool {
        if alwaysSerial.contains(toolName) { return false }
        if toolName.hasPrefix("mcp__") { return false }
        if MCPToolGroupTool.isGroupTool(toolName) { return false }
        return ToolDefinition.observationToolNames.contains(toolName)
    }

    static func partition(_ toolNames: [String]) -> [ToolBatchWave] {
        var waves: [ToolBatchWave] = []
        var pending: [Int] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            if pending.count == 1 {
                waves.append(.serial(pending[0]))
            } else {
                waves.append(.parallel(pending))
            }
            pending = []
        }

        for index in toolNames.indices {
            if supportsParallel(toolNames[index]) {
                pending.append(index)
            } else {
                flushPending()
                waves.append(.serial(index))
            }
        }
        flushPending()
        return waves
    }

    /// Run one isolated batch. Parallel-capable names share a read lock;
    /// serial names take the write lock and wait for in-flight reads.
    /// Results stay in call order. A thrown error cancels later waves.
    @MainActor
    static func run(
        calls: [ToolCallProposal],
        invoke: @escaping @MainActor (ToolCallProposal) async throws -> String
    ) async throws -> [String] {
        let gate = ParallelAdmission()
        var results = [String?](repeating: nil, count: calls.count)
        for wave in partition(calls.map(\.name)) {
            try Task.checkCancellation()
            switch wave {
            case .serial(let index):
                results[index] = try await gate.write {
                    try await invoke(calls[index])
                }

            case .parallel(let indices):
                let tasks = indices.map { index in
                    Task { @MainActor in
                        try await gate.read {
                            try await invoke(calls[index])
                        }
                    }
                }
                do {
                    try await withTaskCancellationHandler {
                        for (index, task) in zip(indices, tasks) {
                            results[index] = try await task.value
                        }
                    } onCancel: {
                        for task in tasks { task.cancel() }
                    }
                } catch {
                    for task in tasks { task.cancel() }
                    throw error
                }
            }
        }
        return results.map { $0! }
    }
}

/// Codex `parallel_execution` RwLock: readers overlap, a writer waits for them
/// and then excludes everyone else.
actor ParallelAdmission {
    private var readers = 0
    private var writer = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func read<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
        await acquire(exclusive: false)
        do {
            let value = try await body()
            release(exclusive: false)
            return value
        } catch {
            release(exclusive: false)
            throw error
        }
    }

    func write<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
        await acquire(exclusive: true)
        do {
            let value = try await body()
            release(exclusive: true)
            return value
        } catch {
            release(exclusive: true)
            throw error
        }
    }

    private func acquire(exclusive: Bool) async {
        while !canEnter(exclusive: exclusive) {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        if exclusive {
            writer = true
        } else {
            readers += 1
        }
    }

    private func release(exclusive: Bool) {
        if exclusive {
            writer = false
        } else {
            readers = max(0, readers - 1)
        }
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    private func canEnter(exclusive: Bool) -> Bool {
        if writer { return false }
        if exclusive { return readers == 0 }
        return true
    }
}
