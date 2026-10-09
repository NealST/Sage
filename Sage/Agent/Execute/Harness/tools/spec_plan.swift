//
//  spec_plan.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/spec_plan.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `planCoreToolOptions` applies the Codex feature and config gates for the
//  handlers this builder already knows. `finalizeToolRouter()` keeps its
//  struct defaults so an unconfigured builder still registers the core set.
//
//  Adapted:
//  - `unified_exec` alone is enough to expose `exec_command`. Rust also
//    requires `shell_tool`.
//  - `supports_search_tool` turns on tool search. Provider namespace-tool
//    capability is not on the model snapshot yet.
//  - apply_patch, tool suggest, request_user_input_async, and collaboration
//    tools are not selected here.
//  - `canManageChildren` stays false until those child tools are planned.
//  - `appendDynamicToolRuntimes` registers the turn's dynamic tools.
//    Direct tools join the model-visible specs; deferred tools stay registered
//    for later search. Reserved `exec_command` and `shell_command` names are skipped.
//

import CodexProtocol
import Foundation

struct ToolSpecPlan {
    var specs: [ToolSpec]
    var registry: HarnessToolRegistry
}

struct ToolRouterPlanOptions: Equatable, Sendable {
    var includeCurrentTime = true
    var includeSleep = true
    var includePlan = true
    var includeNewContextWindow = true
    var includeGetContextRemaining = true
    var includeSendMessageToUserAsync = false
    var includeRequestPermissions = true
    var includeRequestUserInput = false
    var includeTestSync = false
    var includeViewImage = false
    var includeToolSearch = false
    var includeExecCommand = false
    var includeWriteStdin = false
    var includeMcpResources = false
    var includeWaitForEnvironment = false
    var toolMode: ToolMode = .direct
}

struct CoreToolPlanInput: Equatable, Sendable {
    var features: Features
    var updatePlanEnabled: Bool
    var experimentalRequestUserInputEnabled: Bool
    var sleepToolMode: SleepToolMode
    var currentTimeReminder: CurrentTimeReminderConfig?
    var hasEnvironment: Bool
    var sessionSource: SessionSource
    var experimentalSupportedTools: [String]
    var shellType: ConfigShellToolType
    var supportsSearchTool: Bool
    var hasMcpServers: Bool
}

/// Codex `add_core_utility_tools` / `add_shell_tools` / `add_mcp_resource_tools`
/// for the handlers already registered by `finalizeToolRouter`.
func planCoreToolOptions(_ input: CoreToolPlanInput) -> ToolRouterPlanOptions {
    let features = input.features
    let tools = input.experimentalSupportedTools
    let modelHasClock = tools.contains("clock")
    let currentTimeReminderEnabled = features.enabled(.currentTimeReminder)
    let shellAllowed = input.hasEnvironment
        && input.shellType != .disabled
        && (features.enabled(.shellTool) || features.enabled(.unifiedExec))
    let includeSleep: Bool
    if features.enabled(.sleepTool) {
        switch input.sleepToolMode {
        case .alwaysOn:
            includeSleep = true
        case .modelDriven:
            if currentTimeReminderEnabled {
                includeSleep = input.currentTimeReminder?.sleepTool == true
            } else {
                includeSleep = modelHasClock
            }
        }
    } else {
        includeSleep = false
    }

    var options = ToolRouterPlanOptions()
    options.includeCurrentTime = currentTimeReminderEnabled || modelHasClock
    options.includeSleep = includeSleep
    options.includePlan = input.updatePlanEnabled
    options.includeNewContextWindow = features.enabled(.tokenBudget)
    options.includeGetContextRemaining = features.enabled(.tokenBudget)
    options.includeSendMessageToUserAsync = !input.sessionSource.isNonRootAgent()
        && (features.enabled(.sendMessageToUserAsync) || tools.contains("send_message_to_user_async"))
    options.includeRequestPermissions = input.hasEnvironment && features.enabled(.requestPermissionsTool)
    options.includeRequestUserInput = input.experimentalRequestUserInputEnabled
    options.includeTestSync = tools.contains("test_sync_tool")
    options.includeViewImage = input.hasEnvironment && features.enabled(.viewImage)
    options.includeToolSearch = input.supportsSearchTool
    options.includeExecCommand = shellAllowed
    options.includeWriteStdin = shellAllowed && features.enabled(.unifiedExec)
    options.includeMcpResources = input.hasMcpServers
    options.includeWaitForEnvironment = features.enabled(.deferredExecutor)
    return options
}

