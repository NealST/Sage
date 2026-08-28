//
//  ToolAuthorization.swift
//  Sage
//
//  Resource-oriented, just-in-time authorization for tool invocations.
//

import Foundation

nonisolated enum ToolAuthorizationCapability: String, Codable, Hashable, Sendable {
    case sensitiveRead
    case localWrite
    case network
    case protectedMetadataWrite
    case secretUse
}

nonisolated struct ToolAuthorizationRequirement: Codable, Hashable, Sendable {
    var capabilities: Set<ToolAuthorizationCapability>
    var roots: [String]
    var principal: String

    var stableKey: String {
        let capabilities = capabilities.map(\.rawValue).sorted().joined(separator: ",")
        return [principal, capabilities, roots.sorted().joined(separator: "\n")]
            .joined(separator: "\n")
    }

    func isCovered(by grant: ToolAuthorizationGrant) -> Bool {
        guard principal == grant.principal,
              capabilities.isSubset(of: grant.capabilities) else {
            return false
        }
        if capabilities.contains(.secretUse) {
            return Set(roots).isSubset(of: Set(grant.roots))
        }
        return roots.allSatisfy { requiredRoot in
            grant.roots.contains { grantedRoot in
                requiredRoot == grantedRoot || requiredRoot.hasPrefix(grantedRoot + "/")
            }
        }
    }
}

nonisolated struct ToolAuthorizationGrant: Codable, Hashable, Sendable {
    var capabilities: Set<ToolAuthorizationCapability>
    var roots: [String]
    var principal: String
}

nonisolated enum SensitiveResourcePolicy {
    private static let relativeRoots = [
        ".ssh",
        ".gnupg",
        ".aws",
        ".azure",
        ".kube",
        ".config/gcloud",
        "Library/Keychains",
        "Library/Application Support/Google/Chrome",
        "Library/Application Support/Firefox",
    ]

    static let roots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return relativeRoots.map { home.appendingPathComponent($0, isDirectory: true) }
    }()

    static func containingRoot(for url: URL) -> URL? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return roots.first { root in
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}

