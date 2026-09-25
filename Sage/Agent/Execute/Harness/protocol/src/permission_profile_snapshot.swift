//
//  permission_profile_snapshot.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permission_profile_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Trusted permission state keeps local and remote profile roots as
//  executor path URIs. Snapshot equality compares the stored URI spelling
//  without folding Windows case.
//

import CodexUtils
import Foundation

/// A profile-declared root, separate from turn-scoped runtime workspace roots.
public struct ProfileWorkspaceRoot: Sendable {
    private var uri: PathUri

    public init(_ uri: PathUri) {
        self.uri = uri
    }

    /// Borrow the resolved URI without projecting it onto the current host.
    public func asUri() -> PathUri { uri }
}

extension ProfileWorkspaceRoot {
    public init(_ path: AbsolutePathBuf) {
        self.init(PathUri.fromAbsPath(path))
    }
}

/// Trusted snapshot of a resolved permission profile.
public struct PermissionProfileSnapshot: Equatable, Sendable {
    private var permissionProfileValue: PermissionProfile
    private var activePermissionProfileValue: ActivePermissionProfile?
    private var profileWorkspaceRootsValue: [ProfileWorkspaceRoot]

    /// Create a snapshot with no active profile identity.
    public static func legacy(_ permissionProfile: PermissionProfile) -> PermissionProfileSnapshot {
        PermissionProfileSnapshot(
            permissionProfileValue: permissionProfile,
            activePermissionProfileValue: nil,
            profileWorkspaceRootsValue: []
        )
    }

    /// Create a snapshot for an already-resolved active profile.
    public static func active(
        _ permissionProfile: PermissionProfile,
        _ activePermissionProfile: ActivePermissionProfile
    ) -> PermissionProfileSnapshot {
        activeWithProfileWorkspaceRoots(
            permissionProfile,
            activePermissionProfile,
            []
        )
    }

    /// Create a snapshot for an active profile and its declared roots.
    public static func activeWithProfileWorkspaceRoots(
        _ permissionProfile: PermissionProfile,
        _ activePermissionProfile: ActivePermissionProfile,
        _ profileWorkspaceRoots: [ProfileWorkspaceRoot]
    ) -> PermissionProfileSnapshot {
        PermissionProfileSnapshot(
            permissionProfileValue: permissionProfile,
            activePermissionProfileValue: activePermissionProfile,
            profileWorkspaceRootsValue: profileWorkspaceRoots
        )
    }

    /// Reconstruct a trusted snapshot from already-resolved session state.
    public static func fromSessionSnapshot(
        _ permissionProfile: PermissionProfile,
        _ activePermissionProfile: ActivePermissionProfile?
    ) -> PermissionProfileSnapshot {
        if let activePermissionProfile {
            return .active(permissionProfile, activePermissionProfile)
        }
        return .legacy(permissionProfile)
    }

    public func permissionProfile() -> PermissionProfile {
        permissionProfileValue
    }

    public func activePermissionProfile() -> ActivePermissionProfile? {
        activePermissionProfileValue
    }

    public func profileWorkspaceRoots() -> [ProfileWorkspaceRoot] {
        profileWorkspaceRootsValue
    }
}

extension ProfileWorkspaceRoot: Equatable {
    public static func == (lhs: ProfileWorkspaceRoot, rhs: ProfileWorkspaceRoot) -> Bool {
        lhs.asUri().description == rhs.asUri().description
    }
}
