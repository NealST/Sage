//
//  ToolAuthorizationGrantStore.swift
//  Sage
//

import Foundation

@MainActor
final class ToolAuthorizationGrantStore {
    private struct Snapshot: Codable {
        var taskGrants: [String: [ToolAuthorizationGrant]]
        var longTermGrants: [ToolAuthorizationGrant]
        var taskInvocationKeys: [String: Set<String>]?
        var longTermInvocationKeys: Set<String>?
        var longTermInvocationLabels: [String: String]?
        var directoryRoots: [String: [String]]?
    }

    static let shared = ToolAuthorizationGrantStore()

    private let defaults: UserDefaults
    private let storageKey = "sage.tool-authorization-grants.v2"
    private var taskGrants: [String: [ToolAuthorizationGrant]]
    private var longTermGrants: [ToolAuthorizationGrant]
    private var taskInvocationKeys: [String: Set<String>]
    private var longTermInvocationKeys: Set<String>
    private var longTermInvocationLabels: [String: String]
    /// Directory roots that survive task switches.
    private var directoryRoots: [ToolAuthorizationCapability: Set<String>]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            taskGrants = snapshot.taskGrants
            longTermGrants = snapshot.longTermGrants
            taskInvocationKeys = snapshot.taskInvocationKeys ?? [:]
            longTermInvocationKeys = snapshot.longTermInvocationKeys ?? []
            longTermInvocationLabels = snapshot.longTermInvocationLabels ?? [:]
            directoryRoots = Self.decodeDirectoryRoots(snapshot.directoryRoots)
        } else {
            taskGrants = [:]
            longTermGrants = []
            taskInvocationKeys = [:]
            longTermInvocationKeys = []
            longTermInvocationLabels = [:]
            directoryRoots = [:]
        }
    }

    func contains(_ requirement: ToolAuthorizationRequirement, scopeID: String) -> Bool {
        requirement.isCovered(
            by: longTermGrants + taskGrants[scopeID, default: []]
        ) || requirement.isCovered(byDirectoryRoots: directoryRoots)
    }

    func allowForTask(_ requirement: ToolAuthorizationRequirement, scopeID: String) {
        append(requirement, to: &taskGrants[scopeID, default: []])
        rememberDirectoryRoots(requirement)
        persist()
    }

    func allowLongTerm(_ requirement: ToolAuthorizationRequirement) {
        append(requirement, to: &longTermGrants)
        rememberDirectoryRoots(requirement)
        persist()
    }

    func rememberDirectoryRoots(_ requirement: ToolAuthorizationRequirement) {
        for resource in requirement.resources {
            guard resource.capability == .localWrite || resource.capability == .sensitiveRead
            else { continue }
            for root in resource.roots where !root.isEmpty {
                directoryRoots[resource.capability, default: []].insert(root)
            }
        }
        persist()
    }

    var longTermGrantCount: Int {
        longTermGrants.count + longTermInvocationKeys.count
    }

    var longTermGrantSummaries: [ToolAuthorizationGrantSummary] {
        let capabilityGrants = longTermGrants.map { grant in
            ToolAuthorizationGrantSummary(
                id: "capability:\(grant.stableKey)",
                title: Self.displayPrincipal(grant.principal),
                detail: ToolAuthorizationRequirement(
                    resources: grant.resources,
                    principal: grant.principal
                ).userFacingSummary
            )
        }
        let invocationGrants = longTermInvocationKeys.sorted().map { key in
            ToolAuthorizationGrantSummary(
                id: "hook:\(key)",
                title: "Safety hook approval",
                detail: longTermInvocationLabels[key]
                    ?? "Exact invocation · \(key.prefix(12))"
            )
        }
        return capabilityGrants + invocationGrants
    }

    func removeAllLongTermGrants() {
        longTermGrants.removeAll()
        longTermInvocationKeys.removeAll()
        longTermInvocationLabels.removeAll()
        directoryRoots.removeAll()
        persist()
    }

    func removeAllGrants() {
        taskGrants.removeAll()
        longTermGrants.removeAll()
        taskInvocationKeys.removeAll()
        longTermInvocationKeys.removeAll()
        longTermInvocationLabels.removeAll()
        directoryRoots.removeAll()
        persist()
    }

    func removeLongTermGrant(id: String) {
        if id.hasPrefix("capability:") {
            let stableKey = String(id.dropFirst("capability:".count))
            longTermGrants.removeAll { $0.stableKey == stableKey }
        } else if id.hasPrefix("hook:") {
            let key = String(id.dropFirst("hook:".count))
            longTermInvocationKeys.remove(key)
            longTermInvocationLabels[key] = nil
        }
        persist()
    }

    func containsInvocation(_ key: String, scopeID: String) -> Bool {
        longTermInvocationKeys.contains(key)
            || taskInvocationKeys[scopeID, default: []].contains(key)
    }

    func allowInvocationForTask(_ key: String, scopeID: String) {
        taskInvocationKeys[scopeID, default: []].insert(key)
        persist()
    }

    func allowInvocationLongTerm(_ key: String, label: String) {
        longTermInvocationKeys.insert(key)
        longTermInvocationLabels[key] = label
        persist()
    }

    func removeTaskGrants(scopeID: String) {
        taskGrants[scopeID] = nil
        taskInvocationKeys[scopeID] = nil
        persist()
    }

    private func append(
        _ requirement: ToolAuthorizationRequirement,
        to grants: inout [ToolAuthorizationGrant]
    ) {
        let grant = ToolAuthorizationGrant(
            resources: requirement.resources,
            principal: requirement.principal
        )
        guard !grants.contains(grant) else { return }
        grants.append(grant)
    }

    private func persist() {
        let snapshot = Snapshot(
            taskGrants: taskGrants,
            longTermGrants: longTermGrants,
            taskInvocationKeys: taskInvocationKeys,
            longTermInvocationKeys: longTermInvocationKeys,
            longTermInvocationLabels: longTermInvocationLabels,
            directoryRoots: encodeDirectoryRoots()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func displayPrincipal(_ principal: String) -> String {
        if principal == "native-file-tools" { return "File tools" }
        if principal == "shell" { return "Shell" }
        if principal == "skill-writer" { return "Skill writer" }
        if principal.hasPrefix("skill:") { return "Skill script" }
        if principal.hasPrefix("mcp:") {
            let segments = principal.split(separator: ":")
            return segments.last.map { "MCP · \($0)" } ?? "MCP"
        }
        return principal
    }

    private func encodeDirectoryRoots() -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: directoryRoots.map { capability, roots in
            (capability.rawValue, roots.sorted())
        })
    }

    private static func decodeDirectoryRoots(
        _ raw: [String: [String]]?
    ) -> [ToolAuthorizationCapability: Set<String>] {
        var decoded: [ToolAuthorizationCapability: Set<String>] = [:]
        for (key, roots) in raw ?? [:] {
            guard let capability = ToolAuthorizationCapability(rawValue: key) else { continue }
            decoded[capability] = Set(roots.filter { !$0.isEmpty })
        }
        return decoded
    }
}
