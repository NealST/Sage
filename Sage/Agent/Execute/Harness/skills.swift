//
//  skills.swift
//  CodexCore
//
//  Port of codex-rs/core/src/skills.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Host skill lookup and prompt fragments for `build_skills_and_plugins`.
//  Analytics emit paths still throw until Session / TurnContext land here.
//

import CodexProtocol
import CodexSkills
import CodexUtils
import Foundation
import os

/// Deduplicates implicit skill invocations observed on one turn.
public struct ImplicitSkillInvocations: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<String>())

    public init() {}

    public func insert(_ key: String) -> Bool {
        lock.withLock { seen in
            seen.insert(key).inserted
        }
    }
}

/// In-memory host skill catalog used by the turn loop until Config-backed loading lands.
public struct SessionSkillsLookup: ExplicitSkillLookup, Equatable, Sendable {
    public var hostSkills: [SkillMetadata]
    public var disabledSkillPaths: Set<AbsolutePathBuf>
    public var discoveryPathByPath: [AbsolutePathBuf: AbsolutePathBuf]

    public init(
        hostSkills: [SkillMetadata] = [],
        disabledSkillPaths: Set<AbsolutePathBuf> = [],
        discoveryPathByPath: [AbsolutePathBuf: AbsolutePathBuf] = [:]
    ) {
        self.hostSkills = hostSkills
        self.disabledSkillPaths = disabledSkillPaths
        self.discoveryPathByPath = discoveryPathByPath
    }

    public func skills() -> [SkillMetadata] { hostSkills }

    public func disabledPaths() -> Set<AbsolutePathBuf> { disabledSkillPaths }

    public func skillDiscoveryPathForPath(_ path: AbsolutePathBuf) -> AbsolutePathBuf? {
        discoveryPathByPath[path]
    }

    public mutating func insertHostSkill(
        name: String,
        path: String,
        prompt: String,
        pluginId: String? = nil,
        mcpServers: [String] = []
    ) {
        let absolute = (try? AbsolutePathBuf.relativeToCurrentDir(path))
            ?? AbsolutePathBuf.resolvePathAgainstBase(
                path,
                basePath: FileManager.default.currentDirectoryPath
            )
        let dependencies: SkillDependencies?
        if mcpServers.isEmpty {
            dependencies = nil
        } else {
            dependencies = SkillDependencies(
                tools: mcpServers.map { SkillToolDependency(type: "mcp", value: $0) }
            )
        }
        hostSkills.append(
            SkillMetadata(
                name: name,
                description: name,
                interface: SkillInterface(defaultPrompt: prompt),
                dependencies: dependencies,
                pathToSkillsMd: absolute,
                scope: .repo,
                pluginId: pluginId
            )
        )
    }
}

/// Port of `codex-rs/ext/skills/src/fragments.rs` `SkillInstructions`.
public struct SkillInstructions: ContextualUserFragment, Equatable, Sendable {
    public var name: String
    public var path: String
    public var contents: String

    public init(name: String, path: String, contents: String) {
        self.name = name
        self.path = path
        self.contents = contents
    }

    public var contentKind: ContentItemKind { ContentItemKind("skills.selected_skill_instructions") }
    public var role: String { "user" }
    public var openMarker: String { "<skill>" }
    public var closeMarker: String { "</skill>" }
    public var body: String {
        "\n<name>\(name)</name>\n<path>\(path)</path>\n\(contents)\n"
    }
}

public func loadSkillPromptItems(_ skills: [SkillMetadata]) -> (items: [ResponseItem], warnings: [String]) {
    var items: [ResponseItem] = []
    var warnings: [String] = []
    for skill in skills {
        let contents: String
        if let file = try? String(contentsOfFile: skill.pathToSkillsMd.path, encoding: .utf8),
           !file.isEmpty {
            contents = file
        } else if let prompt = skill.interface?.defaultPrompt, !prompt.isEmpty {
            contents = prompt
        } else {
            warnings.append(
                "Failed to load skill \(skill.name) at \(skill.pathToSkillsMd.path)"
            )
            continue
        }
        items.append(
            SkillInstructions(
                name: skill.name,
                path: skill.pathToSkillsMd.path,
                contents: contents
            ).asResponseItem()
        )
    }
    return (items, warnings)
}

/// MCP servers and plugin summaries required by the current user input.
public func requiredMcpServersAndMentionedPlugins(
    userInput: [UserInput],
    plugins: [PluginCapabilitySummary],
    skills: SessionSkillsLookup,
    connectors: [AppInfo]
) -> (servers: [String], plugins: [PluginCapabilitySummary]) {
    let mentionedPlugins = collectExplicitPluginMentions(userInput, plugins: plugins)
    var requiredServers = Set(mentionedPlugins.flatMap(\.mcpServerNames))

    let messages = userInput.compactMap { item -> String? in
        if case .text(let text, _) = item { return text }
        return nil
    }
    let mentions = collectToolMentionsFromMessages(messages)
    let mentionPaths = userInput.compactMap { item -> String? in
        if case .mention(_, let path) = item { return path }
        return nil
    }
    for path in mentionPaths + Array(mentions.paths) {
        guard path.hasPrefix("mcp://") else { continue }
        let server = String(path.dropFirst("mcp://".count))
        guard !server.isEmpty else { continue }
        let name = server.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? server
        if !name.isEmpty {
            requiredServers.insert(name)
        }
    }

    let mentionedSkills = collectExplicitSkillMentions(
        inputs: userInput,
        loadedSkills: skills,
        connectorSlugCounts: buildConnectorSlugCounts(connectors)
    )
    for skill in mentionedSkills {
        if let dependencies = skill.dependencies {
            for tool in dependencies.tools where tool.type.compare("mcp", options: .caseInsensitive) == .orderedSame {
                requiredServers.insert(tool.value)
            }
        }
        if let pluginId = skill.pluginId,
           let plugin = plugins.first(where: { $0.configName == pluginId }) {
            requiredServers.formUnion(plugin.mcpServerNames)
        }
    }

    return (Array(requiredServers).sorted(), mentionedPlugins)
}

/// Host skill prompts, plugin injections, and connector IDs for the turn.
public func buildSkillAndPluginInjectionItems(
    userInput: [UserInput],
    mentionedPlugins: [PluginCapabilitySummary],
    skills: SessionSkillsLookup,
    mcpTools: [PluginToolInfo],
    connectors: [AppInfo]
) -> (items: [ResponseItem], connectors: Set<String>, warnings: [String]) {
    let mentionedSkills = collectExplicitSkillMentions(
        inputs: userInput,
        loadedSkills: skills,
        connectorSlugCounts: buildConnectorSlugCounts(connectors)
    )
    let loaded = loadSkillPromptItems(mentionedSkills)
    let pluginItems = buildPluginInjections(
        mentionedPlugins: mentionedPlugins,
        mcpTools: mcpTools,
        availableConnectors: connectors
    )
    var items = loaded.items
    items.append(contentsOf: pluginItems)
    return (items, collectExplicitAppIds(userInput), loaded.warnings)
}

public func skillsLoadInputFromConfig() throws -> Never {
    throw CodexErr.unsupportedOperation(
        "skills_load_input_from_config waits on Config / PluginSkillRoot"
    )
}

public func emitExplicitSkillInvocations() async throws {
    throw CodexErr.unsupportedOperation(
        "emit_explicit_skill_invocations waits on Session / TurnContext / skills crate"
    )
}

public func maybeEmitImplicitSkillInvocation() async throws {
    throw CodexErr.unsupportedOperation(
        "maybe_emit_implicit_skill_invocation waits on Session / TurnContext / skills crate"
    )
}
