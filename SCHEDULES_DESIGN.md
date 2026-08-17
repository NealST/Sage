# 定时任务（Schedules）：产品设计与技术实现

> Sage 用 **Schedule** 作为会反复触发的配方；**Task** 仍是每一次跑出来的工作单元。  
> 定时不抢当前会话、不走 TaskRouter、不复用 `beginNewTask`。  
>  
> 对应 `DEVELOPMENT_ROADMAP.md` §5.3。细节以本文为准。  
> 进度：完成一项将 `- [ ]` 改为 `- [x]`。

## 状态总览

| Phase | 主题 | 状态 |
|-------|------|------|
| 0 | 决策与本文 | **本文** |
| A | `schedules` 表 + 进程内触发 + 独立 runner | **P0 已落地** |
| B | Agent 首次全流程 → 冻配方 → replay；脚本类 | **P0 + 降级/Re-plan** |
| C | `/schedule` + 列表/通知 UX | **P0 + 点通知打开** |
| D | 退出后仍准点（Login Item / LaunchAgent）；事件触发另议 | **Login Item 已接**；事件触发另文 |

---

## 1. 产品模型

```text
Schedule（配方，持久）
  ├── kind: agent | script
  ├── scope: General | Project
  ├── cadence: once | interval | weekdays@time
  └── frozen recipe（agent 首次成功后才有）

每次触发
  └── 独立 Task（agent）或 run log（script）
        不替换窗里正在进行的对话
```

| 概念 | 含义 | 硬规则 |
|------|------|--------|
| **Schedule** | 何时、在哪个 scope、做什么 | 关窗不删；与 active task 无关 |
| **首次 Agent 跑** | 意图 / skill 召回 / plan / execute / review | 用来 **编译** 配方 |
| **之后 Agent 跑** | 只 execute（+ review） | 复用 frozen `WorkPlan` + skill 名 |
| **脚本跑** | 固定命令 | 无模型；PathGuard 仍生效 |
| **会话 `beginNewTask`** | 关掉当前窗对话并激活新 task | **定时禁止调用** |

### 1.1 和现有实体的边界

| 不要 | 原因 |
|------|------|
| 把闹钟字段塞进 `tasks` | Task 是一次运行；Schedule 要在未运行时也活着 |
| 复用 Skill 当 cron | Skill 是「怎么做」，不是「几点做」 |
| 直接 `beginNewTask` | 会关掉用户当前对话、改 `last_active_task`、误触发提炼 |
| 每次触发再走 matcher + PlanAgent | 可重复的定时会漂成新聊天 |

### 1.2 用户动作

- **创建（Agent）**：当前窗 `/schedule <何时> <自然语言任务>` → tip → 入库；scope = 该窗  
- **创建（Script）**：当前窗 `/schedule-script` → 脚本设置面板 → 入库；scope = 该窗  
- **Dashboard**：只展示状态（下次/上次/Running），**不提供创建入口**
- **首次 Agent 跑**：到点（或保存后立即试跑）走完整流水线；`act` 类 WorkPlan **只在这一次** 需要确认
- **武装（armed）**：首次 review 接受后写入 frozen recipe，之后自动 replay
- **启停 / 删除 / Re-plan**：列表内完成；Re-plan 清掉 frozen，下次再全流程
- **看结果**：系统通知；点通知再 `activateTask` 打开那一次（不在触发时抢窗）

---

## 2. 设计原则（Apple）

服务于 *Principles of Great Design*：Purpose、Agency、Responsibility、Familiarity、Simplicity、Craft。定时是后台能力，默认 **安静、可撤销、不打断**。

| 原则 | 落在本功能上 |
|------|----------------|
| **Purpose** | 不做工作流编辑器、不做完整 cron DSL、不做「到点把窗弹到前台」。先做：到点跑、不抢会话、能关。 |
| **Agency** | 创建时确认时间与范围；随时 Pause；脚本/写盘类可删可停。确认对话框只用于 **第一次** 会改 Mac 的 plan，以及删除 schedule。 |
| **Responsibility** | 创建 schedule = 授权以后自动执行。PathGuard 与手动 submit 相同。脚本 cwd 必须在 scope 沙箱内。失败通知，不静默无限重试。 |
| **Familiarity** | 通知用系统 `UNUserNotification`；列表像菜单栏/日历提醒，不造新导航神器。Project 窗仍是 Task / Files / History。 |
| **Simplicity** | 空态一句话 + 一个主按钮。状态用短词：On / Paused / Needs setup / Running。 |
| **Craft** | 不抢焦点；busy 时排队；菜单栏 `statusHint` 可显示「Scheduled: …」。Reduce Motion 下 tip/列表只用短 cross-fade。 |

### 2.1 反馈四种（status / completion / warning / error）

