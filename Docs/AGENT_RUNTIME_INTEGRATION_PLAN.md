# Sage Agent Runtime 整合计划 — Plan / Execute / Review 全 runtime 化

> **目标**：把已移植的 Codex agent runtime（`Sage/Harness/`，下称 harness）与 Sage 的三层编排（Plan → Execute → Review）整合为**每阶段都是完整 agent runtime**：同一套回合循环、工具编排、审批、压缩、rollout，阶段之间只有行为配置与输出契约的差别。同时把双轨工具系统收口到 harness 侧单一组装点。
>
> **上游关系**：harness 的忠实度目标与文件映射仍以 `EXECUTE_HARNESS_PORT_PLAN.md` 为准；本计划只动**接线与整合**，不新增 codex 侧忠实度欠债（新增机制按 R8 标注 Sage addition）。产品路线（HUD、Schedules、UI）仍以 `DEVELOPMENT_ROADMAP.md` 为准。
>
> **状态**：M0–M5 全部完成（2026-10-15 至 2026-10-20）。三阶段全 runtime 形态收口；后续维护见 §5 各里程碑落地记录。

---

## 1. 背景与决策

### 1.1 现状一句话

Execute 已经是完整 runtime（`RegularTask` → `ExecuteHarnessAttach` → `Session.spawnTask(RegularSessionTask)` → `runTurn`，`regular.swift:791`）；Plan 是 app 侧一次性无工具采样（`PlanAgent.propose` → `streamCustom`）；Review 是 app 侧自建的 6 轮只读检查循环（`ReviewAgent+Inspect.swift:9`，走 `completeUnstreamedTurn` + ToolOrchestrator）；Explore 走旧 `Turn.run` 双轨（`ExploreSubagentRunner` → `ExploreTask`）。工具系统单向打通（名字注册 + `onSageToolCall` 收敛），但 harness 端 Sage 工具只有名字没有 schema（`sage_execute.swift:27`），可见性逻辑分居两处。

### 1.2 已确认的架构决策（2026-10-14）

| # | 决策点 | 结论 |
|---|---|---|
| D1 | 阶段线程拓扑 | **单线程分阶段**：一个 task 一个 root `SageThread` 贯穿三阶段；每阶段 = 一次 `runTurn`，配各自的 TurnContext（工具集 / 模型角色 / 提示词）。历史连续，transcript / rollout 按 task 统一。TurnCoordinator 仍是产品编排者。 |
| D2 | 阶段工具面 | **Plan 只读 + Review 只读**：Plan 用小只读集（list / read / search / view_image），Review 用现有 8 个只读检查工具跑完整回合。 |
| D3 | Explore 收敛 | **并入本次**：`explore_subagent` 收敛到 spawn/wait，删 `ExploreSubagentRunner` 双轨。前置能力（子 agent 只读工具过滤）与阶段拓扑同源。 |
| D4 | 工具整合深度 | **harness 为唯一组装点**：`assembleToolRouter` 成为模型可见工具的唯一组装处；Sage 工具带真实 schema 进 harness；`AgentModelGateway.availableToolDefinitions` 退役为兼容层。 |

### 1.3 核心设计原则

1. **阶段是 app 概念，机制是 harness 通用能力**。harness 只获得通用机制（工具白名单、按回合模型租约、提示词覆盖、spawn/wait）；「plan / review 是什么、输出什么」全部留在 app 粘合层。禁止 harness 长出 Sage 产品语义（对应移植计划 §4.2 分层禁令）。
2. **TurnCoordinator 不变成 ThreadManager 门面**（移植计划 §2.5）。它提交阶段化输入、读回合结果、管确认卡与返工循环；线程与回合的生命周期归 harness。
3. **同一机制不得有两份语义**（移植计划 §4.3）。本计划的每一项收敛都以「调用点原子切换」为单位推进：新路径接通并验收后，旧路径当期删除。
4. **产品可见行为不回归**：确认卡、流式 UI、Stop、审批卡、GRDB task / Recents 的行为与现在一致。

---

## 2. 现状盘点（关键接线点）

### 2.1 编排层（app）

- `TurnCoordinator`（`Agent/Orchestration/TurnCoordinator.swift:13`）持 `planner: PlanAgent`、`execute: RegularTask`、`reviewer: ReviewAgent`（:26–28）。主循环在 `TurnCoordinator+Loop.swift`：`presentWorkPlan`(:10) → 确认 → `startExecution`(:139) → `execute.start()` → `onCandidateReply` → `reviewAndFinish`(:150) → `applyReviewVerdict`(:180)（must-fix ≤ 2 轮返工）→ `finalizeAssistantText`(:322)。
- Plan：`PlanAgent`（`Agent/Plan/PlanAgent.swift:22`）→ `streamCustom`（`AgentModelGateway+CustomStream.swift:55`）一次性采样，`PlanStreamAdapter` 解析出 `WorkPlan`（kind = answer / observe / act）。
- Review：`ReviewAgent`（`Agent/Review/ReviewAgent.swift:37`）自建循环——`maxInspectRounds = 6` 轮 `completeUnstreamedTurn`（带 8 个只读工具，:42–51）+ 外层 `maxAttempts = 3` 重试；不走 harness。
- 持久化唯一写路径 `AgentTaskStore.commit`（`Agent/AgentTaskStore.swift:62`）→ GRDB。

### 2.2 Execute 与 harness 的接法（整合的样板）

