//
//  delegate.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/delegate.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Per-cell dispatch gates are faithful. Nested tool dispatch waits on
//  Session / ToolCallRuntime.
//

import CodexProtocol
import Foundation
import os

final class CodeModeDispatchBroker: @unchecked Sendable {
    private struct CellDispatchGate {
        var ready: Bool
        var originatingCallId: String?
    }

    private let lock = OSAllocatedUnfairLock(initialState: [String: CellDispatchGate]())

    func markCellReadyForDispatch(cellId: String, originatingCallId: String?) {
        lock.withLock { gates in
            var gate = gates[cellId] ?? CellDispatchGate(ready: false, originatingCallId: nil)
            gate.originatingCallId = originatingCallId
            gate.ready = true
            gates[cellId] = gate
        }
    }

    func cellOriginatingCall(_ cellId: String) -> String? {
        lock.withLock { $0[cellId]?.originatingCallId }
    }

    func isCellReadyForDispatch(_ cellId: String) -> Bool {
        lock.withLock { $0[cellId]?.ready ?? false }
    }

    func closeCell(_ cellId: String) {
        lock.withLock { $0.removeValue(forKey: cellId) }
    }
}

struct CodeModeCellDelegate {
    var broker: CodeModeDispatchBroker
    var cellId: String
}