nonisolated enum ToolAuthorizationPolicy {
    private static let readToolNames: Set<String> = [
        "list_directory",
        "read_text_file",
        "search_files",
    ]

    private static let writeToolNames: Set<String> = [
        "copy_file",
        "create_directory",
        "delete_file",
        "edit_text_file",
        "move_file",
        "rename_file",
        "write_text_file",
    ]

    static func requirement(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) -> ToolAuthorizationRequirement? {
        let arguments = decodeObject(argumentsJSON)
        if readToolNames.contains(name) {
            return sensitiveReadRequirement(name: name, arguments: arguments, policy: policy)
        }
        if writeToolNames.contains(name) {
            return fileWriteRequirement(name: name, arguments: arguments, policy: policy)
        }
        if name == "run_shell_command" {
            return shellRequirement(arguments: arguments, policy: policy)
        }
        if name == "run_skill_script" {
            return skillSecretRequirement(arguments: arguments, skills: skills)
        }
        if name.hasPrefix("mcp__"),
           let tool = mcpTools.first(where: { $0.qualifiedName == name }),
           tool.localWriteHint {
            return mcpWriteRequirement(tool: tool, arguments: arguments, policy: policy)
        }
        return nil
    }

    private static func sensitiveReadRequirement(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement? {
        guard let rawPath = arguments["path"] as? String,
              let url = try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read),
              let sensitiveRoot = SensitiveResourcePolicy.containingRoot(for: url) else {
            return nil
        }
        return ToolAuthorizationRequirement(
            capabilities: [.sensitiveRead],
            roots: [normalized(sensitiveRoot)],
            principal: "native-file-tools"
        )
    }

    private static func fileWriteRequirement(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement {
        let rawPaths = writePaths(name: name, arguments: arguments)
        let roots = rawPaths.compactMap { rawPath -> String? in
            guard let url = try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read) else {
                return nil
            }
            return normalized(writeRoot(name: name, url: url))
        }
        return ToolAuthorizationRequirement(
            capabilities: [.localWrite],
            roots: roots.isEmpty ? [policy.defaultWorkingDirectory.path] : Array(Set(roots)).sorted(),
            principal: "native-file-tools"
        )
    }

    private static func shellRequirement(
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement? {
        var capabilities: Set<ToolAuthorizationCapability> = []
        if boolValue(arguments["allow_writes"]) {
            capabilities.insert(.localWrite)
        }
        if boolValue(arguments["allow_network"]) {
            capabilities.insert(.network)
        }
        if boolValue(arguments["allow_protected_metadata_writes"]) {
            capabilities.insert(.protectedMetadataWrite)
        }
        var roots: [String] = []
        if let rawPath = arguments["sensitive_read_path"] as? String,
           let url = try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read),
           let sensitiveRoot = SensitiveResourcePolicy.containingRoot(for: url) {
            capabilities.insert(.sensitiveRead)
            roots.append(normalized(sensitiveRoot))
        }
        guard !capabilities.isEmpty else { return nil }
        let rawDirectory = arguments["working_directory"] as? String
        let directory = rawDirectory.flatMap { rawPath in
            try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read)
        } ?? policy.defaultWorkingDirectory
        if capabilities.contains(.localWrite)
            || capabilities.contains(.protectedMetadataWrite) {
            roots.append(normalized(directory))
        }
        return ToolAuthorizationRequirement(
            capabilities: capabilities,
            roots: Array(Set(roots)).sorted(),
            principal: "shell"
        )
    }

    private static func skillSecretRequirement(
        arguments: [String: Any],
        skills: [SkillRecord]
    ) -> ToolAuthorizationRequirement? {
        guard let skillName = arguments["skill_name"] as? String,
              let skill = skills.first(where: { $0.name == skillName }),
              !skill.requiredSecretNames.isEmpty else {
            return nil
        }
        return ToolAuthorizationRequirement(
            capabilities: [.secretUse],
            roots: skill.requiredSecretNames.sorted(),
            principal: "skill:\(skill.id)"
        )
    }

    private static func mcpWriteRequirement(
        tool: MCPToolInfo,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement {
        let roots = arguments.compactMap { key, value -> String? in
            let lowercased = key.lowercased()
            guard lowercased.contains("path")
                    || lowercased.contains("directory")
                    || lowercased.contains("destination")
                    || lowercased == "root",
                  let rawPath = value as? String,
                  let url = try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read) else {
                return nil
            }
            return normalized(url.deletingLastPathComponent())
        }
        return ToolAuthorizationRequirement(
            capabilities: [.localWrite],
            roots: roots.isEmpty
                ? [normalized(policy.defaultWorkingDirectory)]
                : Array(Set(roots)).sorted(),
            principal: "mcp:\(tool.serverID)"
        )
    }

    private static func writePaths(name: String, arguments: [String: Any]) -> [String] {
        switch name {
        case "move_file", "copy_file":
            return ["source", "destination"].compactMap { arguments[$0] as? String }

        case "rename_file":
            return [arguments["path"] as? String].compactMap { $0 }

        default:
            return [arguments["path"] as? String].compactMap { $0 }
        }
    }

    private static func writeRoot(name: String, url: URL) -> URL {
        name == "create_directory" ? url : url.deletingLastPathComponent()
    }

    private static func decodeObject(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

@MainActor
final class ToolAuthorizationGrantStore {
    private struct Snapshot: Codable {
        var taskGrants: [String: [ToolAuthorizationGrant]]
        var longTermGrants: [ToolAuthorizationGrant]
    }

    static let shared = ToolAuthorizationGrantStore()

    private let defaults: UserDefaults
    private let storageKey = "sage.tool-authorization-grants.v1"
    private var taskGrants: [String: [ToolAuthorizationGrant]]
    private var longTermGrants: [ToolAuthorizationGrant]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            taskGrants = snapshot.taskGrants
            longTermGrants = snapshot.longTermGrants
        } else {
            taskGrants = [:]
            longTermGrants = []
        }
    }

    func contains(_ requirement: ToolAuthorizationRequirement, scopeID: String) -> Bool {
        longTermGrants.contains { requirement.isCovered(by: $0) }
            || taskGrants[scopeID, default: []].contains { requirement.isCovered(by: $0) }
    }

    func allowForTask(_ requirement: ToolAuthorizationRequirement, scopeID: String) {
        append(requirement, to: &taskGrants[scopeID, default: []])
        persist()
    }

    func allowLongTerm(_ requirement: ToolAuthorizationRequirement) {
        append(requirement, to: &longTermGrants)
        persist()
    }

    var longTermGrantCount: Int {
        longTermGrants.count
    }

    func removeAllLongTermGrants() {
        longTermGrants.removeAll()
        persist()
    }

    private func append(
        _ requirement: ToolAuthorizationRequirement,
        to grants: inout [ToolAuthorizationGrant]
    ) {
        let grant = ToolAuthorizationGrant(
            capabilities: requirement.capabilities,
            roots: requirement.roots,
            principal: requirement.principal
        )
        guard !grants.contains(grant) else { return }
        grants.append(grant)
    }

    private func persist() {
        let snapshot = Snapshot(taskGrants: taskGrants, longTermGrants: longTermGrants)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
