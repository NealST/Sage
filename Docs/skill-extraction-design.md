# Skill 自动提炼与经验沉淀 — 设计文档

> 对应 Roadmap 2.3（Skill 系统完善）和 3.1（长期记忆/知识库）中的"经验自动沉淀"能力。  
> 本文档与当前实现同步（识别 → 确认后生成、global/project 作用域、管理 UI）。  
> 跨 task 聚合决策见下文「跨 task 经验聚合（= Enhance 主路径）」——不做延迟簇池。

## 背景

Sage 的 Skill 系统按需激活：把 Available Skills 目录交给云端，由 `load_skill` 决定是否加载正文。经验自动沉淀让 agent 在完成任务后识别可复用经验，经用户确认后再生成并写入 skill 文件，供后续任务召回。

## 设计决策

### 触发时机

**选择：Task 切换时（`beginNewTask` 关闭旧 task）**

- 此时 task 已有完整的 events 记录
- 用户正在开启新话题，不会打断当前工作流
- 比 `phase = .completed` 更可靠（后者只是 UI 状态，表示"当前回合结束"）

### 两阶段：识别 vs 生成

**选择：识别阶段只判定；确认后再生成全文**

1. **识别**（`SkillExtractionService.analyze`）— cloud model 返回 `skip` / `new` / `enhance`（仅 name + description）
2. **确认后生成**（`composeNewSkill` / `composeEnhancedSkill`）— 用 task transcript + `SkillAuthoring`（与 `save_skill` 同源实践）生成全文；enhance 额外注入旧 skill 全文并合并

### 识别策略

**选择：Cloud model 判断**

- 分析 task transcript，按软标准判断是否值得沉淀
- Catalog 带 `[global]` / `[project]` 标签供去重与 enhance 决策
- 同名已存在 → 强制走 enhance（工作区内 skill 名唯一）

### 作用域（Global / Project）

| 环境 | 识别 catalog | 新增默认 | 用户选择 |
|------|--------------|----------|----------|
| General | 仅全局 skill | 全局 | 无 |
| Project | 全局 + 当前 project | 默认 This Project | 分段控件 This Project / Everywhere + 后果说明 |

- **Enhance**：复用已有 skill 的作用域；识别时钉死 `targetSkillPath`，确认时按路径写入
- **写入路径**：全局 → `~/Library/Application Support/Sage/Skills/`；project → `<project>/.sage/skills/`
- **扫描**：全局 = App Support + `~/.agents/skills`；project = 项目下 `.agents/skills` 与 `.sage/skills`（项目树内一律 project）
- **Project 切换**：多窗模型下打开/聚焦另一窗，**不作废**原窗 tips；仅 **关闭 Project window** 时 `prepareForWindowClose` 清理 tip / 放弃 skill choice
- **`save_skill`**：支持 `scope: project \| global`，语义与 banner 一致

### 粒度

**选择：一次关闭/remember 产出至多一条建议（new 或 enhance）**

- New：结晶为新 skill 文件  
- Enhance：把本次 task 经验合入已有 skill（跨 task 累加发生在这里）
- 不做：多 task 一次性合成；也不做「一 task 多条 skill」

### UI 交互

**选择：底部 inline tip（输入框上方）+ composer 状态 chip**

- Apple tip 风格：轻填充、纯文字 Save、轻量关闭
- 确认后 tip 立即消失；Creating/Enhancing 在输入框底部 capsule chip，点击可查状态
- 20s 无操作自动消失
- Project 新增：分段 **This Project / Everywhere** + 后果文案

### 频率控制

**选择：10 秒 debounce + 展示队列聚合**

## 整体流程

```
beginNewTask() closing 旧 task（events ≥ 4 且 API 已配置）
    │
    ├─ 持久化 task、生成 topic
    │
    └─ scheduleSkillExtraction(for: closingTask)
         │
         ▼
    Task.detached(priority: .utility)
         │
         ├─ analyze(task, catalog[scope-filtered], settings)
         │    └─ skip | new(name, description) | enhance(target, description)
         │
         └─ enqueue SkillSuggestion（enhance 带 targetSkillPath）
              │
              ├─ 10s debounce → banner tip
              │
              ├─ Save → 立即 dismiss tip → startSkillSuggestionSave
              │         ├─ composeNewSkill / composeEnhancedSkill（第二次 cloud 调用）
              │         ├─ SkillWriter.createSkill / enhanceSkill
              │         └─ 状态 chip：Saving… / Saved / Save failed
              │
              └─ × 或 20s 超时 → 丢弃
```

