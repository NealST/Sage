//
//  residency.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/residency.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Slot accounting and LRU touch are faithful. Eviction of live threads
//  waits on ThreadManager / Session.
//

import CodexProtocol
import Foundation
import os

public func isV2ResidentSessionSource(_ sessionSource: SessionSource) -> Bool {
    if case .subAgent = sessionSource { return true }
    return false
}

public final class V2Residency: @unchecked Sendable {
    private struct State {
        var residents: [ThreadId] = []
        var pendingSlots: Int = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func reserveSlot(capacity: Int) throws -> V2ResidencySlot {
        try lock.withLock { state in
            if state.residents.count + state.pendingSlots >= capacity {
                throw CodexErr.agentLimitReached(maxThreads: capacity)
            }
            state.pendingSlots += 1
        }
        return V2ResidencySlot(residency: self)
    }

    public func touch(_ threadId: ThreadId) {
        lock.withLock { state in
            touchResident(&state.residents, threadId)
        }
    }

    public func remove(_ threadId: ThreadId) {
        lock.withLock { state in
            state.residents.removeAll { $0 == threadId }
        }
    }

    func commitSlot(_ threadId: ThreadId) {
        lock.withLock { state in
            if state.pendingSlots > 0 { state.pendingSlots -= 1 }
            touchResident(&state.residents, threadId)
        }
    }

    func releasePendingSlot() {
        lock.withLock { state in
            if state.pendingSlots > 0 { state.pendingSlots -= 1 }
        }
    }

    public func reserveV2ResidencySlot(capacity: Int) throws -> V2ResidencySlot {
        try reserveSlot(capacity: capacity)
    }
}

public final class V2ResidencySlot {
    private let residency: V2Residency
    private var active: Bool

    init(residency: V2Residency) {
        self.residency = residency
        self.active = true
    }

    deinit {
        if active {
            residency.releasePendingSlot()
        }
    }

    public func commit(_ threadId: ThreadId) {
        residency.commitSlot(threadId)
        active = false
    }
}

func touchResident(_ residents: inout [ThreadId], _ threadId: ThreadId) {
    residents.removeAll { $0 == threadId }
    residents.append(threadId)
}

extension LocalAgentControl {
    public func reserveV2ResidencySlot(capacity: Int) throws -> V2ResidencySlot {
        try runtime.residency.reserveSlot(capacity: capacity)
    }
}