- `RegularTask.start()`（`Harness/tasks/regular.swift:254`）→ `attachExecuteHarness`(:270)：`ExecuteHarnessAttach.makeSession`（`execute_attach.swift:53`）/ `makeTurnContext`(:147) / `leaseResponsesClient`(:117–132) → `runHarnessTurn`(:791–815) → `session.spawnTask(RegularSessionTask)` → harness `runTurn`（`session/turn.swift:129`）。
- 采样双路径：`runSamplingStreamOverride`（`regular.swift:370`）优先 Responses 客户端（`openModelSample` :503），回退 `AgentModelGateway.streamComplete`（:516–541）。
- 工具收敛缝：`assembleToolRouter`（`session/turn.swift:559`）→ `registerSageTools(sess.services.sageToolNames)`(:590)（空 schema 占位，`sage_execute.swift:27`）；调用时 `registry.dispatch` 未命中 → `handleRegisteredOrSage`（`registry.swift:176`）→ `onSageToolCall` → `dispatchSageTool`（`regular.swift:568`）→ `invokeHarnessTool`（`AgentRuntime+Chrome.swift:150`）→ `ExecuteServices.executeToolInvocation`（`ExecuteServices.swift:53`）→ `ToolOrchestrator` → `ToolInvocationDispatcher`。
- MCP 桥：`installHarnessMcpBridge`（`regular.swift:757`）把 `CapabilityStore` 折叠成 `mcpVisibleTools` / transport 闭包。
- 审批共享：`state.sessionAllowlist.approvalStore`（`SessionToolAllowlist.swift:16`，即 harness `ApprovalStore`，`approvals.swift:204`）attach 进 session（`regular.swift:302`）。
- 多 agent：`attachThreadManager`（`regular.swift:331`）复用跨 attach 存活的 `harnessThreadManager`，`adoptRootThread`(:341–346) 注册父线程不开第二采样循环；spawn 走 `SpawnAgentHandler.handle`（`tools/handlers/multi_agents/spawn_agent.swift:88`）→ `control.spawn`（`agent/control.swift:327`）→ `insertLiveThread`（`thread_manager.swift:390`）→ 子 `SageThread.openLiveSession`（`sage_thread.swift:170`）。

### 2.3 差距清单（要收掉的）

| # | 差距 | 位置 |
|---|---|---|
| G1 | Plan / Review 不经 harness：无 rollout、无统一事件流、无统一中断/预算 | `PlanAgent` / `ReviewAgent` |
| G2 | harness 端 Sage 工具空 schema，全靠 `sageResponsesTools` 旁路补全 | `sage_execute.swift:27`、`turn.swift:659` |
| G3 | 工具可见性逻辑分居两处：Sage 侧 `availableToolDefinitions()`（`AgentModelGateway.swift:74–104`：act-only todo、SkillToolPolicy、MCP 折叠）vs harness 侧 `planCoreToolOptions` / `ToolExposure` | 两处 |
| G4 | Explore 双轨：`ExploreSubagentRunner`（`Agent/Execute/ExploreSubagentRunner.swift:14`）→ `ExploreTask`（`Harness/tasks/explore.swift:15`）走旧 `Turn.run`（`turn.swift:56`） | 见 §5 M4 |
| G5 | Session 每次 start/continue 重建（attach :270），阶段间无历史连续性 | `regular.swift` |
| G6 | 阶段无工具白名单机制：只读约束靠 app 侧各写一份（Review 的 `inspectToolNames`、Explore 的 `allowedNames`、`assertMutatingToolsAllowed`） | 三处 |

---

## 3. 目标架构

```
┌─ App 层 ─────────────────────────────────────────────────────
│  TurnCoordinator（产品编排：确认门、返工循环、task 落盘）
│    ├─ planner  : PhaseTurnRunner(.plan)   → WorkPlan
│    ├─ execute  : RegularTask（现状，改挂同一 task Session）
│    └─ reviewer : PhaseTurnRunner(.review) → ReviewVerdict
│  PhaseProfile（app 粘合层）：阶段语义（提示词/工具集/模型角色/输出契约）
├─ 适配层（现有缝，全部复用）──────────────────────────────────
│  ResponsesClientLease（按 ModelRole 取租约）/ runSamplingStreamOverride
│  onSageToolCall → ExecuteServices → ToolOrchestrator（不变）
│  installHarnessMcpBridge / SessionToolAllowlist↔ApprovalStore（不变）
├─ Harness 层（新增通用机制，全部标注 Sage addition）──────────
│  TurnContext.toolAllowlist（回合级工具白名单）
│  SessionServices.sageToolSpecs（真实 schema 的 Sage 工具清单）
│  spawn 携带 role → 子线程 TurnContext 白名单（explorer 只读）
│  单 root SageThread：plan / execute / review 各一次 runTurn
└──────────────────────────────────────────────────────────────
```

**一个 task 的生命周期**（D1 单线程拓扑）：

```
root SageThread（rollout 按 task）
 ├─ Plan runTurn    planner TurnContext：只读小集 + plan 模型 + plan 提示词
 │    → WorkPlan（解析最终消息）；act 类计划 → app 确认卡（awaitingApproval）
 ├─ Execute runTurn 现有 RegularTask 全量（含 spawn/wait/interrupt）
 │    → 执行 + workspaceChanges diff
 ├─ Review runTurn  reviewer TurnContext：只读 8 工具 + review 模型 + brief
 │    → ReviewVerdict；must-fix → 同 session 提交返工输入（≤2 轮）
 └─ （任务内任意阶段）explore_subagent → spawn explorer 子 agent + wait
```

---

## 4. 关键设计

### 4.1 工具白名单：`TurnContext.toolAllowlist`（harness 通用机制）

- `TurnContext`（`session/turn_context.swift`）新增 `toolAllowlist: Set<String>?`（nil = 不限，按现有 `planCoreToolOptions` / MCP exposure 规则组装）。文件头标注 Sage addition，说明对应 Sage 阶段与子 agent 过滤两用。
- `assembleToolRouter`（`turn.swift:559`）在现有组装完成后按白名单过滤 `modelVisibleSpecs`，且不注册白名单外的 handler。
- **双保险**：`HarnessToolRegistry.dispatch`（`registry.swift:104`）校验 invocation 所属回合的白名单，越界返回 `FunctionCallError.respondToModel`（对齐 `ExploreTask` 现在采样过滤 + 派发拒绝的两道门，但下沉为 harness 机制，替代 G6 的三份 app 侧各写）。
- 白名单同时作用于：①root 线程的阶段回合（Plan / Review）；②spawn 出的子线程（role 驱动，见 §4.6）。Explore 收敛与阶段过滤共用这一条机制（D3 与 D1 的公共前置）。
- 只读约束不再需要 app 侧 `assertMutatingToolsAllowed`、`screenMutations` 对 Plan/Review 回合生效（Execute 回合内的 act-only 检查暂保留，归 M5 评估收口）。

### 4.2 阶段回合运行器：`PhaseTurnRunner`（app 粘合层）

新文件 `Agent/Execute/PhaseTurnRunner.swift`（Sage addition）。职责是「用 harness 原语跑一个阶段回合」，不做阶段语义判断：