## 文件结构

| 文件 | 职责 |
|------|------|
| `SkillExtractionService.swift` | 识别 + 确认后 compose |
| `SkillAuthoring.swift` | 与 `save_skill` 共享的写作实践 |
| `SkillSessionController.swift` | 每窗 tip / save / consolidate / 提炼编排（挂在 `AgentSession.skills`） |
| `SkillTipStore.swift` / `SkillSaveJob.swift` | 统一 tip 队列 + 后台保存任务 |
| `SkillToolExecutor.swift` | skill 工具定义与执行（`SkillToolHost`） |
| `SkillWriter.swift` / `SkillPaths.swift` / `SkillMarkdown.swift` | 写盘 / 路径 / frontmatter |
| `SkillRegistry.swift` | actor 化扫盘与 body/resource 缓存 |
| `SkillTipsBanner.swift` / `SkillTipChrome.swift` | tip UI + 共用 panel chrome |
| `SkillSaveStatusIndicator.swift` | composer 状态 chip |
| `SkillsManageView.swift` | Everywhere / This Project 分组管理 |
| `AgentRuntime.swift` | 会话门面：UI 状态、公开 API、host 接线 |
| `AgentRuntime+SlashCommands.swift` | `SlashCommandHost` 实现 |
| `AgentRuntime+TaskStoreFacade.swift` | taskStore / routing 薄委托 |
| `SessionLifecycle.swift` | bootstrap / close / erase / workspace / persistScope（`SessionLifecycleHost`） |
| `AgentTaskStore.swift` | create / commit / resume / activate / restore（`AgentTaskStoreHost`） |
| `TurnCoordinator.swift` | submit / retry / model turn / handleTurn（`TurnCoordinatorHost`） |
| `ToolInvocationDispatcher.swift` | builtin / skill / MCP 工具分发 + PathGuard / timeout |
| `StreamingPlayback.swift` | 独立 `@Observable` 流式缓冲（不打穿 Runtime / Workspace） |
| `StreamingTextPump.swift` | SSE 文本 ~30Hz 合帧写入 `StreamingPlayback` |
| `SessionOperationGate.swift` | busy lock + cancellable `workTask`（`SessionOperationHost`） |
| `Execute/ToolBatchExecutor.swift` | 工具批次逐步执行 / Stop / Cancel |
| `SkillRecallCoordinator.swift` | skill 匹配 / 选择 / 自动加载 / turn 缓存 |
| `AgentModelGateway.swift` | 拼请求 / 流式 / related-context appendix |
| `TaskRoutingCoordinator.swift` | 本地路由（continue/new/resume）+ topic 生成 |

## Prompt 设计

### 识别

- 值得：非显而易见 workaround、试错最佳实践、可复用工作流、难摸的领域知识
- 不值得：琐碎 Q&A、过窄场景、常识
- Catalog：`name [global|project]: description`（识别阶段不带全文）
- 输出：仅 JSON，**不生成全文**

### 生成（确认后）

- New：transcript + 建议 description + writing guidelines → `{description, body}`
- Enhance：旧全文 + transcript + guidelines → 合并后的 `{description, body}`
- body **不含** frontmatter（由 `SkillWriter` 写入）

### transcript

- user / assistant / tool result；跳过 system；总长约 6k；单条 tool result 最多 500

## 约束与边界

- 最少 4 个 events；需 API 配置；不阻塞主流程
- 识别失败静默；确认写入失败经状态 chip 展示
- 关窗 `prepareForTeardown`：取消 in-flight extraction，并 await 未完成的 save
- Create：`source: auto-generated`；Enhance：保留原 frontmatter `source`（手写 skill 不被改成 auto）
- 工作区内 skill 名唯一（create 撞名 → 应 enhance）
- Enable 状态按 **SKILL.md path** 持久化（兼容旧 name key）
- 目录布局唯一入口：`SkillPaths`；frontmatter parse/upsert：`SkillMarkdown`；写/trash 经 `SkillWriter` 离 MainActor
- Frontmatter：`description` 支持 `|` / `>` 多行 YAML；body 缓存按 mtime 失效 + LRU（条数/字符上限）
- `listResources` 上限 30；截断时在 skill payload / 缺文件错误里标明
- Protected skill 正文：单条 ≤**15,000** 字符（对齐 ≈5k token）；全部 protected 合计 ≤**16,000** 字符（为对话预留预算）；超限先 stub 较早的 skill 正文并提示重新 `load_skill` / `load_skill_resource`
- Event `protected` 落库；related-context 用 lean snippet（summary/topic + 末尾 N 条对话，不全量 loadTask）；plan 同 id 时 upsert steps（执行中 running 走 `updatePlanStep`）
- Transcript：`ToolResultIndex` 按 event revision 预计算，避免 ForEach 内反复扫 events
- Stop：`ProcessRunner.terminateAll()` + workTask cancel（shell / skill script 同源）