| 种类 | 何时 | 形态 |
|------|------|------|
| Status | 正在跑、已排队 | 菜单栏一句；列表行旁细字。**不**把用户窗 transcript 切走 |
| Completion | 成功 | 通知标题 = schedule 名；正文一行结果摘要。点开才进对应 task |
| Warning | 漏跑（睡眠）、排队已久 | 通知或列表「Ran after wake」；不弹窗 |
| Error | 失败、plan 未确认、skill 已删 | 通知 + 列表标记 Needs setup；提供 Pause / Re-plan |

### 2.2 不打断当前会话（空间一致性）

触发是 **平行工作**，不是把当前面板换成定时结果。

- 用户正在 Task 里打字 → 定时在独立 runner 跑  
- 跑完用通知「到达」，不把窗提到前台（除非用户点通知）  
- `last_active_task` **不**改成这次定时 task  

### 2.3 交互密度

- `/schedule` / `/schedule-script`：都在 **当前 Agent 窗** 发起，用该窗识别 General vs Project  
- 列表：Dashboard **只读观察**（状态、上次结果）；Pause 可保留作运行控制（同 MCP 开关），**无 New / 创建**  
- Project 不新加第四个主 tab  
- 删除要确认；Pause 不要确认  

---

## 3. 数据模型

### 3.1 表 `schedules`

| 列 | 说明 |
|----|------|
| `id` | UUID PK |
| `title` | 列表/通知标题 |
| `kind` | `agent` \| `script` |
| `project_id` | NULL = General；非空 = 该 project |
| `prompt` | Agent：用户原话。Script：可空 |
| `command` | Script：要执行的命令；Agent：空 |
| `working_directory` | Script：相对 scope root（`.` / NULL = root）；须在 PathGuard 内 |
| `cadence_kind` | `once` \| `interval` \| `weekdays` |
| `cadence_json` | 具体时间（时区用系统当前日历；存本地墙钟字段，避免偷偷变 UTC） |
| `enabled` | 启停 |
| `status` | `draft` \| `needs_first_run` \| `awaiting_confirmation` \| `armed` \| `paused` \| `failed` |
| `next_fire_at` / `last_fire_at` | 墙钟 |
| `last_status` | 短文案 |
| `frozen_work_plan_json` | Agent armed 后：`WorkPlan` |
| `frozen_skill_names` | 逗号或 JSON 数组 |
| `origin_task_id` | 仅当用户显式「Use this conversation」时才写；默认 NULL |
| `created_at` / `updated_at` | |

索引：`(enabled, next_fire_at)`、`(project_id)`。

**不**默认把 `.sage` 或 schedule 写入 gitignore；schedule 在 App Support 的 Sage DB 里，不进项目目录。

### 3.2 可选 `schedule_runs`

脚本类若不想污染 `tasks`：每次一行 `schedule_id, started_at, ended_at, exit_code, output_excerpt`。  
Agent 类每次仍 `spawnScheduledTask` → 普通 `tasks` 行，带 provenance（见 §4.3）。

### 3.3 迁移

- Migrator 新版本 `addSchedules`  
- 与 `projects(id)` 外键：`ON DELETE CASCADE` 或禁止删仍有 schedule 的 project（P0 建议 CASCADE，与「工程没了闹钟没意义」一致）

---

## 4. 运行时

### 4.1 两种入口

```text
会话 beginNewTask     → 关当前 → 激活新 task → 更新 last_active → 可提炼
spawnScheduledTask    → 创建 task，不关当前、不改 last_active、默认不提炼
```

定时 **只** 走 `spawnScheduledTask`（或脚本的 run log）。

### 4.2 Agent 流水线

```text
首次（status ≠ armed 或 frozen 空）
  spawnScheduledTask
  跳过 TaskRouter
  skill 召回 → PlanAgent →（act 则确认）→ execute → review
  review accept → 写入 frozen WorkPlan + skillNames，status = armed

Replay（armed）
  spawnScheduledTask
  load 钉死的 skills（不 matcher、不选择 tip）
  注入 frozen WorkPlan（不 PlanAgent、不确认）
  execute → review
```

**冻的是策略，不是工具清单。** `WorkPlan.intent` / `approach` / `kind` / `skillNames` 可复用；当天的 tool 序列仍由 ExecuteAgent 按现实 ReAct。

Review **保留** 在 replay：用来发现世界已经变了，不重新做意图分析。

### 4.3 打破复用（自动降回首次）

- Review 连续失败 / execute 明确 blocked  
- frozen skill 删除或禁用  
- 用户 Re-plan 或改了 prompt  
- Project root 失效  

→ `status = needs_first_run`，清 frozen 或保留作参考但下次全流程。通知 Needs setup。

### 4.4 脚本流水线

不进 `TurnCoordinator`。`ProcessRunner` + PathGuard（working directory ∈ scope）。超时、输出 cap 与 `run_shell_command` 同级。跑完通知 + `schedule_runs`。

