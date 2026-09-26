//
//  environment_context.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/environment_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Renders filesystem permission context. Path-URI materialization of
//  `:workspace_roots` waits for a full PermissionProfile helper.
//

import CodexProtocol
import Foundation

public struct FileSystemContext: Equatable, Sendable {
    public var workspaceRoots: [String]
    public var permissionProfile: PermissionProfile

    public init(workspaceRoots: [String], permissionProfile: PermissionProfile) {
        self.workspaceRoots = workspaceRoots
        self.permissionProfile = permissionProfile
    }

    public static func fromPermissionProfile(
        _ permissionProfile: PermissionProfile,
        workspaceRoots: [String]
    ) -> FileSystemContext {
        FileSystemContext(workspaceRoots: workspaceRoots, permissionProfile: permissionProfile)
    }

    public func render() -> String {
        var rendered = "<filesystem>"
        if !workspaceRoots.isEmpty {
            rendered += "<workspace_roots>"
            for root in workspaceRoots {
                rendered += "<root>\(xmlEscape(root))</root>"
            }
            rendered += "</workspace_roots>"
        }
        switch permissionProfile {
        case .managed(let fileSystem, _):
            rendered += "<permission_profile type=\"managed\">"
            rendered += renderManaged(fileSystem)
            rendered += "</permission_profile>"
        case .disabled:
            rendered += "<permission_profile type=\"disabled\"><file_system type=\"unrestricted\" /></permission_profile>"
        case .external:
            rendered += "<permission_profile type=\"external\"><file_system type=\"external\" /></permission_profile>"
        }
        rendered += "</filesystem>"
        return rendered
    }

    private func renderManaged(_ fileSystem: ManagedFileSystemPermissions) -> String {
        switch fileSystem {
        case .unrestricted:
            return "<file_system type=\"unrestricted\" />"
        case .restricted(let entries, let globScanMaxDepth):
            var rendered = "<file_system type=\"restricted\">"
            for entry in entries {
                rendered += "<entry access=\"\(entry.access)\">\(xmlEscape(String(describing: entry.path)))</entry>"
            }
            if let globScanMaxDepth {
                rendered += "<glob_scan_max_depth>\(globScanMaxDepth)</glob_scan_max_depth>"
            }
            rendered += "</file_system>"
            return rendered
        }
    }
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}