1. attach 一个阶段配置的 Session（复用 `ExecuteHarnessAttach`，参数化：`ModelRole` 租约、`toolAllowlist`、`prepareSamplingPrompt` 的阶段提示词）；初期沿用「每次 attach 从 `state.events` 重建历史」的现状机制（见 §4.4 的 M3 升级）。
2. `session.spawnTask(RegularSessionTask)` + 提交阶段输入；事件映射复用 `regular.swift` 现有路径（工具结果 `recordHarnessToolResult`、文本流经 `runSamplingStreamOverride` → `StreamingTextPump`，Plan 阶段流式 UI 不回归）。
3. 采样不经工具批次 HUD 门（阶段回合无 pendingPlan；`admittedGate` 只在 Execute 路径生效）。
4. 返回回合最终文本 + 工具事件序列；Stop/中断经 `sendOp` 打断（复用现有 interrupt 通道）。

`PhaseProfile`（app 侧值类型，与 harness 无关）：

```swift
struct PhaseProfile {
    var kind: PhaseKind                 // .plan / .review
    var modelRole: ModelRole            // ModelSettings.snapshot(for:)
    var toolAllowlist: Set<String>      // D2 的两个只读集
    var prompt: (AgentSessionState, WorkPlan?) -> String   // plan 提示 / review brief
    var outputParser: (String) -> ...   // PlanStreamAdapter / ReviewVerdict JSON
}
```

### 4.3 Plan / Review 的输入、输出与循环语义

- **Plan**：输入 = 会话历史（attach 映射）+ plan 提示词；工具 = `list_directory` / `read_text_file` / `search_files` / `view_image`；输出 = 最终消息经 `PlanStreamAdapter` 解析为 `WorkPlan`（解析器不动）。act 确认卡、`replaceUnconfirmedPlanIfNeeded`、主题漂移提示等 app 流程不变。
- **Review**：输入 = brief（沿用 `ReviewAgent.brief` 组装：用户文本 + WorkPlan + 草稿 + 沙盒边界 + `workspaceChanges.snapshot().inspectPlaces()`）；工具 = 现有 8 个只读检查工具（`ReviewAgent.swift:42–51`）；输出 = 最终消息解析 `ReviewVerdict`（JSON 解析不动）。
- **检查循环的形态变化**：现在的「6 轮 inspect 循环」变成**一个 runTurn 内模型自主决定调用多少次只读工具**（这正是回合循环的本义）；`maxAttempts = 3` 外层重试保留（解析失败时 TurnCoordinator 重提）。轮次预算改由 TurnContext 的 token / 工具调用预算承担；若行为测试发现失控，再补回合级工具调用数上限。
- **返工循环**：`applyReviewVerdict` 的 must-fix 分支从「`execute.resetLoop()` + 重启」改为「同一 session 提交返工输入」（M3 后生效；M1–M2 期间维持现状重启路径）。

### 4.4 Session 生命周期与 task 对齐（单写者规则）

- **目标态**：一个 task 一次 attach；plan → execute → review → 返工全部在同一 `Session` / root `SageThread` 上提交；rollout 按 task 开启（现有 `enableRolloutPersistence`，`regular.swift:323`）。
- **单写者规则**：live 期间 harness history 是权威；`AgentEvent`（UI 投影）只由 harness 事件映射产生（现有 `recordHarnessToolResult` 等已是这个方向）；删除 attach 时「`state.events` → harness history」的反向映射，仅保留两个恢复场景使用：进程重启 / Recents 切线程后的 task 续跑。
- **迁移策略**：M1 / M2 的阶段回合先用「每阶段 attach 一次」的过渡形态（历史连续性由 events 映射保证，与 Execute 现状同级）；M3 才切持久 Session。这样 Review / Plan 的 harness 化收益（工具、事件、中断、rollout）先行落地，最大的双写收敛风险后置且有恢复路径。

### 4.5 Explore 收敛（D3）

- 前置（M0）：spawn 链路携带 role → 子线程 TurnContext 白名单。`SpawnConfigOptions` 已有 `roleName`（`child_config.swift:36`；注意 `prepareAgentSpawnConfig` :54 仍是 throw 的移植欠债，实路径走 `control.spawn`，白名单从 `SpawnRequest` / spawn source 传给 `SageThread.openLiveSession` → 子 TurnContext）。
- 内建 `explorer` 角色（agent-roles，`agent/role.swift` + `agent-roles/` 加载器）：只读工具集 + 6 轮预算等价约束。
- `explore_subagent` 工具（Sage 工具，经 `onSageToolCall` 缝）实现改为：`control.spawn`（explorer role，不带 fork）→ `subscribeStatus` 等待完成（对齐 `wait_agent.swift:118` 的订阅方式，带超时）→ 子线程最终 assistant 消息作为工具输出返回。
- 删除：`ExploreSubagentRunner`、`ExploreTask`、`ExploreSubagentRunner.invokeExploreCall` 的只读守门（由白名单替代）；审计 `Turn.run`（`turn.swift:56`）剩余调用点（`RegularTask.handleTurn` 兜底，`regular.swift:678`）——若兜底仅为旧路径容错则一并退役 `ExecuteTurnLoop`，若仍有恢复语义则保留并文档化。

### 4.6 工具系统收口（D4）

**目标：`assembleToolRouter` 是模型可见工具的唯一组装点。**

| 事项 | 改动 |
|---|---|
| 真实 schema | `SessionServices.sageToolNames: [String]` → `sageToolSpecs: [SageToolSpec]`（name + description + parameters + requiresConfirmation）；`registerSageTools`（`sage_execute.swift:59`）用真实 spec 注册；attach 侧把 `ToolDefinition` 的 JSON schema 映射为 `JsonSchema`。MCP 工具仍走 `registerMcpTools` 先注册（现有去重顺序已保证 MCP 优先，`turn.swift:587→590`） |
| 删旁路 | `builtTools`（`turn.swift:659`）删 `sageResponsesTools` 分支，一律从 `router.modelVisibleSpecs` 出全量 schema；`bindHarnessSampling`（`regular.swift:356`）不再写 `sageResponsesTools`。token 成本与现状持平（两条模型路径本就一个全 schema 一个全定义） |
| 可见性归属 | ①`manage_todo_list` act-only（`AgentModelGateway.swift:84`）→ Execute 阶段白名单携带（plan / review 不含）；②`SkillToolPolicy.filterDefinitions` → attach 期计算 spec 列表时执行（仍由 `prepareSamplingPrompt` 提供技能上下文）；③MCP `mcp_group__` 折叠（20 个未解锁 server）→ 保留在 `mcpVisibleCatalog` 桥闭包里（产品语义，留在适配层是对的）；④`recall_task_transcript` → attach 期按工作记忆存在与否加入 |
| 退役兼容 | `AgentModelGateway.availableToolDefinitions()` 改为仅供 attach 期取全量定义 + 兼容旧路径调用点；M5 结束后审计剩余调用者 |

