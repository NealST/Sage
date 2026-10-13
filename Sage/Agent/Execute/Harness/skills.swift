//
//  skills.swift
//  SageCore
//
//  Port of codex-rs/core/src/skills.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Host skill lookup and prompt fragments for `build_skills_and_plugins`.
//  Plugin mention collection (plugins/mentions.rs) and explicit plugin
//  injections (plugins/injection.rs, plugins/render.rs, and the
//  context/plugin_instructions.rs fragment) are adapted into this file;
//  apps/render.rs stays deferred with the connectors layer. Analytics
//  emit paths still throw until Session / TurnContext land here.
//

import SageProtocol
import SageSkills
import SageUtils
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

/// Port of `codex-rs/core/src/context/plugin_instructions.rs`.
public struct PluginInstructions: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("plugins.instructions") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { text }
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
    return (items, Set(collectExplicitAppIds(userInput)), loaded.warnings)
}

public func skillsLoadInputFromConfig() throws -> Never {
    throw SageErr.unsupportedOperation(
        "skills_load_input_from_config waits on Config / PluginSkillRoot"
    )
}

public func emitExplicitSkillInvocations() async throws {
    throw SageErr.unsupportedOperation(
        "emit_explicit_skill_invocations waits on Session / TurnContext / skills crate"
    )
}

public func maybeEmitImplicitSkillInvocation() async throws {
    throw SageErr.unsupportedOperation(
        "maybe_emit_implicit_skill_invocation waits on Session / TurnContext / skills crate"
    )
}

public struct PluginCapabilitySummary: Equatable, Sendable {
    public var configName: String
    public var displayName: String
    public var pluginNamespace: String?
    public var description: String?
    public var hasSkills: Bool
    public var mcpServerNames: [String]

    public init(
        configName: String,
        displayName: String,
        pluginNamespace: String? = nil,
        description: String? = nil,
        hasSkills: Bool = false,
        mcpServerNames: [String] = []
    ) {
        self.configName = configName
        self.displayName = displayName
        self.pluginNamespace = pluginNamespace
        self.description = description
        self.hasSkills = hasSkills
        self.mcpServerNames = mcpServerNames
    }
}

public struct PluginToolInfo: Equatable, Sendable {
    public var name: String
    public var serverName: String
    public var pluginDisplayNames: [String]

    public init(
        name: String = "",
        serverName: String = "",
        pluginDisplayNames: [String] = []
    ) {
        self.name = name
        self.serverName = serverName
        self.pluginDisplayNames = pluginDisplayNames
    }
}

public struct AppInfo: Equatable, Sendable {
    public var id: String
    public var name: String
    public var isAccessible: Bool
    public var isEnabled: Bool
    public var pluginDisplayNames: [String]

    public init(
        id: String,
        name: String,
        isAccessible: Bool = false,
        isEnabled: Bool = true,
        pluginDisplayNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.isAccessible = isAccessible
        self.isEnabled = isEnabled
        self.pluginDisplayNames = pluginDisplayNames
    }
}

public struct CollectedToolMentions: Equatable, Sendable {
    public var names: Set<String>
    public var paths: Set<String>
    public var plainNames: Set<String>
}

public func collectToolMentionsFromMessages(_ messages: [String]) -> CollectedToolMentions {
    var names: Set<String> = []
    var paths: Set<String> = []
    var plainNames: Set<String> = []
    for message in messages {
        let mentions = extractToolMentions(message)
        names.formUnion(mentions.names)
        paths.formUnion(mentions.paths)
        plainNames.formUnion(mentions.plainNames)
    }
    return CollectedToolMentions(names: names, paths: paths, plainNames: plainNames)
}

public func collectExplicitAppIds(_ input: [UserInput]) -> [String] {
    Array(mentionedPaths(in: input, sigil: TOOL_MENTION_SIGIL).compactMap(appIdFromPath))
        .sorted()
}

public func collectExplicitPluginIds(_ input: [UserInput]) -> [String] {
    // Plugin plaintext links use `@`, not the default `$` tool sigil.
    Array(
        mentionedPaths(in: input, sigil: PLUGIN_TEXT_MENTION_SIGIL)
            .compactMap(pluginConfigNameFromPath)
    )
    .sorted()
}

