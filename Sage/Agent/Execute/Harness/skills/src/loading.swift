//
//  loading.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/loading.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `SkillLoadFuture` is an async protocol method. Snapshot identity uses
//  `ObjectIdentifier` of the cache box.
//

import CodexProtocol
import CodexUtils
import Foundation

/// A skill document that could not be read, parsed, or validated.
public struct SkillError: Equatable, Sendable {
    public var path: AbsolutePathBuf
    public var message: String

    public init(path: AbsolutePathBuf, message: String) {
        self.path = path
        self.message = message
    }
}

/// Filesystem-independent metadata discovered beneath one canonical skill root.
public struct LoadedSkillRoot: Equatable, Sendable {
    public var root: AbsolutePathBuf
    public var skills: [SkillMetadata]
    public var skillDiscoveryPathByPath: [AbsolutePathBuf: AbsolutePathBuf]
    public var errors: [SkillError]
    public var isAgentPlugin: Bool

    public init(
        root: AbsolutePathBuf,
        skills: [SkillMetadata] = [],
        skillDiscoveryPathByPath: [AbsolutePathBuf: AbsolutePathBuf] = [:],
        errors: [SkillError] = [],
        isAgentPlugin: Bool = false
    ) {
        self.root = root
        self.skills = skills
        self.skillDiscoveryPathByPath = skillDiscoveryPathByPath
        self.errors = errors
        self.isAgentPlugin = isAgentPlugin
    }
}

/// Skills and errors produced by loading an ordered set of roots.
public struct LoadedSkills: Equatable, Sendable {
    public var skills: [SkillMetadata]
    public var errors: [SkillError]

    public init(skills: [SkillMetadata] = [], errors: [SkillError] = []) {
        self.skills = skills
        self.errors = errors
    }
}

/// Caches parsed roots without assigning ownership of the cache to a loader.
public protocol SkillRootSnapshotCache<Root>: AnyObject, Sendable {
    associatedtype Root
    func get(_ root: Root) -> LoadedSkillRoot?
    func insert(_ root: Root, snapshot: LoadedSkillRoot)
}

/// Shared access to one owner-managed collection of parsed skill roots.
public final class SkillRootSnapshots<Root>: @unchecked Sendable {
    private let cache: any SkillRootSnapshotCache<Root>

    public init<C: SkillRootSnapshotCache>(cache: C) where C.Root == Root {
        self.cache = cache
    }

    public func get(_ root: Root) -> LoadedSkillRoot? {
        cache.get(root)
    }

    public func insert(_ root: Root, snapshot: LoadedSkillRoot) {
        cache.insert(root, snapshot: snapshot)
    }
}

extension SkillRootSnapshots: Equatable {
    public static func == (lhs: SkillRootSnapshots<Root>, rhs: SkillRootSnapshots<Root>) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension SkillRootSnapshots: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// Inputs for loading roots while optionally reusing snapshots owned by the caller.
public struct SkillRootLoadRequest<Root> {
    public var roots: [Root]
    public var restrictionProduct: Product?
    public var snapshots: SkillRootSnapshots<Root>?

    public init(
        roots: [Root],
        restrictionProduct: Product? = nil,
        snapshots: SkillRootSnapshots<Root>? = nil
    ) {
        self.roots = roots
        self.restrictionProduct = restrictionProduct
        self.snapshots = snapshots
    }
}

/// Loads ordered skill roots without owning their source inventory or capability state.
public protocol SkillRootLoader<Root>: Sendable {
    associatedtype Root
    func loadRoots(_ request: SkillRootLoadRequest<Root>) async -> LoadedSkills
}
