//
//  loader.swift
//  CodexAgentRoles
//
//  Port of codex-rs/agent-roles/src/loader.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `ConfigToml` / `ConfigLayerStack` / `AgentRoleToml` are not ported.
//  Layer-stack merge throws until the config crate exists. Discovery and
//  declared-role loading take explicit role maps and `agents/` directories.
//

import CodexUtils
import FileSystem
import Foundation

/// Declared `[agents.roles.<name>]` fields used when `ConfigToml` is absent.
public struct AgentRoleToml: Equatable, Sendable {
    public var description: String?
    public var configFile: String?
    public var nicknameCandidates: [String]?

    public init(
        description: String? = nil,
        configFile: String? = nil,
        nicknameCandidates: [String]? = nil
    ) {
        self.description = description
        self.configFile = configFile
        self.nicknameCandidates = nicknameCandidates
    }
}

/// `load_agent_roles` with a config layer stack — throws until config is ported.
public func loadAgentRoles(
    fs: any ExecutorFileSystem,
    configLayerStackPresent: Bool,
    startupWarnings: inout [String]
) async throws -> [String: AgentRoleConfig] {
    _ = fs
    _ = startupWarnings
    if configLayerStackPresent {
        throw IOError.other(
            "load_agent_roles with ConfigLayerStack is unsupported until the config crate is ported"
        )
    }
    return [:]
}

/// `load_agent_roles_without_layers` plus directory discovery.
public func loadAgentRoles(
    fs: any ExecutorFileSystem,
    declaredRoles: [String: AgentRoleToml],
    agentsDirectories: [AbsolutePathBuf],
    startupWarnings: inout [String]
) async throws -> [String: AgentRoleConfig] {
    var roles: [String: AgentRoleConfig] = [:]
    for (declaredRoleName, roleToml) in declaredRoles {
        let (roleName, role) = try await readDeclaredRole(
            fs: fs,
            declaredRoleName: declaredRoleName,
            roleToml: roleToml
        )
        try validateRequiredAgentRoleDescription(roleName, role.description)
        if roles[roleName] != nil {
            throw IOError.invalidInput(
                "duplicate agent role name `\(roleName)` declared in config"
            )
        }
        roles[roleName] = role
    }

    var declaredRoleFiles = Set<String>()
    for role in roles.values {
        if let configFile = role.configFile {
            declaredRoleFiles.insert(configFile)
        }
    }

    for agentsDir in agentsDirectories {
        let discovered = try await discoverAgentRolesInDir(
            fs: fs,
            agentsDir: agentsDir,
            declaredRoleFiles: declaredRoleFiles,
            startupWarnings: &startupWarnings
        )
        for (roleName, role) in discovered {
            if roles[roleName] != nil {
                pushAgentRoleWarning(
                    &startupWarnings,
                    IOError.invalidInput(
                        "duplicate agent role name `\(roleName)` discovered in \(agentsDir.display)"
                    )
                )
                continue
            }
            roles[roleName] = role
        }
    }

    return roles
}

func pushAgentRoleWarning(_ startupWarnings: inout [String], _ error: IOError) {
    let message = "Ignoring malformed agent role definition: \(error)"
    startupWarnings.append(message)
}

func readDeclaredRole(
    fs: any ExecutorFileSystem,
    declaredRoleName: String,
    roleToml: AgentRoleToml
) async throws -> (String, AgentRoleConfig) {
    var role = try await agentRoleConfigFromToml(
        fs: fs,
        roleName: declaredRoleName,
        role: roleToml
    )
    var roleName = declaredRoleName
    if let configFile = role.configFile {
        let absolute = try AbsolutePathBuf.fromAbsolutePath(configFile)
        let parsedFile = try await readResolvedAgentRoleFile(
            fs: fs,
            path: absolute,
            roleNameHint: declaredRoleName
        )
        roleName = parsedFile.roleName
        role.description = parsedFile.description ?? role.description
        role.nicknameCandidates = parsedFile.nicknameCandidates ?? role.nicknameCandidates
    }
    return (roleName, role)
}

