//
//  mentions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/mentions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  CodexSkills mention extractors and CodexCore mention sigils.
//

import CodexProtocol
import CodexSkills
import Foundation

public struct CollectedToolMentions: Equatable, Sendable {
    public var plainNames: Set<String>
    public var paths: Set<String>
}

public func collectToolMentionsFromMessages(_ messages: [String]) -> CollectedToolMentions {
    collectToolMentionsFromMessages(messages, sigil: TOOL_MENTION_SIGIL)
}

func collectToolMentionsFromMessages(
    _ messages: [String],
    sigil: Character
) -> CollectedToolMentions {
    var plainNames = Set<String>()
    var paths = Set<String>()
    for message in messages {
        let mentions = extractToolMentions(message, sigil: sigil)
        plainNames.formUnion(mentions.plainNames)
        paths.formUnion(mentions.paths)
    }
    return CollectedToolMentions(plainNames: plainNames, paths: paths)
}

public func collectExplicitAppIds(_ input: [UserInput]) -> Set<String> {
    let messages = input.compactMap { item -> String? in
        if case .text(let text, _) = item { return text }
        return nil
    }
    let mentionPaths = input.compactMap { item -> String? in
        if case .mention(_, let path) = item { return path }
        return nil
    }
    return Set(
        (mentionPaths + Array(collectToolMentionsFromMessages(messages).paths))
            .filter { toolKindForPath($0) == .app }
            .compactMap { appIdFromPath($0) }
    )
}

public func collectExplicitPluginMentions(
    _ input: [UserInput],
    plugins: [PluginCapabilitySummary]
) -> [PluginCapabilitySummary] {
    if plugins.isEmpty { return [] }
    let mentionedPluginIds = collectExplicitPluginIds(input)
    return plugins.filter { mentionedPluginIds.contains($0.configName) }
}

public func collectExplicitPluginIds(_ input: [UserInput]) -> Set<String> {
    let messages = input.compactMap { item -> String? in
        if case .text(let text, _) = item { return text }
        return nil
    }
    let mentionPaths = input.compactMap { item -> String? in
        if case .mention(_, let path) = item { return path }
        return nil
    }
    return Set(
        (mentionPaths + Array(collectToolMentionsFromMessages(messages, sigil: PLUGIN_TEXT_MENTION_SIGIL).paths))
            .filter { toolKindForPath($0) == .plugin }
            .compactMap { pluginConfigNameFromPath($0) }
    )
}

public func buildConnectorSlugCounts(_ connectors: [AppInfo]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for connector in connectors {
        let slug = connectorMentionSlug(connector)
        counts[slug, default: 0] += 1
    }
    return counts
}