func finalizeToolRouter(_ options: ToolRouterPlanOptions = ToolRouterPlanOptions()) -> ToolRouter {
    var registry = HarnessToolRegistry()
    var specs: [ToolSpec] = []

    func add(_ runtime: any CoreToolRuntime, exposure: ToolExposure? = nil) {
        let resolved = exposure ?? runtime.exposure()
        registry.register(runtime, exposure: resolved)
        if resolved.isDirect() {
            specs.append(runtime.spec())
        }
    }

    if options.includeCurrentTime { add(CurrentTimeHandler()) }
    if options.includeSleep { add(SleepHandler()) }
    if options.includePlan { add(PlanHandler()) }
    if options.includeNewContextWindow { add(NewContextWindowHandler(), exposure: .directModelOnly) }
    if options.includeGetContextRemaining { add(GetContextRemainingHandler()) }
    if options.includeSendMessageToUserAsync {
        add(SendMessageToUserAsyncHandler(), exposure: .directModelOnly)
    }
    if options.includeRequestPermissions { add(RequestPermissionsHandler()) }
    if options.includeRequestUserInput { add(RequestUserInputHandler(), exposure: .directModelOnly) }
    if options.includeTestSync { add(TestSyncHandler()) }
    if options.includeViewImage { add(ViewImageHandler()) }
    if options.includeToolSearch { add(ToolSearchHandler()) }
    if options.includeExecCommand { add(ExecCommandHandler()) }
    if options.includeWriteStdin { add(WriteStdinHandler()) }
    if options.includeMcpResources {
        add(ListMcpResourcesHandler())
        add(ListMcpResourceTemplatesHandler())
        add(ReadMcpResourceHandler())
    }
    if options.includeWaitForEnvironment { add(WaitForEnvironmentHandler()) }

    return ToolRouter(
        registry: registry,
        modelVisibleSpecs: specs,
        toolMode: options.toolMode,
        canManageChildren: false
    )
}

/// rust `append_dynamic_tool_runtimes`.
func appendDynamicToolRuntimes(_ specs: [DynamicToolSpec], on router: inout ToolRouter) {
    for handler in dynamicToolHandlers(specs) {
        let qualified = handler.toolName().withDefaultNamespace()
        if qualified.isDefaultNamespace(),
           qualified.name == "exec_command" || qualified.name == "shell_command" {
            continue
        }
        if router.registry.entry(for: handler.toolName()) != nil {
            continue
        }
        let exposure = handler.exposure()
        router.registry.register(handler, exposure: exposure)
        if exposure.isDirect() {
            appendModelVisibleDynamicSpec(handler.spec(), on: &router)
        }
    }
}

func dynamicToolHandlers(_ specs: [DynamicToolSpec]) -> [DynamicToolHandler] {
    var handlers: [DynamicToolHandler] = []
    for spec in specs {
        switch spec {
        case .function(let tool):
            if let handler = DynamicToolHandler(tool) {
                handlers.append(handler)
            }
        case .namespace(let namespace):
            for namespaced in namespace.tools {
                guard case .function(let tool) = namespaced else { continue }
                if let handler = DynamicToolHandler(tool, namespace: namespace) {
                    handlers.append(handler)
                }
            }
        }
    }
    return handlers
}

/// rust `merge_into_namespaces` for the specs just appended.
func appendModelVisibleDynamicSpec(_ spec: ToolSpec, on router: inout ToolRouter) {
    guard case .namespace(var namespace) = spec else {
        router.modelVisibleSpecs.append(spec)
        return
    }
    if let index = router.modelVisibleSpecs.firstIndex(where: { existing in
        if case .namespace(let current) = existing { return current.name == namespace.name }
        return false
    }), case .namespace(var existing) = router.modelVisibleSpecs[index] {
        if existing.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !namespace.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            existing.description = namespace.description
        }
        existing.tools.append(contentsOf: namespace.tools)
        existing.tools.sort { $0.function.name < $1.function.name }
        router.modelVisibleSpecs[index] = .namespace(existing)
        return
    }
    namespace.tools.sort { $0.function.name < $1.function.name }
    router.modelVisibleSpecs.append(.namespace(namespace))
}
