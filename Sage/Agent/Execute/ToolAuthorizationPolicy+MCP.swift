//
//  ToolAuthorizationPolicy+MCP.swift
//  Sage
//

import Foundation

extension ToolAuthorizationPolicy {
    static func mcpRequirement(
        tool: MCPToolInfo,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement? {
        if tool.readOnlyHint == true, !tool.localWriteHint {
            return nil
        }
        let roots = collectMCPWriteRoots(
            arguments,
            policy: policy,
            schema: tool.inputSchema
        )
        if tool.localWriteHint || !roots.isEmpty {
            return mcpWriteRequirement(tool: tool, roots: roots, policy: policy)
        }
        return nil
    }

    static func collectMCPWriteRoots(
        _ object: Any,
        key: String? = nil,
        policy: PathGuard.Policy,
        schema: JSONValue? = nil
    ) -> [String] {
        collectMCPWriteRoots(
            object,
            key: key,
            policy: policy,
            allowedKeys: schemaPathKeys(schema)
        )
    }

    private static func mcpWriteRequirement(
        tool: MCPToolInfo,
        roots: [String],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement {
        var resources = [
            ToolAuthorizationResource(
                capability: .localWrite,
                roots: Array(Set(roots)).sorted()
            ),
        ]
        let protectedRoots = roots.filter { root in
            PathGuard.isProtectedWritePath(root, policy: policy)
        }
        if !protectedRoots.isEmpty {
            resources.append(
                ToolAuthorizationResource(
                    capability: .protectedMetadataWrite,
                    roots: Array(Set(protectedRoots)).sorted()
                )
            )
        }
        return ToolAuthorizationRequirement(
            resources: resources,
            principal: [
                "mcp",
                tool.serverID,
                tool.serverAuthorizationFingerprint,
                tool.name,
            ].joined(separator: ":")
        )
    }

    private static func collectMCPWriteRoots(
        _ object: Any,
        key: String?,
        policy: PathGuard.Policy,
        allowedKeys: Set<String>?
    ) -> [String] {
        if let dictionary = object as? [String: Any] {
            return dictionary.flatMap { nestedKey, value in
                collectMCPWriteRoots(
                    value,
                    key: nestedKey,
                    policy: policy,
                    allowedKeys: allowedKeys
                )
            }
        }
        if let array = object as? [Any] {
            return array.flatMap { value in
                collectMCPWriteRoots(
                    value,
                    key: key,
                    policy: policy,
                    allowedKeys: allowedKeys
                )
            }
        }
        return resolvedMCPWriteRoot(
            key: key,
            value: object,
            policy: policy,
            allowedKeys: allowedKeys
        )
    }

    private static func resolvedMCPWriteRoot(
        key: String?,
        value: Any,
        policy: PathGuard.Policy,
        allowedKeys: Set<String>?
    ) -> [String] {
        guard let key, let rawPath = value as? String else { return [] }
        let normalizedKey = normalizedSchemaKey(key)
        let keyAllowed = allowedKeys.map { keys in
            keys.contains(normalizedKey)
        } ?? looksLikePathKey(key)
        guard keyAllowed,
              looksLikePath(rawPath),
              let url = try? PathGuard.resolveAllowed(
                  rawPath,
                  policy: policy,
                  access: .read
              ) else {
            return []
        }
        let isDirectoryKey = normalizedKey.contains("directory")
            || normalizedKey == "root"
            || normalizedKey == "rootpath"
        if isDirectoryKey || directoryExists(at: url) {
            return [normalized(url)]
        }
        return [normalized(url.deletingLastPathComponent())]
    }

    /// `nil` means the schema is empty or unknown, so the default key allowlist applies.
    private static func schemaPathKeys(_ schema: JSONValue?) -> Set<String>? {
        guard let schema else { return nil }
        let keys = pathKeys(in: schema)
        return keys.isEmpty ? nil : keys
    }

    private static func pathKeys(in schema: JSONValue) -> Set<String> {
        guard case .object(let object) = schema else { return [] }
        var keys = Set<String>()
        if case .object(let properties) = object["properties"] {
            for (name, property) in properties {
                if isStringSchema(property), looksLikePathKey(name) {
                    keys.insert(normalizedSchemaKey(name))
                }
                keys.formUnion(pathKeys(in: property))
            }
        }
        if let items = object["items"] {
            keys.formUnion(pathKeys(in: items))
        }
        return keys
    }

    private static func isStringSchema(_ schema: JSONValue) -> Bool {
        guard case .object(let object) = schema else { return false }
        if case .string(let type) = object["type"] {
            return type == "string"
        }
        if case .array(let types) = object["type"] {
            return types.contains { $0.stringValue == "string" }
        }
        return false
    }

    private static func looksLikePathKey(_ name: String) -> Bool {
        let normalized = normalizedSchemaKey(name)
        let supportedKeys: Set<String> = [
            "path",
            "filepath",
            "directory",
            "destination",
            "destinationpath",
            "outputpath",
            "outputdirectory",
            "targetpath",
            "root",
            "rootpath",
        ]
        return !normalized.contains("source") && supportedKeys.contains(normalized)
    }

    private static func normalizedSchemaKey(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func looksLikePath(_ value: String) -> Bool {
        value.hasPrefix("/")
            || value.hasPrefix("~")
            || value.hasPrefix(".")
            || value.contains("/")
    }
}
