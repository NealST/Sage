//
//  ToolAuthorizationModels.swift
//  Sage
//

import Foundation

nonisolated enum ToolAuthorizationCapability: String, Codable, Hashable, Sendable {
    case sensitiveRead
    case localWrite
    case network
    case protectedMetadataWrite
    case secretUse
}

nonisolated struct ToolAuthorizationResource: Codable, Hashable, Sendable {
    var capability: ToolAuthorizationCapability
    var roots: [String]
}

nonisolated struct ToolAuthorizationRequirement: Codable, Hashable, Sendable {
    var resources: [ToolAuthorizationResource]
    var principal: String

    var capabilities: Set<ToolAuthorizationCapability> {
        Set(resources.map(\.capability))
    }

    func roots(for capability: ToolAuthorizationCapability) -> [String] {
        resources
            .filter { $0.capability == capability }
            .flatMap(\.roots)
    }

    var userFacingSummary: String {
        resources.map { resource in
            let label = Self.capabilityLabel(resource.capability)
            guard !resource.roots.isEmpty else { return label }
            let roots = resource.roots.map(Self.displayResource).joined(separator: ", ")
            return "\(label): \(roots)"
        }
        .joined(separator: "\n")
    }

    var userFacingPrompt: String {
        let kinds = capabilities
        if kinds == [.network] {
            return "This call needs permission to use the network."
        }
        if kinds == [.secretUse] {
            return "This call needs permission to use configured secrets."
        }
        if kinds == [.protectedMetadataWrite] {
            return "This call needs permission to modify protected project metadata."
        }
        if kinds == [.sensitiveRead] {
            return "This call needs permission to read protected data."
        }
        if kinds == [.localWrite] {
            return "This call needs permission to modify local content."
        }
        return "This call needs permission for the actions listed below."
    }

    var stableKey: String {
        let resourceKeys = resources.map { resource in
            resource.capability.rawValue + ":" + resource.roots.sorted().joined(separator: "\n")
        }
        return [principal, resourceKeys.sorted().joined(separator: "\n")]
            .joined(separator: "\n")
    }

    var validationError: String? {
        let unresolved = resources.contains { resource in
            resource.capability != .network && resource.roots.isEmpty
        }
        return unresolved
            ? "Sage could not determine a safe resource scope for this authorization request."
            : nil
    }

    func isCovered(by grants: [ToolAuthorizationGrant]) -> Bool {
        resources.allSatisfy { requiredResource in
            grants.contains { grant in
                guard principal == grant.principal else { return false }
                return grant.resources.contains { grantedResource in
                    guard requiredResource.capability == grantedResource.capability else {
                        return false
                    }
                    if requiredResource.capability == .network {
                        return true
                    }
                    guard !requiredResource.roots.isEmpty else { return false }
                    if requiredResource.capability == .secretUse {
                        return Set(requiredResource.roots)
                            .isSubset(of: Set(grantedResource.roots))
                    }
                    return requiredResource.roots.allSatisfy { requiredRoot in
                        grantedResource.roots.contains { grantedRoot in
                            requiredRoot == grantedRoot
                                || requiredRoot.hasPrefix(grantedRoot + "/")
                        }
                    }
                }
            }
        }
    }

    private static func capabilityLabel(_ capability: ToolAuthorizationCapability) -> String {
        switch capability {
        case .sensitiveRead: "Read protected data"
        case .localWrite: "Modify local content"
        case .network: "Use network access"
        case .protectedMetadataWrite: "Modify protected project metadata"
        case .secretUse: "Use secrets"
        }
    }

    private static func displayResource(_ resource: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if resource == home { return "~" }
        if resource.hasPrefix(home + "/") {
            return "~/" + resource.dropFirst(home.count + 1)
        }
        return resource
    }
}

nonisolated struct ToolAuthorizationGrant: Codable, Hashable, Sendable {
    var resources: [ToolAuthorizationResource]
    var principal: String

    var stableKey: String {
        ToolAuthorizationRequirement(resources: resources, principal: principal).stableKey
    }
}

nonisolated struct ToolAuthorizationGrantSummary: Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
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
        let path = normalizedPath(url)
        return roots.first { root in
            contains(path: path, root: normalizedPath(root))
        }
    }

    /// Protected roots that a recursive operation beginning at `url` could enter.
    static func intersectingRoots(for url: URL) -> [URL] {
        let path = normalizedPath(url)
        return roots.filter { root in
            let rootPath = normalizedPath(root)
            return contains(path: path, root: rootPath)
                || contains(path: rootPath, root: path)
        }
    }

    static func isProtectedRoot(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return roots.contains { normalizedPath($0) == path }
    }

    /// True when moving or copying `source` would place a protected root at a new path.
    static func wouldRelocateProtectedRoot(source: URL) -> Bool {
        let sourcePath = normalizedPath(source)
        if isProtectedRoot(source) { return true }
        return intersectingRoots(for: source).contains { root in
            let rootPath = normalizedPath(root)
            return rootPath != sourcePath && contains(path: rootPath, root: sourcePath)
        }
    }

    private static func contains(path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