### 4.5 与窗口 / busy

| 情况 | 行为 |
|------|------|
| 目标窗不存在 | 静默建 session 或纯 runner；**不**把窗提到前台 |
| 目标窗 idle | runner 跑 spawned task；窗 UI 仍显示用户当前 task |
| 目标窗 busy | 排队，当前回合结束后再跑 |
| 跑完 | 通知；点通知再 focus + `activateTask` |

Runner 与用户窗的 `SessionOperationGate` **分开**，避免 think 时被闹钟抢 lock。

### 4.6 触发（macOS）

没有「App 退出后系统保证跑 Swift」的 API。准点 = **机器醒着且 Sage 活着**；漏了就补扫。

| 阶段 | 机制 |
|------|------|
| **A（P0）** | 进程内：`next_fire_at` + `DispatchSourceTimer`（wall deadline） |
| 唤醒补扫 | `NSWorkspace.didWakeNotification` + 启动时 `WHERE enabled AND next_fire_at <= now` |
| App Nap | **等待期间**不 `beginActivity`；**真正跑 agent/脚本时**包一层（与现有 gate 相同） |
| **不要** | `NSBackgroundActivityScheduler` 当用户可见闹钟（会漂） |
| **D** | `SMAppService` 登录项 / LaunchAgent，退出后仍拉起再扫表 |
| 辅助 | 完成/失败用 `UNUserNotification`；通知本身不代替执行 |

睡眠过点：醒了补跑 **一次** 并重算下一拍；文案可标 after wake。不在睡眠中强行醒机。

### 4.7 不做（本设计）

- 事件触发（FSEvents / 剪贴板 / 前台 App）— 可共用 runner，触发器另文  
- 完整 cron 表达式  
- 工作流编辑器、条件分支  
- 跨 project 一只 schedule  
- 定时 task 的 automatic skill 提炼（`/remember` 仍可）

---

## 5. UX 规格

### 5.1 添加交互

两种配方 **两条 slash**，都在当前 Agent 窗的 composer 里发起，**用该窗识别 scope**（Project → 该工程，General → 全局）。都不默认读当前 transcript。

Dashboard **不提供创建入口**（只做可观测性，见 §5.2）。

不要把脚本写进 `/schedule weekdays 9:00 git status` 这种自然语言句子里。

#### A. Agent — `/schedule`

```text
/schedule <何时> <要 Sage 做的事>
```

补全只给何时预设，选中后光标留在后面写任务：

```text
/schedule weekdays 9:00 Check git status and summarize
```

Return → composer 上方 tip（Skill Save 密度）确认何时。种类固定 Agent。Save 入库，scope = 当前窗。

空 `/schedule`：Save 禁用直到有何时 + 做什么；不填当前对话。  
显式例外：`this` / **Use this conversation** 才引用当前用户原话。

#### B. Script — `/schedule-script`

打开 **脚本设置面板**（挂在当前窗，从 composer 长出来的轻量面板，不是 Dashboard、不是独立向导）。

```text
Run a script                          This Project · ~/…/MyApp
Command     [ ./scripts/daily.sh          ]   ← 等宽；Choose File…
Working dir [ .                           ]   ← 相对 root，PathGuard 内
When        [ Weekdays 9:00 ] [ Morning ] [ Daily ] [ In 1 hour ]

[Save]  [Cancel]
```

- 键入 `/schedule-script` 即开面板；可选参数预填 Command（`/schedule-script ./scripts/daily.sh`）  
- **Choose File…**：`NSOpenPanel` 限在当前窗沙箱（project root 或 `~`）；填 **相对路径**  
- 参数写在 Command 同一行  
- 次要 **试跑一次**（默关）  
- Save → scope 钉死为打开面板时的那一窗；换工程请到对应窗再 `/schedule-script`  
- Cancel / Esc 关面板，当前对话不动  

Files 树保持浏览；不靠右键创建（避免第三入口）。要从文件开跑，在对应 Project 窗用 `/schedule-script` 再 Choose File。

### 5.2 列表（Dashboard，只观察）

Dashboard 已有 token / MCP 状态。Schedules 一节同样是 **监视**：标题、种类、下次时间、上次结果、Running/Queued。

- **没有** New / Add  
- 空态只说明怎么加，不放按钮：

> No schedules  
> In a chat window: /schedule for Sage, /schedule-script for a command.

- Pause 与 MCP 开关同类，算运行控制，可保留；删除确认。创建必须回 Agent 窗 slash。

### 5.3 通知

- 标题：schedule `title`  
- 正文：成功摘要或失败原因（一行）  
- 点按：打开对应 General/Project 窗并 `activateTask`（agent）或展示 run log（script）  
- Reduce Motion：系统通知已够；App 内 banner 只用 opacity  