**收口后的可见性决策表**（唯一事实源）：

| 规则 | 归属 | 机制 |
|---|---|---|
| 阶段工具集（plan / review 只读，execute 全量 + todo） | app PhaseProfile | `TurnContext.toolAllowlist` |
| 子 agent 工具集（explorer 只读） | agent-roles 角色 | spawn → 子 TurnContext 白名单 |
| MCP direct / deferred / hidden、Apps 过滤、字节预算 | harness | `mcp_tool_exposure`（现状不动） |
| 核心工具门控（plan 工具、request_user_input 等） | harness | `planCoreToolOptions`（现状不动） |
| skill 过滤、MCP 折叠、工作记忆工具 | 适配层 | attach 期 spec 列表 / catalog 闭包 |

---

## 5. 分阶段实施

> 每个里程碑独立可交付、可构建、可回归；顺序按依赖排（M0 是 M1/M2/M4 的公共前置）。文件行号以 2026-10-14 盘点为准。

### M0 — 底层机制（harness 通用能力，无产品行为变化）✅ 已完成（2026-10-15）

**范围**：
1. `TurnContext.toolAllowlist` + `assembleToolRouter` 过滤 + `registry.dispatch` 越界拒绝（§4.1）。
2. `sageToolSpecs` 真实 schema 通道 + `registerSageTools` 改造 + 删 `sageResponsesTools` 旁路（§4.6 前两行）。
3. spawn → 子线程白名单传递 + 内建 `explorer` 角色（§4.5 前置）。子线程走 `ThreadManager.childModelTools(for:)` → `ModelClientTurnSampler.tools` 组装门 + `ThreadSession.functionCallOutputs` 派发门（双门对齐 §4.1）。

**验收**：现有测试全绿（`SageTests/Harness/**`、TurnTests、ToolLoopPolicyTests）；新增单测：白名单过滤（组装 + 派发双门）、真实 schema 注册 round-trip（spec 名 / 描述 / 参数与 `ToolDefinition` 一致）、explorer 角色子线程只读、`builtTools` 全量输出与旧 `sageResponsesTools` 输出语义等价（golden 对拍）。

> 落地记录：app 侧 4 个 Harness 测试类 220 全绿；包侧 Phase9AgentTests 54 全绿（含 4 个新 e2e/单元测试）。泛用回合机械测试（`testRegularTurnRunsToolsThenSamplesAgain` / `testRegularTurnInterruptAbortsToolFollowUp`）的 spawn 角色从 "explorer" 改为 nil——explorer 角色现在带只读门，这两处测的是通用机械而非角色语义。

### M1 — Review 阶段 harness 化 ✅ 已完成（2026-10-15）

**范围**：`PhaseTurnRunner`（§4.2）；`ReviewAgent.evaluate` 内部换 PhaseTurnRunner，brief 组装与 verdict 解析保留；inspect 循环 → 单回合自主检查（§4.3）；评审事件（工具调用 / 结果）进 transcript 与 `state.events`；Stop 可中断 review 回合。

**不动**：`maxAttempts` 重试、`applyReviewVerdict` 的返工重启路径（M3 才改）、确认卡。

**验收**：Review 行为回归——8 只读工具可用、mutating 工具被拒（错误消息对齐现有 `assertMutatingToolsAllowed` 文案）、mustFix / optional 输出格式不变、评审过程在 UI 可见（流式 + 工具事件）、中断生效；ReviewAgent 相关现有测试改走新路径后全绿。

> 落地记录：新增 `Sage/Agent/Execute/PhaseTurnRunner.swift`（app 粘合层，§4.2 全量落地）：每阶段回合 attach 一个一次性 Session——全量工具经 `sageToolSpecs` 注册、`TurnContext.toolAllowlist` 同时收窄模型可见集（`assembleToolRouter`）与派发集（`registry.dispatch`），mutating 调用在到达 handler 前被 M0.1 注册表门拒绝（"tool X is not available this turn"）。CancellationToken 经 `withTaskCancellationHandler` 桥接外层 Task 取消，对齐 `runHarnessTurn` 的 spawn 后检查（`token.isCancelled || lastTurnAbortReason != nil` → CancellationError）。采样优先走 Responses 直连（`runSamplingStreamOverride`，404 时置 `responsesTransportUnavailable` 并回落 `modelGateway.completeUnstreamedTurn` chat-completions 路径）；`modelSampler` / `dispatchTool` 为测试缝。工具调用与结果经 `taskStore.commit` 落 transcript（`assistantResponse(toolCalls:)` + `toolResult` 事件对，UI 工具芯片即来自这对事件）。
>
> `ReviewAgent` 持有常驻 `phaseRunner`（init 时接好 `dispatchTool → invokeInspect`，`taskStore` 由 `TurnCoordinator` 传入）；`inspect(brief:)` = 单个阶段回合，`maxInspectRounds`（6 轮固定循环）删除；`evaluate` 的 brief 组装、`parse`、`maxAttempts=3` 不动。`skillHost` 为空时白名单置空，回合退化为纯文本。
>
> 与验收原文的两处有意偏差：① mutating 拒绝消息走 M0.1 统一注册表门（D4 单一门），不再是 `assertMutatingToolsAllowed` 文案——后者保留给 Execute 的 app 层路径，`invokeInspect` 另留 "Review cannot call 'X'" 应用层兜底；② 评审文本有意不接 StreamingTextPump（草稿已由 `reviewAndFinish` 先行 flush，评审不打断正文流式），UI 可见性 = transcript 工具事件 + `state.isReviewing`。
>
> 顺手修了一个真实 bug：`AgentTaskStore.commit` 的读-改-写横跨 DB await，两个并行工具结果的提交会交错，后到的 `adoptTaskInMemory` 覆盖前者事件（并行只读工具下 transcript 丢事件，Execute 同样潜伏此问题）——加了 FIFO 交接锁串行化 commit。`PhaseTurnRunnerTests.testInspectRunsToolsAndParsesVerdict` 捕获该问题。
>
> 测试：新增 `SageTests/PhaseTurnRunnerTests.swift` 5 个用例（8 只读工具集 + brief + systemPrompt 进 prompt、工具轮 + verdict + transcript 事件、mutating 注册表门前拒绝、Stop 中断、skillHost 空文本化、不可用输出耗尽 maxAttempts）全绿；ReviewAgentTests 10 全绿；app 全量 667/668（唯一失败 `ContextBudgetTests.testProtectedSkillSurvivesAFoldRange` 经干净 HEAD worktree 复跑确认为既有失败，与 M1 无关）；包侧 `swift test` 全绿；双构建通过。

