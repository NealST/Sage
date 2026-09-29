//
//  spawn_guard.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/spawn_guard.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Cancellation cleanup closes over ThreadManagerState / agent graph store.
//  The guard tracks a child id so later wiring can drop it on cancel.
//

import CodexProtocol
import Foundation

public final class PendingSpawn: @unchecked Sendable {
    public private(set) var child: ThreadId?
    public private(set) var armed: Bool

    public init(child: ThreadId) {
        self.child = child
        self.armed = true
    }

    public func waitForEdge() async throws {
        throw CodexErr.unsupportedOperation(
            "PendingSpawn.wait_for_edge waits on ThreadManager / graph-store write"
        )
    }

    public func disarm() {
        child = nil
        armed = false
    }

    deinit {
        if armed, child != nil {
            // ThreadManager cleanup waits on Session.
        }
    }
}
