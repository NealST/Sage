//
//  injection.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/injection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `ToolInfo` is represented as `PluginToolInfo` until the MCP crate is
//  ported. Response-item conversion uses `ContextualUserFragment.asResponseItem`.
//

import CodexProtocol
import Foundation

public func buildPluginInjections(
    mentionedPlugins: [PluginCapabilitySummary],
    mcpTools: [PluginToolInfo],
    availableConnectors: [AppInfo]
) -> [ResponseItem] {
    if mentionedPlugins.isEmpty { return [] }

    return mentionedPlugins.compactMap { plugin in
        let availableMcpServers = Array(
            Set(
                mcpTools
                    .filter { tool in
                        tool.serverName != CODEX_APPS_MCP_SERVER_NAME
                            && tool.pluginDisplayNames.contains(plugin.displayName)
                    }
                    .map(\.serverName)
            )
        ).sorted()
        let availableApps = Array(
            Set(
                availableConnectors
                    .filter { connector in
                        connector.isEnabled
                            && connector.pluginDisplayNames.contains(plugin.displayName)
                    }
                    .map { connectorDisplayLabel($0) }
            )
        ).sorted()
        return renderExplicitPluginInstructions(
            plugin: plugin,
            availableMcpServers: availableMcpServers,
            availableApps: availableApps
        )
        .map { PluginInstructions(text: $0).asResponseItem() }
    }
}