### M2 — Plan 阶段 harness 化 ✅ 已完成（2026-10-16）

**范围**：`PlanAgent.propose` 换 PhaseTurnRunner（planner profile：4 只读工具 + plan 模型角色 + 流式桥接）；`PlanStreamAdapter` 解析最终消息；`judgePersistence` 判定入口不动。

**验收**：plan 流式 UI 不回归（文本经 StreamingTextPump 实时显示）、WorkPlan 三种 kind 解析正常、observe / answer 阶段无副作用工具、act 确认卡流程不变、plan 回合可 Stop。

> 落地记录：`PlanAgent` 持常驻 `phaseRunner`（对齐 M1 的 ReviewAgent 形态），`TurnCoordinator` 构造 planner 时传入 `taskStore`、`bind` 时设 `skillHost`。propose = 单个阶段回合：全量工具经 `sageToolSpecs` 注册，`TurnContext.toolAllowlist` = D2 的 plan 只读集（`PlanAgent+Harness.swift` 的 `planToolNames`），mutating 调用被 M0.1 注册表门在到达 handler 前拒绝。brief 组装（thread context + skill appendix）、`resolveProposal` / `PlanStreamAdapter` 解析管线、`judgePersistence` 全部不动。
>
> 流式桥接（PhaseTurnRunner 新增通用机制）：`onTextDelta` / `onThinkingDelta` / `onSampleStart` 三个观察者。Responses 直连路径 tee provider 的 `outputTextDelta` / reasoning delta（`teeSampleDeltas`）；缓冲采样器（测试缝）与 chat-completions 回退路径把整段消息作为单个 delta 喂入（`feedTextDeltas`）——三条路径语义一致。`onSampleStart` 在每个采样轮开始时重置流式缓冲，对齐 Execute `collectStream` 的 per-round 边界（工具后继轮的文本替换上一轮而非拼接）。app 侧 `PlanTextStreamBuffer`（PlanAgent+Harness.swift）把 delta 经 PlanStreamAdapter 过滤后喂 StreamingTextPump：prose 实时显示、JSON 保留工作计划卡片占位（`setReservingWorkPlan`）、thinking 累积发布——与旧 `streamCustom` onText 路径逐行为对齐。回合最终消息（`lastTaskAgentMessage`）是解析的权威来源，流式累积仅兜底「最后一轮无文本」的回合。
>
> 有意偏差：① `view_image` 在 `planToolNames` 中占位但暂不模型可见——harness 的 tool output→图像输入转换是移植欠债（view_image.swift Phase 5–6），现在广告它只会给模型喂 base64 文本墙；欠债清偿后从 `planToolDefinitions()` 一行启用。模型可见集因此是 3 工具（list / read / search），验收按此执行。② `AgentModelGateway.streamCustom` 随调用点清零删除（原子切换原则）；`completeUnstreamed` 保留给 `judgePersistence`（M2 明确不动）。
>
> 测试：新增 `SageTests/PlanAgentHarnessTests.swift` 8 个用例（工具轮 + act plan 解析 + 流式 + 卡片占位、answer 直接回复流式、observe 无需确认、skill 名过滤、mutating 注册表门前拒绝、skillHost 空文本化、Stop 中断、不可解析输出抛错）全绿；PhaseTurnRunnerTests 5 + ReviewAgentTests 10 + PlanStreamAdapterTests 11 + WorkPlanTests 13 回归全绿（47/47）。

### M3 — Session 与 task 对齐（单线程拓扑落定） ✅ 已完成（2026-10-19）

**范围**：attach 一次 / task；三阶段与返工循环在同一 Session 提交（§4.4）；must-fix 返工 = 同 session 新输入；「events → history」反向映射收缩到恢复场景；rollout 按 task 开启并验证续跑。

**验收**：Review 回合能看到 plan 确认与执行全史 + diff（历史连续性核心用例）；must-fix 返工闭环（≤2 轮）在同一 session 上完成；进程重启 / Recents 切换后 task 恢复正常（重建路径）；`turnLoopByTask` 状态与 session 生命周期对齐无泄漏。