## 召回与上下文（当前策略）

理想：skill 彼此独立内聚 → **一次意图至多匹配 1 个 skill**。

### 匹配与激活

1. 每轮只注入 **Available Skills** 目录（name + description），不预加载正文
2. 云端模型在需要时调用 `load_skill`（斜杠激活仍走同一工具）
3. 不再用本地小模型做 auto-match / auto-load
4. Consolidate tip 仍可作为碎片 skill 的合并入口：用户 **Keep** 主 skill，确认 Merge 后 `composeMergedSkills` 写入主 path，其余进废纸篓

### 复杂意图

拆步由云端 plan 负责。执行已有 plan 时按 step 刷新 catalog appendix，不在本地再跑一轮匹配。

### 跨 task 经验聚合（= Enhance 主路径）

**决策（2026-08-13）：** 不做「多 task 待聚合池 / 延迟簇」。  
Skill 文件即经验累加态；跨 task 聚合 **就是** analyze → enhance → compose。Consolidate 仅作碎片补救。

```text
Task A 值得沉淀 → new skill X（第一次结晶，允许偏窄）
Task B 同类     → analyze 命中 X → enhance → compose(旧全文 + B transcript)
Task C 再同类   → 再 enhance X
误 new 碎片     → 召回 N 命中 → Consolidate tip → merge
```

| 原则 | 说明 |
|------|------|
| 文件即历史 | 历次 enhance 写进 SKILL.md 后，不必再拼多份旧 transcript |
| 偏 enhance | 同问题类 / 同域 → `enhance`；仅明确新主题才 `new` |
| 第一次可窄 | 靠后续 enhance 变厚，不靠识别阶段一次写全 |
| 不做 | pending 池、跨 task transcript join、独立向量记忆层 |

#### 实现清单（相对现状）

- [x] **Analyze 更敢 enhance**：automatic / `/remember` prompt 明确「近邻优先 enhance」；近重复名强制 enhance（已有同名规则可保留并加强近义描述）
- [x] **近邻预筛**：已去掉本地 matcher；analyze 仍看到完整 catalog，由云端决定 new vs enhance
- [x] **Compose 合并准则**：保留仍正确的旧结论；用新 transcript 补边 / 修正矛盾；去重；文件即跨 task 累加态
- [x] **Tip 文案**：enhance 写成「Update existing experience」/ 按钮「Update」
- [x] **Consolidate**：保持为误 `new` 后的回收路径，不升级为主聚合器

#### 后置（不阻塞本决策）

- skill 过期衰减（usage / lastUsed → 召回排序，不参与如何聚合）
- 外部编辑 skill 目录的 FSEvents 监视（当前靠 Refresh / 写入后 reload）

## 显式记住（`/remember`）

用户可主动触发沉淀，仍走**识别阶段**（判定 new vs enhance），但**不能 skip**：

1. 输入 `/remember` 或 `/remember 可选备注`
2. 对当前 task transcript 调用 `analyze(mode: .explicitRemember)`
3. Tip **立即**展示（无 10s debounce），确认后照常 compose + 写入
4. Project 环境下同样提供 This Project / Everywhere 选择

Slash 自动补全包含 `remember`（描述来自 `SlashCommandDefinition`）。

实现位于 `Sage/Commands/`：
- `SlashCommandRegistry.builtins` 是 builtin 的唯一注册点（实现 `BuiltinSlashCommand` 后加入数组即可）
- 动态 skill 激活按名称大小写不敏感匹配
- Handler 只依赖 `SlashCommandHost`；`AgentRuntime+SlashCommands` 实现该协议
