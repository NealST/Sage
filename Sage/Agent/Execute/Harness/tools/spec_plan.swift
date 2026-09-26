//
//  spec_plan.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/spec_plan.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Feature/config-driven planning waits for Phase 5 Config. This builder
//  registers the Phase 4 handlers that do not need Session.
//

import CodexProtocol

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

func finalizeToolRouter(_ options: ToolRouterPlanOptions = ToolRouterPlanOptions()) -> ToolRouter {
    var registry = HarnessToolRegistry()
    var specs: [ToolSpec] = []

    func add(_ runtime: any CoreToolRuntime) {
        registry.register(runtime)
        specs.append(runtime.spec())
    }

    if options.includeCurrentTime { add(CurrentTimeHandler()) }
    if options.includeSleep { add(SleepHandler()) }
    if options.includePlan { add(PlanHandler()) }
    if options.includeNewContextWindow { add(NewContextWindowHandler()) }
    if options.includeGetContextRemaining { add(GetContextRemainingHandler()) }
    if options.includeSendMessageToUserAsync { add(SendMessageToUserAsyncHandler()) }
    if options.includeRequestPermissions { add(RequestPermissionsHandler()) }
    if options.includeRequestUserInput { add(RequestUserInputHandler()) }
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
