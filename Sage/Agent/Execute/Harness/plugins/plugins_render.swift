//
//  plugins_render.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/render.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  R4a: basename `render.swift` would collide with `apps/apps_render.swift`.
//

import CodexUtils
import Foundation

let MAX_EXPLICIT_PLUGIN_INSTRUCTIONS_BYTES = 4 * 1024
let TRUNCATED_PLUGIN_INSTRUCTIONS_SUFFIX =
    "\n- Additional plugin capabilities omitted to fit the context limit."

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
        let listed = availableApps.map { "`\($0)`" }.joined(separator: ", ")
        lines.append("- Apps from this plugin available in this session: \(listed).")
    }

    if !availableMcpServers.isEmpty {
        let listed = availableMcpServers.map { "`\($0)`" }.joined(separator: ", ")
        lines.append("- MCP servers from this plugin available in this session: \(listed).")
    }

    if lines.count == 1 {
        return nil
    }

    lines.append("Use these plugin-associated capabilities to help solve the task.")
    return boundExplicitPluginInstructions(lines.joined(separator: "\n"))
}

func boundExplicitPluginInstructions(_ rendered: String) -> String {
    if rendered.utf8.count <= MAX_EXPLICIT_PLUGIN_INSTRUCTIONS_BYTES {
        return rendered
    }
    let maxPrefixBytes = MAX_EXPLICIT_PLUGIN_INSTRUCTIONS_BYTES
        - TRUNCATED_PLUGIN_INSTRUCTIONS_SUFFIX.utf8.count
    let prefix = takeBytesAtCharBoundary(rendered, maxb: max(maxPrefixBytes, 0))
    return "\(prefix)\(TRUNCATED_PLUGIN_INSTRUCTIONS_SUFFIX)"
}
