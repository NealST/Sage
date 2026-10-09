//
//  request_permissions.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/request_permissions.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The live tool call resolves filesystem paths against the step's turn
//  environments, then waits on Session.requestPermissions. The policy
//  context includes that environment's workspace roots and temporary
//  directories. An empty root list uses the environment cwd. Unset
//  temporary directories stay unset. That session method applies a
//  guardian decision, when one exists, before the user waiter.
//  ToolCallRuntime installs the callback and supplies the environments.
//  When the step list is empty it uses the admitted turn environment.
//

import CodexCore
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

struct RequestPermissionsHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "request_permissions") }
    func spec() -> ToolSpec { createRequestPermissionsTool(requestPermissionsToolDescription()) }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "request_permissions handler received unsupported payload"
            )
        }
        var parsed: CodexProtocol.JSONValue = try parseArguments(arguments)
        let environment = try resolveRequestPermissionsEnvironment(
            invocation.turnEnvironments,
            environmentId: requestPermissionsEnvironmentId(parsed)
        )
        let context = try permissionPolicyContext(environment)
        try resolvePermissionPathStrings(&parsed, context: context)
        let encoded = try JSONEncoder().encode(parsed)
        let decoded: RequestPermissionsArgs
        do {
            decoded = try JSONDecoder().decode(RequestPermissionsArgs.self, from: encoded)
        } catch {
            throw FunctionCallError.respondToModel(
                "failed to parse function arguments: \(error)"
            )
        }
        let normalized: AdditionalPermissionProfile
        do {
            normalized = try normalizeAdditionalPermissionsWithContext(
                AdditionalPermissionProfile(decoded.permissions),
                context: context
            )
        } catch {
            throw FunctionCallError.respondToModel(permissionModelMessage(error))
        }
        var args = decoded
        args.permissions = RequestPermissionProfile(normalized)
        if args.permissions.isEmpty {
            throw FunctionCallError.respondToModel(
                "request_permissions requires at least one permission"
            )
        }
        guard let onRequest = invocation.onRequestPermissions else {
            throw FunctionCallError.respondToModel(
                "request_permissions is not wired (Phase 5 Session)"
            )
        }
        guard let response = await onRequest(args, context) else {
            throw FunctionCallError.respondToModel(
                "request_permissions was cancelled before receiving a response"
            )
        }
        let data = try JSONEncoder().encode(response)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return boxedToolOutput(FunctionToolOutput.fromText(content, success: true))
    }
}

func requestPermissionsEnvironmentId(_ arguments: CodexProtocol.JSONValue) -> String? {
    guard case .object(let object) = arguments else { return nil }
    if case .string(let id)? = object["environment_id"] { return id }
    if case .string(let id)? = object["environmentId"] { return id }
    return nil
}

/// rust `resolve_tool_environment` for the environments this handler can see.
func resolveRequestPermissionsEnvironment(
    _ environments: [TurnEnvironment],
    environmentId: String?
) throws -> TurnEnvironment {
    if let environmentId {
        guard let match = environments.first(where: { $0.environmentId == environmentId }) else {
            throw FunctionCallError.respondToModel(
                "unknown turn environment id `\(environmentId)`"
            )
        }
        return match
    }
    guard let primary = environments.first else {
        throw FunctionCallError.respondToModel(
            "request_permissions requires a primary environment"
        )
    }
    return primary
}

func permissionPolicyContext(_ environment: TurnEnvironment) throws -> FileSystemSandboxPolicyContext {
    let cwd = try permissionPathUri(environment.cwd)
    let home = try environment.userHomeDir.map { try permissionPathUri($0) }
    let roots = try environment.workspaceRoots.map { try permissionPathUri($0) }
    let temporaryDirectories = try environment.temporaryDirectories.map { directories in
        try directories.map { try permissionPathUri($0) }
    }
    return FileSystemSandboxPolicyContext(
        cwd: cwd,
        workspaceRoots: roots.isEmpty ? [cwd] : roots,
        userHomeDir: home,
        temporaryDirectories: temporaryDirectories
    )
}