public func collectExplicitPluginMentions(
    _ input: [UserInput],
    plugins: [PluginCapabilitySummary]
) -> [PluginCapabilitySummary] {
    let mentioned = Set(collectExplicitPluginIds(input))
    return plugins.filter { mentioned.contains($0.configName) }
}

public func buildConnectorSlugCounts(_ connectors: [AppInfo]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for connector in connectors {
        counts[connectorMentionSlug(connector), default: 0] += 1
    }
    return counts
}

public func connectorNameSlug(_ name: String) -> String {
    let slug = name.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
    return slug.isEmpty ? "app" : slug
}

public func connectorMentionSlug(_ app: AppInfo) -> String {
    connectorNameSlug(app.name)
}

public func buildPluginInjections(
    mentionedPlugins: [PluginCapabilitySummary],
    mcpTools: [PluginToolInfo],
    availableConnectors: [AppInfo]
) -> [ResponseItem] {
    guard !mentionedPlugins.isEmpty else { return [] }

    // Turn each explicit plugin mention into a developer hint that points the
    // model at the plugin's visible MCP servers, enabled apps, and skill prefix.
    return mentionedPlugins.compactMap { plugin in
        let availableMcpServers = Set(
            mcpTools
                .filter {
                    $0.serverName != SAGE_APPS_MCP_SERVER_NAME
                        && $0.pluginDisplayNames.contains(plugin.displayName)
                }
                .map(\.serverName)
        ).sorted()
        let availableApps = Set(
            availableConnectors
                .filter { $0.isEnabled && $0.pluginDisplayNames.contains(plugin.displayName) }
                // Upstream maps via `connector_display_label`, which is the connector name.
                .map(\.name)
        ).sorted()
        return renderExplicitPluginInstructions(
            plugin: plugin,
            availableMcpServers: availableMcpServers,
            availableApps: availableApps
        )
        .map { PluginInstructions(text: $0).asResponseItem() }
    }
}

public func renderExplicitPluginInstructions(
    plugin: PluginCapabilitySummary,
    availableMcpServers: [String],
    availableApps: [String]
) -> String? {
    var lines = ["Capabilities from the `\(plugin.displayName)` plugin:"]

    if !availableApps.isEmpty {
        lines.append(
            "- For the user request that explicitly selected this plugin, and only for that "
                + "request, if `tool_search` is available and an app from this plugin may help, "
                + "search for its tools before falling back to unrelated or built-in tools."
        )
    }

    if plugin.hasSkills {
        let skillNamespace = plugin.pluginNamespace ?? plugin.displayName
        lines.append("- Skills from this plugin are prefixed with `\(skillNamespace):`.")
    }

    if !availableApps.isEmpty {
        lines.append(
            "- Apps from this plugin available in this session: "
                + availableApps.map { "`\($0)`" }.joined(separator: ", ")
                + "."
        )
    }

    if !availableMcpServers.isEmpty {
        lines.append(
            "- MCP servers from this plugin available in this session: "
                + availableMcpServers.map { "`\($0)`" }.joined(separator: ", ")
                + "."
        )
    }

    if lines.count == 1 {
        return nil
    }

    lines.append("Use these plugin-associated capabilities to help solve the task.")

    return boundExplicitPluginInstructions(lines.joined(separator: "\n"))
}

private let maxExplicitPluginInstructionsBytes = 4 * 1024
private let truncatedPluginInstructionsSuffix =
    "\n- Additional plugin capabilities omitted to fit the context limit."

private func boundExplicitPluginInstructions(_ rendered: String) -> String {
    if rendered.utf8.count <= maxExplicitPluginInstructionsBytes {
        return rendered
    }
    let maxPrefixBytes = maxExplicitPluginInstructionsBytes
        - truncatedPluginInstructionsSuffix.utf8.count
    let prefix = takeBytesAtCharBoundary(rendered, maxb: maxPrefixBytes)
    return String(prefix) + truncatedPluginInstructionsSuffix
}

public func renderAppsSection(_ apps: [AppInfo]) -> String? {
    _ = apps
    return nil
}

private func mentionedPaths(in input: [UserInput], sigil: Character) -> Set<String> {
    var paths: Set<String> = []
    var messages: [String] = []
    for item in input {
        switch item {
        case .text(let text, _):
            messages.append(text)
        case .mention(_, let path):
            paths.insert(path)
        default:
            break
        }
    }
    paths.formUnion(messages.flatMap { extractToolMentions($0, sigil: sigil).paths })
    return paths
}