### 5.4 首次 plan 确认

仅 `WorkPlan.kind == .act` 且 **尚未 armed**。形态与现有 awaiting confirmation 相同，但挂在 **这次 spawned task** 上：若用户当时在看别的对话，用通知「A schedule needs confirmation」+ 列表徽章，**不要**把当前窗 plan 卡片换成别人的。

Replay 不再出确认。

### 5.5 VoiceOver / 键盘

- 列表行 `accessibilityLabel`：「{title}, weekdays 9:00, on」  
- Toggle：「Pause schedule {title}」  
- 通知与 tip 走现有 `AccessibilitySettings`（VO 时不自动 dismiss 确认 tip）  

---

## 6. 代码落点（示意）

| 模块 | 职责 |
|------|------|
| `GRDBTaskSchema` | `addSchedules` 迁移 |
| `ScheduleRecord` | 行模型 |
| `ScheduleRepository` | CRUD + due 查询（可挂在 `TaskRepository` 或独立 actor） |
| `ScheduleClock` | 根据 cadence 算 `next_fire_at` |
| `ScheduleTrigger` | timer + wake/launch 扫表 |
| `ScheduleRunner` | 队列；调用 spawn / ProcessRunner；写回 last_* / frozen |
| `spawnScheduledTask` | `AgentTaskStore` 新入口 |
| `TurnCoordinator.performScheduledFirstRun` / `performScheduledReplay` | 跳过 route；replay 跳过 propose |
| `ScheduleSlashCommand` | `/schedule` Agent 一句 + tip |
| `ScheduleScriptSlashCommand` | `/schedule-script` 打开当前窗脚本面板 |
| Dashboard 一节 | **只读**状态列表（无 New） |
| `NotifyTool` / UNUserNotification | 完成与失败（复用权限） |

---

## 7. 实现清单

### Phase A — 骨架

- [x] `schedules` 表 + 模型 + repository
- [x] `ScheduleClock` + 进程内 trigger + 启动/唤醒扫 due
- [x] `spawnScheduledTask`（不关当前、不改 last_active、不提炼）
- [x] 独立 runner 队列（与窗 busy lock 分离）
- [x] 跑完/失败通知（可先固定文案）

### Phase B — 两种执行

- [x] Agent 首次：跳过 router，全流程；act 确认挂在 spawned task 上（通知 + Dashboard，不抢当前窗 Plan）
- [x] Armed replay：冻 WorkPlan + skills；仅 execute + review
- [x] 降级条件（blocked / 缺 skill / Re-plan）
- [x] Script：`ProcessRunner` + PathGuard + `schedule_runs` + working dir + 试跑一次

### Phase C — UX

- [x] `/schedule` + `/schedule-script` 面板；`this` / Use this conversation
- [x] Dashboard **观察**列表（无创建入口；Needs confirmation 徽章）
- [x] 点通知打开对应 task
- [x] 菜单栏 status 一句 Running/Queued

### Phase D — 加深

- [x] `SMAppService` 登录项（退出后拉起扫表）
- [ ] 事件触发（另文，共用 runner）

---

## 8. 成功标准

1. 用户正在对话时，定时跑完 **不** 替换 transcript、**不** 改 last_active  
2. Agent 第二次起不再跑 matcher / PlanAgent（除非降级）  
3. 脚本不调用云端模型  
4. 关窗后 schedule 仍在；开 Sage 或唤醒会补漏跑  
5. Pause / 删除随时可用；第一次 act 才需要 plan 确认  

---

## 9. 相关文档

- `TASK_ROUTING_DESIGN.md` — 会话线程；定时不走路由  
- `PROJECT_SYSTEM_DESIGN.md` — scope / PathGuard；schedule 的 `project_id` 与此一致  
- `Docs/skill-extraction-design.md` — 定时 task 默认不 automatic extract  
- `DEVELOPMENT_ROADMAP.md` — §5.3  
- `Sage/Tools/TOOL_DESIGN.md` — 脚本输出与错误文案  

---

## 10. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-08-17 | 初稿：Schedule ≠ Task；spawn 与 beginNewTask 分离；首次全流程 / replay；脚本类；进程内触发；Apple UX（不打断、四种反馈、tip 密度） |
| 2026-08-17 | 脚本入口改为 `/schedule-script` 打开面板（scope=当前窗）；Dashboard 仅观察、不创建 |
| 2026-08-17 | P0 落地：进程内 trigger、slash 创建、Dashboard 观察列表；首次 act 在 ephemeral runner 上 auto-confirm |
| 2026-08-17 | P1：点通知打开 task、Re-plan/缺 skill 降级、唤醒补跑文案、跑时 beginActivity、登录项 |
| 2026-08-17 | 首次 act 确认：`awaiting_confirmation`；`/schedule this` / Use this conversation；脚本 working dir + 试跑 |
