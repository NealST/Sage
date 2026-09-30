//
//  McpToolExposureTests.swift
//  Phase9AgentTests
//
//  Sage addition (no codex counterpart).
//  Port of codex-rs/core/src/mcp_tool_exposure_test.rs behavior.
//

import CodexCore
import XCTest

final class McpToolExposureTests: XCTestCase {
    func testDirectlyExposesToolsWhenSearchIsUnavailable() {
        let tools = numberedTools(2)
        let runtimes = runtimesByName(tools, searchToolEnabled: false)
        XCTAssertEqual(Set(runtimes.values), [.direct])
        XCTAssertEqual(runtimes.count, 2)
    }

    func testDefersToolsWhenSearchIsAvailable() {
        let tools = numberedTools(2)
        let runtimes = runtimesByName(tools, searchToolEnabled: true)
        XCTAssertEqual(Set(runtimes.values), [.deferred])
    }

    func testExcludesToolsHiddenFromModelExposure() {
        let visible = makeTool(server: "rmcp", name: "visible_tool")
        let hidden = makeTool(server: "rmcp", name: "hidden_tool", visibility: ["app"])
        let emptyVisibility = makeTool(server: "rmcp", name: "empty_visibility_tool", visibility: [])
        let visibleApp = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "calendar_read",
            connectorId: "calendar",
            visibility: ["app", "model"]
        )
        let hiddenApp = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "calendar_open",
            connectorId: "calendar",
            visibility: ["app"]
        )
        let runtimes = runtimesByName(
            [visible, hidden, emptyVisibility, visibleApp, hiddenApp],
            appsEnabled: true
        )
        XCTAssertEqual(Set(runtimes.keys), [visible.name, visibleApp.name])
    }

    func testAppToolsAreOmittedWhenAppsDisabled() {
        let app = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "calendar_list_events",
            connectorId: "calendar"
        )
        let missingConnector = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "unknown_tool"
        )
        let regular = makeTool(server: "rmcp", name: "regular_tool")
        let enabled = appendMcpTools(
            [app, missingConnector, regular],
            appsEnabled: true,
            appsConfig: nil,
            searchToolEnabled: false
        )
        XCTAssertEqual(enabled.map(\.tool.name), [regular.name, app.name])
        let disabled = appendMcpTools(
            [app, missingConnector, regular],
            appsEnabled: false,
            appsConfig: nil,
            searchToolEnabled: false
        )
        XCTAssertEqual(disabled.map(\.tool.name), [regular.name])
    }

    func testAppliesPerToolAppPolicy() {
        let enabledTool = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "events/create",
            connectorId: "calendar"
        )
        let disabledTool = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "events/list",
            connectorId: "calendar"
        )
        let config = AppsConfig(apps: [
            "calendar": AppsAppConfig(
                defaultToolsEnabled: false,
                tools: ["events/create": AppsToolConfig(enabled: true)]
            ),
        ])
        let runtimes = runtimesByName(
            [enabledTool, disabledTool],
            appsEnabled: true,
            appsConfig: config
        )
        XCTAssertEqual(Array(runtimes.keys).sorted(), [enabledTool.name])
    }

    func testCachedAppHandlersStillObeyCurrentAppsEnablement() {
        let tool = makeTool(
            server: CODEX_APPS_MCP_SERVER_NAME,
            name: "events/create",
            connectorId: "calendar"
        )
        var handlers: [String: McpVisibleTool] = [:]
        let allowed = appendMcpTools(
            [tool],
            appsEnabled: true,
            appsConfig: nil,
            searchToolEnabled: false,
            handlers: &handlers
        )
        let disabled = appendMcpTools(
            [tool],
            appsEnabled: false,
            appsConfig: nil,
            searchToolEnabled: false,
            handlers: &handlers
        )
        let restricted = appendMcpTools(
            [tool],
            appsEnabled: true,
            appsConfig: AppsConfig(apps: [
                "calendar": AppsAppConfig(defaultToolsEnabled: false),
            ]),
            searchToolEnabled: false,
            handlers: &handlers
        )
        let restored = appendMcpTools(
            [tool],
            appsEnabled: true,
            appsConfig: nil,
            searchToolEnabled: true,
            handlers: &handlers
        )
        XCTAssertEqual(allowed.map(\.tool.name), [tool.name])
        XCTAssertTrue(disabled.isEmpty)
        XCTAssertTrue(restricted.isEmpty)
        XCTAssertEqual(restored.map(\.tool.name), [tool.name])
        XCTAssertEqual(restored.first?.exposure, .deferred)
        XCTAssertEqual(handlers[tool.name], tool)
    }

    func testAgentPluginBudgetHidesOnlyOverflowAgentTools() {
        var tools = (0..<40).map { index in
            makeTool(
                server: "agent",
                name: "tool_\(index)",
                isAgentPlugin: true,
                modelSpecBytes: 2_000
            )
        }
        let oversized = makeTool(
            server: "agent",
            name: "oversized_agent_tool",
            isAgentPlugin: true,
            modelSpecBytes: maxAgentPluginMcpSpecBytes + 1
        )
        let legacy = makeTool(
            server: "legacy",
            name: "legacy_tool",
            isAgentPlugin: false,
            modelSpecBytes: maxAgentPluginMcpSpecBytes + 1
        )
        tools.append(oversized)
        tools.append(legacy)
        let runtimes = runtimesByName(tools, appsEnabled: false)
        let agentExposures = tools[..<40].map { runtimes[$0.name] }
        XCTAssertTrue(agentExposures.contains(.direct))
        XCTAssertTrue(agentExposures.contains(.hidden))
        XCTAssertEqual(runtimes[oversized.name], .hidden)
        XCTAssertEqual(runtimes[legacy.name], .direct)
    }

    func testCacheDropsHandlersWhenBindingChanges() {
        var cache = McpHandlerCache()
        let first = makeTool(server: "rmcp", name: "search")
        _ = cache.registerTools(
            [first],
            bindingID: 1,
            appsEnabled: true,
            appsConfig: nil,
            searchToolEnabled: false
        )
        XCTAssertEqual(cache.cached?.toolsByName[first.name], first)
        let second = makeTool(server: "rmcp", name: "other")
        _ = cache.registerTools(
            [second],
            bindingID: 2,
            appsEnabled: true,
            appsConfig: nil,
            searchToolEnabled: false
        )
        XCTAssertNil(cache.cached?.toolsByName[first.name])
        XCTAssertEqual(cache.cached?.toolsByName[second.name], second)
        XCTAssertEqual(cache.exposedToolNames, [second.name])
    }
}

private func makeTool(
    server: String,
    name: String,
    connectorId: String? = nil,
    visibility: [String]? = nil,
    isAgentPlugin: Bool = false,
    modelSpecBytes: Int? = nil
) -> McpVisibleTool {
    McpVisibleTool(
        name: name,
        description: "Test tool: \(name)",
        serverName: server,
        connectorId: connectorId,
        visibility: visibility,
        isAgentPlugin: isAgentPlugin,
        modelSpecBytes: modelSpecBytes
    )
}

private func numberedTools(_ count: Int) -> [McpVisibleTool] {
    (0..<count).map { makeTool(server: "rmcp", name: "tool_\($0)") }
}

private func runtimesByName(
    _ tools: [McpVisibleTool],
    appsEnabled: Bool = false,
    appsConfig: AppsConfig? = nil,
    searchToolEnabled: Bool = false
) -> [String: McpToolExposure] {
    Dictionary(
        uniqueKeysWithValues: appendMcpTools(
            tools,
            appsEnabled: appsEnabled,
            appsConfig: appsConfig,
            searchToolEnabled: searchToolEnabled
        ).map { ($0.tool.name, $0.exposure) }
    )
}