> 落地记录：新增 `Sage/Agent/Execute/TaskHarness.swift`（Sage addition）：一个 task 一个持久 harness Session / root SageThread。`TurnCoordinator.ensureTaskHarness()` 懒创建；`adoptActiveTask()`（Recents 切换）发现 task 变更即 `retireTaskHarness()`（后台 shutdown，在飞回合随之中止），下次 ensure 以一次性 events→history 反向映射重建——§4.4「反向映射收缩到恢复场景」即此：创建后所有回合只 append。`harnessIdentity` 按 task 记 threadId + rollout 路径，重建时 `restoreVerifiedAnswers` + `resumeRolloutPersistence` 续写同一 rollout 文件；`dropTurnLoop` 删任务时 `discardTaskHarness` + 清身份；`turnLoopByTask` 的存取与 harness 退役同在 adopt / drop 两点，无泄漏。harness 另持有 per-task `ThreadManager`、按 "baseURL\napiKey" 的 Responses 租约池（阶段角色与 Execute 共享 wire 身份）与 per-baseURL 404 标记；`prepareExecuteTurn()` 在每个 Execute 回合前刷新模型租约 / hooks / MCP / 子工具快照（Execute 侧 M3 前置工作，此处收口）。
>
> 三阶段同 session：`PhaseTurnRunner` 新增 `harnessProvider`，`TurnCoordinator` 构造时把 planner / reviewer / execute 全部接 `ensureTaskHarness()`。阶段回合不再自建一次性 Session，而是在 task session 上 spawn `RegularSessionTask`，经 M1 引入的 `TurnServiceOverrides` 做回合级服务租借：`baseInstructions`（阶段提示词）、`runSamplingStreamOverride`（阶段角色采样——每回合 mint 一枚 phase-role client session，404 时标记 harness 并回落 chat-completions，跨回合共享）、`onSageToolCall`（阶段工具派发）、`sageToolSpecs`（本回合 Sage 工具注册集）。harness 配套新增 `TurnServiceOverrides.sageToolSpecs`：`assembleToolRouter` 优先注册回合级 spec 而非 session 槽位（上一 Execute 采样轮可能已把槽位清空，如 `finishWithoutMoreTools` 置空之后）。阶段回合不写 session 级 sampling / Execute 槽位；`TurnContext.toolAllowlist` 照旧双门收窄。`harnessProvider` 为空或 harness 已 shutdown 时回落 M1 的一次性 session 路径（R1 的恢复回退）。
>
> must-fix 返工 = 同 session 显式输入：`ExecuteTurnInputMode` 新增 `.text(String)`；`RegularTask.startRework(_:)` 在 task session 上直接提交返工输入（不做 events 重建），synthetic user turn 只进 session、不进 `state.events`，UI transcript 不受污染。`applyReviewVerdict` must-fix 自动分支、`resumeMustFixReview`、`applyOptionalReview` 三处由「`resetLoop()` + 重启」改为 `startRework(Self.reworkUserText(message))`。反馈双载体：显式输入覆盖 live（评审历史就在 session 里，模型直接看到上一轮草稿与 verdict 上下文），`state.reviewFeedback` 系统提示词 appendix 保留——重启重建后 session 无评审历史，appendix 是唯一载体，故不删。
>
> 与验收原文的对应与偏差：①「Review 看到 plan 确认 + 执行全史 + diff」——plan 回合消息、execute 工具调用 / 结果与最终回复经 session history 全量可见（核心用例断言 user input / plan 消息 / execute 回复都在 review prompt 里）；diff 摘要未单独注入 review brief——写入类工具结果本身已在历史中，reviewer 亦可经只读工具自查，是否显式注入 diff 摘要留 M5 评审 brief 收口时评估。② 进程重启未新增端到端测试：恢复 = 懒重建 + 一次性映射 + remembered rollout，与 Recents 切换共用同一代码路径（`testRolloutPathSurvivesTaskSwitchRoundTrip` 已测 remembered 身份续跑）；真重启属 app 级测试宿主，按 M1/M2 同口径靠手动 golden path 收尾。
>
> 测试：TaskHarnessTests 7 全绿（新增 2 个 M3 验收用例：三阶段同 session 历史连续性 + 阶段提示词不污染 Execute 槽位；must-fix 返工同 session 显式输入 + 不落 transcript + 二轮通过后 feedback 清空）；PhaseTurnRunnerTests 5 + PlanAgentHarnessTests 8 自动切到共享 session 路径后原断言全绿（阶段提示词 / 只读工具集 / 注册表门前拒绝 / Stop 中断 / maxAttempts 语义不变，即 M1/M2 行为无回归）；app 全量 688/689——唯一失败 `ContextBudgetTests.testProtectedSkillSurvivesAFoldRange` 与 M1 收尾时相同，干净 HEAD worktree 复跑确认为既有失败，与 M3 无关；M3 全部改动落在 app 目标（session / tasks 目录不进包 target），包侧 `swift test` 全绿。

### M4 — Explore 收敛 ✅ 已完成（2026-10-19）

**范围**：`explore_subagent` 改 spawn explorer + wait + 摘要返回（§4.5）；删 `ExploreSubagentRunner` / `ExploreTask`；处置 `Turn.run` 剩余调用点。

**验收**：explore 工具行为等价（只读、结果摘要形态、超时）；子 agent 状态经 collab turn item 在 UI 可见（对齐 spawn_agent 现有展示）；`ExploreSubagentRunner` 引用清零；全库检索无旧路径调用。

