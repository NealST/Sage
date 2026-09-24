//
//  cache_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/cache/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `lru::LruCache` maps to the embedded `LruCache` below (same get/put/pop/
//  clear semantics, get promotes to most-recently-used). `tokio::sync::Mutex`
//  + `block_in_place` map to `NSLock`: the upstream type is a no-op outside a
//  Tokio runtime (`lock_if_runtime` returns None); Swift has no runtime check,
//  so the cache is always active. The `disabled_without_runtime` upstream test
//  is tokio-specific and not ported.
//
//  `V: Clone` bounds are dropped: Swift value types copy on return, and for
//  reference types the port shares the reference (documented difference).
//
//  `sha1::Sha1` maps to CryptoKit's `Insecure.SHA1`.
//
//  R4a: upstream `lib.rs` maps to `cache_lib.swift` because
//  `utils/absolute-path/src/lib.swift` claimed the basename first (plan §5.1).
//

import CryptoKit
import Foundation

/// `lru::LruCache` — capacity-bounded, ordered by recency of `get`/`put`.
public final class LruCache<Key: Hashable, Value> {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private var nodes: [Key: Node] = [:]
    /// Most-recently-used end.
    private var head: Node?
    /// Least-recently-used end (eviction candidate).
    private var tail: Node?
    private let capacity: Int

    /// `LruCache::new` (`NonZeroUsize` capacity).
    public init(capacity: Int) {
        precondition(capacity > 0, "LruCache capacity must be non-zero")
        self.capacity = capacity
    }

    private init(unbounded: ()) {
        self.capacity = Int.max
    }

    /// `LruCache::unbounded`.
    public static func unbounded() -> LruCache<Key, Value> {
        LruCache(unbounded: ())
    }

    /// `LruCache::len`.
    public var count: Int {
        nodes.count
    }

    /// `LruCache::get` — returns the value and promotes the entry.
    @discardableResult
    public func get(_ key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        promote(node)
        return node.value
    }

    /// `LruCache::put` — inserts or replaces, returning the replaced value.
    @discardableResult
    public func put(_ key: Key, _ value: Value) -> Value? {
        if let node = nodes[key] {
            let old = node.value
            node.value = value
            promote(node)
            return old
        }
        let node = Node(key: key, value: value)
        nodes[key] = node
        attach(node)
        if nodes.count > capacity, let tail {
            detach(tail)
            nodes[tail.key] = nil
        }
        return nil
    }

    /// `LruCache::pop` — removes the entry, returning it.
    @discardableResult
    public func pop(_ key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        detach(node)
        nodes[key] = nil
        return node.value
    }

    /// `LruCache::clear`.
    public func clear() {
        nodes.removeAll()
        head = nil
        tail = nil
    }

    private func promote(_ node: Node) {
        guard node !== head else { return }
        detach(node)
        attach(node)
    }

    private func attach(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func detach(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node { head = node.next }
        if tail === node { tail = node.prev }
        node.prev = nil
        node.next = nil
    }
}

/// A minimal LRU cache protected by a Tokio mutex (upstream) — an `NSLock`
/// here. Always active (see header).
public final class BlockingLruCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var inner: LruCache<Key, Value>

    /// Creates a cache with the provided non-zero capacity.
    public init(capacity: Int) {
        inner = LruCache(capacity: capacity)
    }

    /// Returns the cached value for `key`, or computes and inserts it.
    public func getOrInsertWith(_ key: Key, _ value: () -> Value) -> Value {
        lock.withLock {
            if let cached = inner.get(key) {
                return cached
            }
            let computed = value()
            // Insert to keep ownership in the cache.
            inner.put(key, computed)
            return computed
        }
    }

    /// Like `getOrInsertWith`, but the value factory may fail.
    public func getOrTryInsertWith(_ key: Key, _ value: () throws -> Value) throws -> Value {
        try lock.withLock {
            if let cached = inner.get(key) {
                return cached
            }
            let computed = try value()
            inner.put(key, computed)
            return computed
        }
    }

    /// Builds a cache if `capacity` is non-zero, returning `nil` otherwise
    /// (`NonZeroUsize::new(capacity).map(Self::new)`).
    public static func tryWithCapacity(_ capacity: Int) -> BlockingLruCache<Key, Value>? {
        capacity > 0 ? BlockingLruCache(capacity: capacity) : nil
    }

    /// Returns the cached value corresponding to `key`, if present.
    public func get(_ key: Key) -> Value? {
        lock.withLock { inner.get(key) }
    }

    /// Inserts `value` for `key`, returning the previous entry if it existed.
    @discardableResult
    public func insert(_ key: Key, _ value: Value) -> Value? {
        lock.withLock { inner.put(key, value) }
    }

    /// Removes the entry for `key` if it exists, returning it.
    @discardableResult
    public func remove(_ key: Key) -> Value? {
        lock.withLock { inner.pop(key) }
    }

    /// Clears all entries from the cache.
    public func clear() {
        lock.withLock { inner.clear() }
    }

    /// Executes `callback` with a mutable reference to the underlying cache.
    public func withMut<R>(_ callback: (inout LruCache<Key, Value>) -> R) -> R {
        lock.withLock { callback(&inner) }
    }

    /// `blocking_lock` — direct cache access under the lock. Upstream returns
    /// `None` outside a Tokio runtime and yields a `MutexGuard`; Swift locks
    /// cannot hand out a guard, so this takes a callback and never fails.
    public func blockingLock<R>(_ callback: (inout LruCache<Key, Value>) -> R) -> R? {
        lock.withLock { callback(&inner) }
    }
}

/// Computes the SHA-1 digest of `bytes`.
///
/// Useful for content-based cache keys when you want to avoid staleness
/// caused by path-only keys. (Upstream returns `[u8; 20]`.)
public func sha1Digest(_ bytes: [UInt8]) -> [UInt8] {
    Array(Insecure.SHA1.hash(data: Data(bytes)))
}
