//
//  spawn_guard.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/spawn_guard.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Cancellation cleanup removes the live CodexThread when a ThreadManager
//  is attached. Agent-graph-store Closed writes stay skipped.
//

import CodexProtocol
import Foundation

public final class PendingSpawn: @unchecked Sendable {
    public private(set) var child: ThreadId?
    public private(set) var armed: Bool
    weak var manager: ThreadManager?
    private var edgeWritePending: Bool

    public init(child: ThreadId, manager: ThreadManager? = nil) {
        self.child = child
        self.armed = true
        self.manager = manager
        self.edgeWritePending = false
    }

    public func markEdgeWritePending() {
        edgeWritePending = true
    }

    public func waitForEdge() async {
        edgeWritePending = false
    }

    public func disarm() {
        child = nil
        armed = false
        edgeWritePending = false
    }

    deinit {
        guard armed, let child else { return }
        let manager = manager
        Task {
            if let manager, let thread = await manager.removeThread(child) {
                try? await thread.shutdownAndWait()
            }
        }
    }
}