> 落地记录：新增 `Sage/Agent/Execute/ExploreAgentSpawn.swift`：`ExploreSubagentTool`（名称/描述/schema/requiresConfirmation 与旧工具一致）+ `ExploreAgentSpawnRunner` 三步实现——`threadManager.agentControl` 上 `control.spawn`（explorer 角色、`.userInput` 初始输入、不带 fork、parent = task 根线程 `.cli`、depth 1，超深直接报「Agent depth limit reached」）→ `waitForFinalStatuses`（120s，刻意低于 `ToolOrchestrator` 的 130s explore 预算：超时先 interrupt 子线程，调用方拿到明确超时错误而非整批工具调用被杀）→ 子线程 `AgentStatus.completed` 的最终 assistant 消息作为工具输出返回（空/nil 回落默认文案；`.errored` 包装为 ToolError；`.interrupted`（未超时）→ CancellationError；`.shutdown` → 默认文案）。`ExploreSubagentRunner.swift` / `ExploreSubagentRequest.swift` / `Harness/tasks/explore.swift` 删除，全库引用清零。
>
> 只读约束与轮次预算走 §4.5 前置的通用 explorer 角色机制（双门落位）：`role.swift` 公开 `explorerRoleName` / `explorerToolRoundBudget`（6）；子采样器组装门 `ThreadManager.childModelTools` 与子派发门 `ThreadSession.functionCallOutputs` 都按 `roleToolAllowlist("explorer")` = {list_directory, read_text_file, search_files} 收窄，写类调用在到达 handler 前即以模型可见 ERROR 拒绝。轮次预算为 Sage 增补（无 codex 对应）：`runRegularTurn` 中 explorer 子线程派发满 6 个工具批次后，后续调用以「ERROR: Tool-round limit reached. Summarize the evidence gathered so far without tools.」拒绝（不派发）；模型若无视拒绝继续调工具，`toolsRefused` 直接终止回合（有界收敛）。子 agent 状态经 collab turn item 可见：minted `explore-<UUID>` id + 空 turnId（协议不携带 turn id），started / failed / completed 三态对齐 `spawn_agent` 现有展示形态。接线：`AgentHostSurface.runExploreSubagentDelegate`（`AgentSessionGraph` → `TurnCoordinator.runExploreSubagent` → `ensureTaskHarness()`）；三条派发路由（根 Execute 回合 onSageToolCall / 子线程 ExecuteChildToolRunner / skill-fork）都收敛到 `ToolInvocationDispatcher.dispatchSpecializedTool`。`TaskHarness.prepareExploreSpawn()`：skill-fork 可能在任何 Execute 回合前触发 explore，此处补挂模型租约（runner 门卫接受 modelClient 或手动 turnSampler 两条采样路径）。
>
> 旧路径整体退役（R5 处置 = 退役，非文档化保留）：审计确认 app 层批次运行器环（`executeCurrentPlanUnlocked` → `ToolBatchExecutor.execute` → `sampleNextTurn` 分支 → `continueTurn` → `TurnCoordinator.handleTurn` → `RegularTask.handleTurn` → `Turn.run` / `ExecuteTurnLoop` → `runToolTurn` → runToolBatch 闭包回到起点）自 M3 收敛后已无外部调用者，全链删除：包侧 `Turn` / `ExecuteTurnLoop` 协议；app 侧 `ToolBatchExecutor.execute` / `finishSuccessfulBatch` / `prepareForResume` / `FollowUp`、`executeCurrentPlanUnlocked`、`RegularTask` 的 ExecuteTurnLoop 一致性与 `handleTurn` / `willSample` / `sample` / `consume` / `runToolTurn` / `injectHookContexts` / `pauseForToolRoundLimit` 及死变量、`TurnCoordinator.handleTurn` / `canOfferMoreTools` / `pauseForToolRoundLimit` / `executeToolBatch`、`ExecuteServices` 的 `modelGateway` / `topicCoordinator` / `allowToolsAfterExecute` / `continueTurn` / `pauseForToolRoundLimit` 字段与 `requestModelStreaming` / `generateTopicIfNeeded`（逐项 grep 确认零调用者）。存活的 `admit` / `runAdmittedBatch` / `handleStop` / `cancelPendingPlan` / `errorToolResultIDs` / `makePlan` 等 API 与既有测试不动。
>
> 与 §4.5 原文的偏差：① 采样器无 baseInstructions 通道，旧 systemInstruction 框架文字改为随初始 user input 原文下发（`composeChildInput`：只读声明 + sandbox 边界 + task/context 拼装）；② 子线程采样无 maxTokens 封顶（旧路径用 `ModelOutputCaps.subagent` 4096）；③ 强制摘要的形态是工具输出拒绝（ERROR 回复）而非「无工具采样轮」，模型继续调工具时直接终止；④ 等待用 `waitForFinalStatuses` 而非 `subscribeStatus`（同一订阅语义，带超时参数）；⑤ 子线程工具串行派发（harness 子线程一致性，旧路径并行）；⑥ 子线程工具调用的 hooks/授权走共享 ExecuteServices 管线与活会话状态（非 fork 的 activatedSkillNames 快照）；⑦ 旧「reached its limit without a summary」兜底文案删除（新路径不可达）；⑧ 从子线程再触发 explore 时 parent 归因仍是根线程（depth 检查在 1 挡住嵌套）。
>
> 测试：app 侧 `ExecuteHarnessExploreTests` 重写为 spawn 路径 9 用例（spawn/wait/摘要、初始输入框架 + task/context、读工具经 invokeHarnessTool 派发、写工具双门拒绝不派发、轮次预算收敛、超时中断、子采样错误传播、未配置模型时报错、父 transcript 不受污染），经 harness threadManager 手动 `turnSampler` 注入驱动。注：旧 explore 测试文件此前被 pbxproj `membershipExceptions` 排除在 SageTests target 外、从未运行，本次移除排除项使其真正入 target（全量 689 → 698）；tearDown 补 `shutdownAllThreadsBounded` + `harness.shutdown()`——explore 测试派生的根/子会话若不关闭，泄漏的提交循环会拖慢后续真实 zsh 启动类测试（`RunUserShellCommand*` 5s 超时偶发；关闭后三连同口径全量复跑消失）。包侧新增 `testExplorerChildToolRoundBudgetEndsWithSummary`。回归：app 全量 698 用例 1 失败（`ContextBudgetTests.testProtectedSkillSurvivesAFoldRange`，M1 起既有）；包 `swift test` 全绿；构建 0 error 0 warning；全库 grep 旧路径符号零命中（仅 role.swift 注释保留一处出处说明）。

### M5 — 可见性收口与清理 ✅ 已完成（2026-10-20）

**范围**：可见性决策表（§4.6）逐项落地；`availableToolDefinitions` 降级为兼容层并审计调用者；`assertMutatingToolsAllowed` / `screenMutations` 对阶段回合的职责边界定稿（Execute 回合内 act-only 检查是否保留）；文档同步（本计划勾选、`PORTING.md` 备注、`DEVELOPMENT_ROADMAP.md` 引用关系）。

**验收**：决策表逐行核对通过；全量回归（见 §6）。

