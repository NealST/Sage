//
//  mcp_refresh.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp_refresh.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  One dirty bit plus a single in-flight permit. `claim` takes the bit.
//  A closed gate fails the next acquire; the refresh already holding the
//  permit still finishes.
//

import Foundation

final class McpRefresh: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false
    private var locked = false
    private var closed = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    init() {}

    func invalidate() {
        lock.lock()
        pending = true
        lock.unlock()
    }

    func claim() -> Bool {
        lock.lock()
        let claimed = pending
        pending = false
        lock.unlock()
        return claimed
    }

    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    /// `false` when the gate is closed.
    func acquire() async -> Bool {
        lock.lock()
        if closed {
            lock.unlock()
            return false
        }
        if !locked {
            locked = true
            lock.unlock()
            return true
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        if closed {
            locked = false
            let receivers = waiters
            waiters = []
            lock.unlock()
            for waiter in receivers {
                waiter.resume(returning: false)
            }
            return
        }
        if waiters.isEmpty {
            locked = false
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        lock.unlock()
        waiter.resume(returning: true)
    }

    func close() {
        lock.lock()
        closed = true
        let receivers = waiters
        waiters = []
        lock.unlock()
        for waiter in receivers {
            waiter.resume(returning: false)
        }
    }
}