func mergeMissingRoleFields(_ role: inout AgentRoleConfig, fallback: AgentRoleConfig) {
    role.description = role.description ?? fallback.description
    role.configFile = role.configFile ?? fallback.configFile
    role.nicknameCandidates = role.nicknameCandidates ?? fallback.nicknameCandidates
}

func agentRoleConfigFromToml(
    fs: any ExecutorFileSystem,
    roleName: String,
    role: AgentRoleToml
) async throws -> AgentRoleConfig {
    let configFile = try role.configFile.map { try AbsolutePathBuf.fromAbsolutePath($0) }
    try await validateAgentRoleConfigFile(fs: fs, roleName: roleName, configFile: configFile)
    let description = try normalizeAgentRoleDescription(
        "agents.\(roleName).description",
        role.description
    )
    let nicknameCandidates = try normalizeAgentRoleNicknameCandidates(
        "agents.\(roleName).nickname_candidates",
        role.nicknameCandidates
    )
    return AgentRoleConfig(
        description: description,
        configFile: configFile?.path,
        nicknameCandidates: nicknameCandidates
    )
}

func readResolvedAgentRoleFile(
    fs: any ExecutorFileSystem,
    path: AbsolutePathBuf,
    roleNameHint: String?
) async throws -> ResolvedAgentRoleFile {
    let pathUri = PathUri.fromAbsPath(path)
    let contents = try await fs.readFileText(
        pathUri,
        options: .default,
        sandbox: nil
    )
    let configBaseDir = path.parent?.path ?? path.path
    return try parseAgentRoleFileContents(
        contents,
        roleFileLabel: path.asPath,
        configBaseDir: configBaseDir,
        roleNameHint: roleNameHint
    )
}

func validateRequiredAgentRoleDescription(
    _ roleName: String,
    _ description: String?
) throws {
    if description != nil {
        return
    }
    throw IOError.invalidInput("agent role `\(roleName)` must define a description")
}

func validateAgentRoleConfigFile(
    fs: any ExecutorFileSystem,
    roleName: String,
    configFile: AbsolutePathBuf?
) async throws {
    guard let configFile else { return }
    let configFileUri = PathUri.fromAbsPath(configFile)
    let metadata: FileMetadata
    do {
        metadata = try await fs.getMetadata(
            configFileUri,
            options: .default,
            sandbox: nil
        )
    } catch {
        throw IOError.invalidInput(
            "agents.\(roleName).config_file must point to an existing file at \(configFile.display): \(error)"
        )
    }
    if metadata.isFile {
        return
    }
    throw IOError.invalidInput(
        "agents.\(roleName).config_file must point to a file: \(configFile.display)"
    )
}

func discoverAgentRolesInDir(
    fs: any ExecutorFileSystem,
    agentsDir: AbsolutePathBuf,
    declaredRoleFiles: Set<String>,
    startupWarnings: inout [String]
) async throws -> [String: AgentRoleConfig] {
    var roles: [String: AgentRoleConfig] = [:]
    for agentFile in try await collectAgentRoleFiles(fs: fs, dir: agentsDir) {
        if declaredRoleFiles.contains(agentFile.path) {
            continue
        }
        let parsedFile: ResolvedAgentRoleFile
        do {
            parsedFile = try await readResolvedAgentRoleFile(
                fs: fs,
                path: agentFile,
                roleNameHint: nil
            )
        } catch let error as IOError {
            pushAgentRoleWarning(&startupWarnings, error)
            continue
        } catch {
            pushAgentRoleWarning(&startupWarnings, IOError.other(String(describing: error)))
            continue
        }
        let roleName = parsedFile.roleName
        if roles[roleName] != nil {
            pushAgentRoleWarning(
                &startupWarnings,
                IOError.invalidInput(
                    "duplicate agent role name `\(roleName)` discovered in \(agentsDir.display)"
                )
            )
            continue
        }
        roles[roleName] = AgentRoleConfig(
            description: parsedFile.description,
            configFile: agentFile.path,
            nicknameCandidates: parsedFile.nicknameCandidates
        )
    }
    return roles
}