func permissionPathUri(_ path: String) throws -> PathUri {
    let legacy = LegacyAppPathString.fromString(path)
    guard let convention = legacy.inferAbsolutePathConvention() else {
        throw FunctionCallError.respondToModel(
            "request_permissions cwd `\(path)` has no path convention"
        )
    }
    do {
        return try legacy.toPathUri(convention)
    } catch {
        throw FunctionCallError.respondToModel(permissionModelMessage(error))
    }
}

func jsonObject(_ value: CodexProtocol.JSONValue?) -> [String: CodexProtocol.JSONValue]? {
    guard let value, case .object(let object) = value else { return nil }
    return object
}

func resolvePermissionPathStrings(
    _ arguments: inout CodexProtocol.JSONValue,
    context: FileSystemSandboxPolicyContext
) throws {
    guard var root = jsonObject(arguments),
          var permissions = jsonObject(root["permissions"]),
          var fileSystem = jsonObject(permissions["file_system"])
    else { return }

    var legacyEntries: [CodexProtocol.JSONValue] = []
    for (field, access) in [("read", "read"), ("write", "write")] {
        guard let paths = fileSystem.removeValue(forKey: field) else { continue }
        if case .null = paths { continue }
        guard case .array(let pathValues) = paths else {
            fileSystem[field] = paths
            continue
        }
        for var path in pathValues {
            try resolvePermissionPathString(&path, context: context)
            legacyEntries.append(.object([
                "path": .object(["type": .string("path"), "path": path]),
                "access": .string(access),
            ]))
        }
    }
    if !legacyEntries.isEmpty {
        var entries: [CodexProtocol.JSONValue]
        if let existing = fileSystem["entries"] {
            guard case .array(let current) = existing else {
                throw FunctionCallError.respondToModel(
                    "request_permissions file_system.entries must be an array"
                )
            }
            entries = current
        } else {
            entries = []
        }
        entries.append(contentsOf: legacyEntries)
        fileSystem["entries"] = .array(entries)
    }
    if case .array(var entries) = fileSystem["entries"] {
        for index in entries.indices {
            try resolvePermissionEntryPath(&entries[index], context: context)
        }
        fileSystem["entries"] = .array(entries)
    }
    permissions["file_system"] = .object(fileSystem)
    root["permissions"] = .object(permissions)
    arguments = .object(root)
}

func resolvePermissionEntryPath(
    _ entry: inout CodexProtocol.JSONValue,
    context: FileSystemSandboxPolicyContext
) throws {
    guard var object = jsonObject(entry),
          var pathObject = jsonObject(object["path"]),
          case .string(let type) = pathObject["type"] ?? .null,
          type == "path"
    else { return }
    var path = pathObject["path"] ?? .null
    try resolvePermissionPathString(&path, context: context)
    pathObject["path"] = path
    object["path"] = .object(pathObject)
    entry = .object(object)
}

func resolvePermissionPathString(
    _ value: inout CodexProtocol.JSONValue,
    context: FileSystemSandboxPolicyContext
) throws {
    guard case .string(let path) = value else { return }
    guard let convention = context.cwd.inferPathConvention() else {
        throw FunctionCallError.respondToModel(
            "request_permissions cwd `\(context.cwd)` has no path convention"
        )
    }
    let resolved: PathUri
    do {
        resolved = try LegacyAppPathString.fromString(path).resolveAgainst(
            cwd: context.cwd,
            userHomeDir: context.userHomeDir
        )
    } catch {
        throw FunctionCallError.respondToModel(permissionModelMessage(error))
    }
    if resolved.isOpaque() || String(bytes: resolved.decodedPathBytes(), encoding: .utf8) == nil {
        throw FunctionCallError.respondToModel(
            "permission path cannot be represented losslessly"
        )
    }
    let rendered: String
    do {
        rendered = try LegacyAppPathString.fromPathUri(resolved, convention: convention).intoString()
    } catch {
        throw FunctionCallError.respondToModel(permissionModelMessage(error))
    }
    value = .string(rendered)
}

func permissionModelMessage(_ error: Error) -> String {
    if let codex = error as? CodexErr {
        return codex.description
    }
    if let describable = error as? CustomStringConvertible {
        return describable.description
    }
    return String(describing: error)
}
