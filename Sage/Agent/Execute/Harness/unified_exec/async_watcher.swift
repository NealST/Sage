//
//  async_watcher.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/async_watcher.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session event emission is replaced by `UnifiedExecEventSink`. The
//  trailing-output grace period and per-delta byte cap match upstream.
//

import Foundation

let TRAILING_OUTPUT_GRACE = Duration.milliseconds(100)
let UNIFIED_EXEC_OUTPUT_DELTA_MAX_BYTES = 8192

protocol UnifiedExecEventSink: AnyObject {
    func emitOutputDelta(callId: String, chunk: Data)
    func emitExecEnd(callId: String, exitCode: Int32?, output: Data, timedOut: Bool)
    func emitExecFailed(callId: String, message: String)
}

func startStreamingOutput(
    process: UnifiedExecProcess,
    callId: String,
    sink: UnifiedExecEventSink
) {
    var remaining = MAX_EXEC_OUTPUT_DELTAS_PER_CALL
    process.subscribeOutput { chunk in
        guard remaining > 0 else { return }
        remaining -= 1
        var offset = 0
        let bytes = Array(chunk)
        while offset < bytes.count {
            let end = min(offset + UNIFIED_EXEC_OUTPUT_DELTA_MAX_BYTES, bytes.count)
            sink.emitOutputDelta(callId: callId, chunk: Data(bytes[offset..<end]))
            offset = end
        }
    }
}

func spawnExitWatcher(
    process: UnifiedExecProcess,
    callId: String,
    sink: UnifiedExecEventSink
) {
    let token = process.cancellationToken()
    Task {
        await token.waitForCancellation()
        try? await Task.sleep(for: TRAILING_OUTPUT_GRACE)
        if let message = process.failureMessage() {
            sink.emitExecFailed(callId: callId, message: message)
            return
        }
        sink.emitExecEnd(
            callId: callId,
            exitCode: process.exitCode(),
            output: process.snapshotOutput(),
            timedOut: process.timedOut()
        )
    }
}