> 落地记录：决策表逐行核对结论——M0–M4 已把五行全部落位，M5 无新增接线：①阶段工具集 = `TurnContext.toolAllowlist` 双门（M1/M2/M3）；②explorer 子 agent = 角色白名单 + `childModelTools` / `functionCallOutputs` 双门（M4）；③MCP exposure / Apps / 字节预算与核心工具门控留在 harness（现状不动）；④skill 过滤（`SkillToolPolicy.filterDefinitions`）、MCP 折叠（`mcpVisibleCatalog` 桥闭包 + `groupedDefinitions`）、工作记忆工具（`recall_task_transcript` 按 `workingMemory.hasContent`）、`manage_todo_list` act-only 均已在 attach 期 spec 列表计算（`availableToolDefinitions`）内执行，plan / review allowlist 不含 todo。
>
> `availableToolDefinitions` 降级为兼容层：注释从「Single source of truth for tools exposed to the model (and UI)」（D4 后不再成立，且全库已无 UI 调用者）改为 attach 期全量定义源声明。调用者审计：TaskHarness attach / `prepareSamplingPrompt`（Execute 注册集）、PlanAgent / ReviewAgent 阶段注册集、`prepareRequest`（Execute chat-completions 回退 wire 路径，R2 兼容）、`compactBeforeSampling` / `occupancyIgnoringWorkingMemory`（压缩与占用）——全部落在两类允许用途内，无游离调用点。死参数 `includeSkills`（全库零 false 调用者）随收口删除。
>
> act-only 检查职责边界定稿（**保留，不收口**）：`assertMutatingToolsAllowed`（ToolOrchestrator.prepare 门）与 `screenMutations`（Execute 批次筛查）保留——「会改 Mac」是 capability 语义（`requiresConfirmation` / `writesLocally`），名字白名单表达不了；Execute observe / answer 回合无 allowlist，此门是唯一防线；`screenMutations` 的拒绝额外落 transcript（注册表门只回模型不落 UI）。`invokePlanTool` / `invokeInspect` 的名字守门保留为 app 层兜底（经 harness 不可达——注册表门先拒），注释标明。M3 登记的「review brief 是否显式注入 diff 摘要」评估结论：brief 已含 `workspaceChanges.snapshot().inspectPlaces()`，写入类工具结果本就在 session 历史中，无需另注入。
>
> 清理：`RegularTask.sampleModelTurn` 与 `AgentModelGateway.streamComplete(includeTools:)` 无对话变体（M4 退役旧批次环后零调用者，逐项 grep 确认）删除；`recordHarnessToolResult` 引用死路径的注释修正。
>
> 文档同步：`PORTING.md`——删 M4 已退役的 `tasks/explore.swift` 行；turn / turn_context / registry / tools-context / state-service / agent-role / thread_manager / session_mod / regular / sage_execute / execute_attach 各行补 M0–M4 机制备注（toolAllowlist 双门、TurnServiceOverrides、sageToolSpecs、explorer 角色、screenMutations、startRework）；`harness_port.py check` 无新增问题。`DEVELOPMENT_ROADMAP.md`「Agent Runtime」条目更新为三阶段全 runtime 形态（去掉已退役的 `Turn.run`）。
>
> 测试：app 全量 698 用例 1 失败（`ContextBudgetTests.testProtectedSkillSurvivesAFoldRange`，M1 起既有，与 M5 无关）；包侧 `swift test` 全绿（10 套件）；构建通过。

---

## 6. 测试与验收策略

1. **单元**：M0 的白名单 / schema / explorer 角色三组；PhaseTurnRunner 用假 `ModelClient` 回放 `ResponseEvent` 流（对齐移植计划 Phase 5 的回合 golden 测试做法）。
2. **行为级**：Plan 只读检查、Review 自主检查 + verdict、返工闭环、explore spawn/wait、中断——每个里程碑的验收清单即行为用例。
3. **回归**：`SageTests/Harness/**` 全绿；app 侧 TurnTests / ToolLoopPolicyTests / ReviewAgent / PlanAgent 测试改路径后全绿；工具审批（`ApprovalStore` / SessionToolAllowlist / GrantStore 三层）行为不回归。
4. **手动 golden path**（每个里程碑收尾跑一次真实任务）：observe 任务（无工具）→ answer 任务 → act 任务（确认卡 + 执行 + 评审）→ must-fix 返工 → explore 工具调用 → Stop / 恢复。
5. **wire 对拍**：`builtTools` 输出与旧 `sageResponsesTools` 输出做语义等价对拍（M0）；rollout 写入 → 回放 round-trip（M3）。

---

## 7. 风险与对策

| # | 风险 | 对策 |
|---|---|---|
| R1 | M3 双写收敛是最大回归面（attach 重建 → 持久 session） | 放最后；恢复场景保留重建路径作为回退；单写者规则先在 PhaseTurnRunner 内落地再推广到 Execute |
| R2 | 双模型路径（Responses vs chat completions 回退）在阶段回合的行为差异 | PhaseTurnRunner 两条路径都跑验收用例；`ModelSettings.baseURL` 的后端约定（移植计划「当前下一步」）不阻塞本计划，但 Responses 路径的 schema 送达依赖后端联调 |
| R3 | Review 自主检查的轮次 / token 失控（原 6 轮硬上限消失） | TurnContext 预算承担 + 行为测试观测；失控则补回合级工具调用数上限（白名单机制同位实现） |
| R4 | Plan 流式 UI 桥接差异（streamCustom 直连 → override 事件流） | M2 验收清单显式含流式不回归；StreamingTextPump 侧不动，只换喂入源 |
| R5 | `Turn.run` 退役影响 `RegularTask.handleTurn` 兜底 | M4 先审计调用语义再决定退役或文档化保留，不盲删 |
| R6 | 白名单与 MCP exposure / `planCoreToolOptions` 三层门控叠加出意外组合 | M0 单测覆盖组合矩阵（白名单 × MCP direct/deferred × 核心工具开关） |
| R7 | `child_config.swift` 的 `prepareAgentSpawnConfig` throw 欠债与 explorer 角色路径冲突 | 白名单走 `SpawnRequest` → `SageThread` 实路径，不经过该函数；欠债清偿仍归移植计划 |
| R8 | 阶段回合误触发 Execute 的批次 HUD 门 / 审批卡 | PhaseTurnRunner 无 pendingPlan；只读工具本就低审批；验收含「plan / review 回合不出工具批次卡」 |

---

## 8. 非目标

- 不改 Plan → Execute → Review 的产品形态、确认卡、HUD 交互。
- 不用 Codex 的 `plan` 工具替代 `WorkPlan`（`plan` handler 保持移植忠实度，Sage 产品不用它）。
- 不动 GRDB task store / Recents / 多窗口模型；rollout 仍是 runtime 回放，不进用户可见产品。
- 不做三阶段并行执行（顺序拓扑是 D1 的既定决策）。
- 不在本计划内清偿 harness 的 faithful 欠债（guardian、compact remote V2 等，仍归 `EXECUTE_HARNESS_PORT_PLAN.md`）。

## 9. 与现有文档的关系

- `EXECUTE_HARNESS_PORT_PLAN.md`：harness 忠实度与文件映射的唯一事实源；本计划新增的 harness 机制（`toolAllowlist` / `sageToolSpecs`）按 R8 登记 Sage addition，`PORTING.md` 追踪表同步。
- `DEVELOPMENT_ROADMAP.md`：产品路线图。本计划完成后「Agent Runtime」条目的描述需更新为三阶段全 runtime 形态。
- `Sage/Tools/TOOL_DESIGN.md`：Sage 工具规范不变；工具 schema 进 harness 只是传输形态变化，设计标准照旧。
