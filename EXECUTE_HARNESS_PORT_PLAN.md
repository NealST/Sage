# Sage Execute Harness — Codex 完整复写计划

> **目标**：将 codex 的 agent harness（`codex-rs/core` 及其运行时依赖锥）用 Swift 完整复写为 Sage 的 Execute 层，目录结构与文件名与 codex 一一对应，实现充分还原上游语义。
>
> **上游基线**：`codex-rs` @ `0a2eb4696c26ac33204bcd255721ab30220a4774`（本工作区 `codex/` 仓库当前 HEAD，与现有移植文件头部一致）。
>
> **现状一句话**：已完成 37 个 Swift 文件 / ~4,700 行（apply-patch 栈最忠实，turn 循环与 guardian 为骨架），约占复写范围的 **2%**；本计划覆盖剩余全部工作。

---

## 1. 背景与目标

Sage 的 agent 架构分三层：**Plan → Execute → Review**。Execute 承接 Plan 产出的 workplan，其运行核心（回合循环、工具编排、沙盒、压缩、审批）应当完全对齐 codex 的 harness——即 `codex-rs/core` crate 加上它运行时直接依赖的 `codex-*` crate 集合。

**复写目标（三条硬要求）**：

1. **完整**：范围内每一个 Rust 文件都有对应的 Swift 文件（或被明确标记为平台排除/暂缓），不允许无声跳过。
2. **一一对应**：目录结构与文件名镜像 codex（映射规则见 §5），codex 侧重命名/移动时 Swift 侧跟随。
3. **充分还原**：逐文件对齐行为语义；只有平台差异（Landlock/Windows 沙盒、本地代理进程等）和 Sage 已有子系统（GRDB 持久化、MCP client、Settings）允许走「适配」，且必须在文件头显式标注差异。

**非目标**：不移植 codex 的 UI 层（tui/cli/app-server）、不做 Sage 没有对应能力形态的语音 realtime（保留映射占位，见 §2.4）。

---

## 2. 复写范围界定

### 2.1 范围内：harness 本体（`codex-rs/core`）

- 非测试生产代码：**391 个 `.rs` 文件，~118,200 行**
- 测试代码：~117,000 行（移植策略见 §8）
- 公开门面：`ThreadManager` / `CodexThread` / `TurnContext` / `ModelClient`；`session`、`tasks`、`tools`、`state` 均为 `pub(crate)`——即 harness 内部机制，正是本次复写的主体。

### 2.2 范围内：运行时依赖 crate（按移植优先级分层）

| 层 | crate | 非测试行数 | 说明 |
|---|---|---:|---|
| P1 协议基础 | `protocol` | 27,279 | 全部 wire/domain 类型：`EventMsg`、`ResponseItem`、`PermissionProfile`、`ToolName` 等 |
| P1 工具集 | `utils/*` 子集（absolute-path、path、path-uri、path-utils、output-truncation、string、stream-parser、cache、home-dir、git-discovery、image）+ `async-utils` | ~12,900 | core 直接链接的小工具库 |
| P2 文件/补丁 | `file-system`、`apply-patch`、`git-utils` | 1,140 / 4,828 / 4,055 | apply-patch 已有较忠实基础 |
| P3 执行/沙盒 | `sandboxing`（含 macOS `seatbelt.rs` 1,122 行）、`shell-command`、`execpolicy`、`utils/pty` | 4,135 / 7,883 / 1,954 / 5,302 | Landlock/bwrap/Windows 后端为平台排除 |
| P4 工具系统 | （core 内 `tools/`，见 §7 Phase 4） | ~28,000 | router/registry/spec_plan/parallel/orchestrator/handlers/runtimes |
| P6 模型客户端 | `model-provider-info`、`codex-api` SSE 子集 | 924 / ~4,000（子集） | `codex-api` 全量 13,506 行，realtime/websocket 部分暂缓 |
| P7 持久化 | `rollout`、`state`、`thread-store` | 9,334 / 20,362 / 22,930 | rollout JSONL 忠实移植；state/thread-store 语义对齐、存储适配 GRDB |
| P8 审查/钩子/技能 | `hooks`、`skills`、`agent-roles`、`context-fragments` | 11,657 / 1,493 / 592 / 478 | guardian 完整版依赖 |
| 裁剪 | `otel`、`terminal-detection` | 4,898 / 423 | 遥测裁剪为最小接口 |

### 2.3 平台适配项（不逐行复写，做 macOS 等价实现）

| codex 内容 | Sage 处理 |
|---|---|
| `sandboxing/landlock.rs`、`bwrap.rs`（Linux） | 平台排除，不建 Swift 文件，追踪表标记 `excluded(platform)` |
| `sandboxing/windows*.rs`、`windows-sandbox-rs`（23,433 行）、`mxc-sandbox` | 平台排除 |
| `core/src/windows_sandbox*.rs`（532 行） | 平台排除 |
| `shell-command` 的 PowerShell/Windows 危险命令（~2,000 行） | 适配：macOS 只需 bash/zsh/sh；保留同名文件并标注 |
| `arg0` 重 exec 分发（813 行） | 适配：Sage 为 app 进程，无 argv0 多重分发；apply_patch 走进程内调用 |
| `process-hardening`（Linux pre-main） | 排除 |
| `network-proxy`（22,784 行，补记） | core 的 `network_policy.rs` 依赖其策略类型；仅移植类型层 5 文件（`config.rs`/`network_policy.rs`/`policy.rs`/`reasons.rs`/`environment_policy.rs`，Phase 4），本地代理进程机械全部 `excluded` |

### 2.4 明确排除/暂缓项

| 项 | 行数 | 原因 |
|---|---:|---|
| `tui` / `cli` / `exec` / `app-server*` / `core-api` / `chatgpt` | — | codex 的 UI/宿主层，不是 harness |
| `realtime_*`（core 内 ~6,100 行）+ `realtime-webrtc` | ~6,100 | 语音 realtime，Sage 无此能力形态；**暂缓**，追踪表标记 `deferred`，保留文件映射占位 |
| `ansi-escape`、`file-search`、`responses-api-proxy`、`codex-home` | — | TUI/工具向，core 运行时不依赖 |
| `login`、`agent-identity` | — | ChatGPT 登录链路；Sage 用 API Key（适配层处理鉴权） |

**范围内总量**：约 **28 万行 Rust**（core 11.8 万 + 依赖 crate ~16 万）。其中忠实复写约 17 万行、语义对齐+存储/平台适配约 7 万行、暂缓约 4 万行。按 Rust→Swift 经验系数 0.7–0.9 估算，最终 Swift 侧约 **18–22 万行**。

---

## 3. 现状盘点

### 3.1 已有移植（37 文件 / 4,722 行，全部 pin 在 `0a2eb469`）

| 区域 | 文件 | 行数 | 保真度 |
|---|---|---:|---|
| `apply-patch/src/` | lib / parser / streaming_parser / file_update / text_file / invocation / seek_sequence | 1,401 | ✅ 忠实（最强区域；25 个 scenario fixture 全过） |
| `file-system/src/lib.swift` | ← `file-system/src/lib.rs` 的 `FileSystemSandboxContext` | 90 | 🟡 部分（原 crate 1,140 行，仅移植沙盒上下文） |
| `tools/runtimes/apply_patch.swift` | | 42 | 🟡 薄但对齐 |
| `tools/` | orchestrator / parallel / approvals / sandboxing / network_approval / handlers/apply_patch(+spec) | 1,560 | 🟡 形状对齐、Sage 接线（orchestrator 调 `ToolInvocationPipeline`；parallel 用波次替代 RWLock 准入） |
| `session/turn.swift` | ← `session/turn.rs` `run_turn` | 67 | 🟡 骨架（原文件 3,105 行） |
| `tasks/` | regular / compact / explore | 612 | regular ✅+队列拆分；compact 🟡（remote V2 未做）；**explore 为 Sage 原生，无 codex 对应文件** |
| `guardian/` | 14 个文件 | 527 | 🟡 多为薄抽取（原目录 ~3,600 行，如 `review_session.rs` 947 行 vs 现有 44 行） |
| `hook_runtime.swift` | | 170 | 🟡 部分（原 1,352 行，无脚本 runner） |
| `config/network_proxy_spec.swift` | | 186 | 🟡 适配（Mac 无本地代理进程，保留 allow/deny/ask 决策） |

测试：`SageTests/ExecuteHarness/` 11 个文件 / ~1,525 行 / ~62 用例，覆盖 orchestrator、turn、explore、apply-patch（含 25 个 codex scenario fixture）、parallel、sandboxing、approvals、guardian prompt。

### 3.2 差距分析

| 维度 | codex（范围内） | Sage 已移植 | 覆盖 |
|---|---:|---:|---:|
| core crate 文件 | 391 | ~30 个有对应 | **8%** |
| core crate 行数 | ~118,200 | ~2,700（core 对应部分） | **~2.3%** |
| 依赖 crate | ~16 万行 | ~1,500（apply-patch/file-system） | **~1%** |

**关键缺口**（无任何 Swift 对应物的核心机制）：

- `protocol` crate 全部（harness 的类型地基，当前 Sage 用自有 `ModelTurn` 等类型代替）
- `session/` 的 40 个文件（现有仅 67 行 turn 骨架；缺 `Session`、`TurnContext`、`turn_input` 准入、输入队列、step 设置、rollout 重建等）
- `state/`、`tasks/mod.rs` 的任务生命周期、`context_manager/` 历史管理
- `tools/` 的 router/registry/spec_plan/events/context 与全部 handler（现有仅 apply_patch 一个 handler）
- `client.rs`（2,852 行 Responses 流式客户端）、compact remote V2
- `unified_exec` PTY 进程管理（4,105 行）、`sandboxing` crate 的 seatbelt（1,122 行）
- `hooks` crate（11,657 行）完整钩子引擎、guardian 完整审查会话
- `rollout`/`state`/`thread-store` 持久化三件套

### 3.3 现有 Sage 粘合层（`Agent/Execute/` 根级，~3,900 行）的处理原则

这些文件**不是**第二棵 codex 树，是 app 接线：`ToolBatchExecutor(+Waves/+Approval)`、`ToolInvocationPipeline/Dispatcher/Request`、`ToolAuthorization*`、`SessionToolAllowlist`、`PreToolUseHooks`、`ExecuteServices`、`ExploreSubagentRunner`、`TextToolCallParser` 等。

处理原则（详见 §4.3）：随着忠实 port 落地，粘合层逐步**退化为适配层**——实现 harness 定义的 protocol，不再自带机制语义。已知需要收敛的重叠点：

- `ToolBatchExecutor+Waves` 的波次执行 ↔ codex `tools/parallel.rs` 的准入控制
- `SessionToolAllowlist`（HUD 批准）↔ `tools/approvals.rs` 的 `ApprovalStore`
- `PreToolUseHooks`（声明式 JSON）↔ `hook_runtime.rs` + `hooks` crate（事件钩子）
- `ToolInvocationPipeline`（validate/timeout/dispatch）↔ orchestrator 内部的执行管线

---

## 4. 目标架构与模块设计

### 4.1 SwiftPM 模块图

`ExecuteHarness` 本地包（`Sage/Agent/Execute/Harness/Package.swift`）随 phase 推进扩展。模块边界 = codex crate 边界，依赖方向与 codex 一致：

```
CodexProtocol        ← codex-rs/protocol            [Phase 1] 纯值类型，Codable，无依赖
CodexUtils           ← codex-rs/utils 子集           [Phase 1]
CodexAsyncUtils      ← codex-rs/async-utils         [Phase 1] SPM 一个 target 只能有一个
                                                       path，async-utils/ 不在 utils/ 子树，
                                                       故独立模块（与 §5.1 R4a 同类的工程适配）
FileSystem           ← codex-rs/file-system         [已有，Phase 2 补齐]
ApplyPatch           ← codex-rs/apply-patch         [已有，Phase 2 补齐]  deps: FileSystem
CodexShellCommand    ← codex-rs/shell-command       [Phase 3]
CodexSandboxing      ← codex-rs/sandboxing          [Phase 3]  macOS seatbelt 全量
CodexExecPolicy      ← codex-rs/execpolicy          [Phase 3，风险项 §10.1]
CodexHooks           ← codex-rs/hooks               [Phase 8]
CodexSkills          ← codex-rs/skills + agent-roles [Phase 8]
CodexRollout         ← codex-rs/rollout             [Phase 7]
CodexCore            ← codex-rs/core 其余全部        [Phase 4–5 逐步迁入]
                       deps: 以上全部
ToolsRuntimes        ← core/src/tools/runtimes      [已有；Phase 4 并入 CodexCore 或保留，
                       deps: ApplyPatch              取决于可见性拆分需要]
```

**为什么 core 要是独立 SPM 模块（而非继续留在 app target）**：

1. codex 中 core 是独立 crate，`pub(crate)` 语义只有在独立 Swift module 中才能对应 `internal`；
2. SPM target 无法 import app 类型——**强制** harness 不依赖 Sage，从构建系统上保证忠实度；
3. 独立编译 + 独立单测，迭代速度快于 app target。

### 4.2 三层边界

```
┌─ App 层（Sage app target）──────────────────────────────
│  Plan / Review / TurnCoordinator / AgentRuntime / UI
│  持有 harness 会话句柄，订阅事件驱动 UI
├─ 适配层（Sage app target，实现 harness 定义的 protocol）─
│  SageModelClient        → harness ModelClient 协议（桥 AgentModelGateway）
│  PathGuardFileSystem    → ExecutorFileSystem 协议
│  HUDApprovalSink        → 审批/elicitation 协议（弹卡片、问用户）
│  SeatbeltSandboxSupport → 沙盒执行支持（进程 spawn、profile 应用）
│  GRDBThreadStore        → ThreadStore 协议（桥现有 GRDB task store）
│  SageMCPHub             → MCP 管理协议（桥 CapabilityStore/MCPStdioClient）
│  SageSettingsBridge     → Config 提供（桥 Settings）
├─ Harness 层（ExecuteHarness SPM，忠实复写）──────────────
│  CodexCore: session / turn / tasks / tools / state /
│  context_manager / compact / guardian / client ...
│  ⚠️ 禁止 import Sage app 类型；一切外部能力经 protocol 注入
└─────────────────────────────────────────────────────────┘
```

**注入点即 codex 的 trait 边界**：Rust 里 `dyn Trait` 出现的地方，Swift 定义 `protocol`；codex 构造 `Session`/`ThreadManager` 时传入具体实现的位置，就是 Sage 适配层的接线位置。

### 4.3 现有 app-target harness 文件的迁移路径

当前 `tools/*.swift`、`tools/handlers/`、`session/`、`tasks/`、`guardian/`、`hook_runtime.swift`、`config/` 编译在 app target 内（它们闭合引用 `PathGuard`、`AgentTool`、`TurnCoordinator`）。迁移规则：

1. **每个 phase 内**，先把该区域的 codex 忠实 port 写入对应 SPM 模块（只依赖 `CodexProtocol` + 注入 protocol）；
2. 然后把 app-target 旧文件改为薄适配（或直接删除，调用点改接 harness）；
3. 迁移期间允许「双轨」短暂共存，但同一机制不得有两份语义——旧文件删除前，其调用点必须全部切换；
4. `Package.swift` 头部注释（模块划分理由）随每次结构调整同步更新。

---

## 5. 目录与文件映射规范

### 5.1 映射规则（强制）

| # | 规则 |
|---|---|
| R1 | `codex-rs/core/src/<path>.rs` → `Sage/Agent/Execute/Harness/<path>.swift`（core crate 映射到 Harness 根，沿用现有惯例） |
| R2 | `codex-rs/<crate>/src/<path>.rs` → `Sage/Agent/Execute/Harness/<crate>/src/<path>.swift`（独立 crate 保留 crate 目录名，如 `apply-patch/src/parser.swift`） |
| R3 | Rust `mod.rs` → Swift `mod.swift`（mod.rs 中有实际类型/函数时；纯 `mod` 声明无对应物） |
| R4 | 文件名保持 snake_case 不变；一个 Rust 文件 → 一个 Swift 文件，禁止合并或拆分 |
| R4a | **模块内 basename 冲突**：Swift 要求同一 module 内文件名唯一（swiftc 拒绝两个 `lib.swift`）。冲突时**先到先得**（仓库中已存在的文件保留原名）；同批多个新文件冲突时按 codex 路径排序，首个保留原名；其余加前缀：crate 文件用 crate 目录名（`-`→`_`，如 `utils/path-uri/src/lib.rs` → `utils/path-uri/src/path_uri_lib.swift`），core 文件用父目录名（如 `sandboxing/mod.rs` → `sandboxing_mod.swift`）。`harness_port.py` 自动判定 |
| R5 | 测试：`…/<path>_tests.rs` 与 `…/tests/**` → `SageTests/ExecuteHarness/<crate>/tests/suite/<path>.swift`（沿用现有目录）；fixture 原样拷贝到 `…/tests/fixtures/` |
| R6 | 平台排除文件**不建** Swift 文件，在追踪表（§9.2）标记 `excluded(platform)` + 原因 |
| R7 | 适配文件仍建同名 Swift 文件，文件头标 `Port status: adapted` 并说明差异 |
| R8 | Sage 新增、无 codex 对应的文件（如 `tasks/explore.swift`）必须标注 `// Sage addition (no codex counterpart)`，且不得放在会造成映射歧义的位置 |

### 5.2 文件头模板（强制）

```swift
//
//  <file>.swift
//  Sage
//
//  Port of codex-rs/<crate>/src/<path>.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful | adapted | partial | stub
//
//  <2–4 句行为摘要；adapted/partial 时必须写清与上游的差异及原因>
//
```

`stub` 仅允许出现在「依赖尚未就绪的过渡 phase」，进入 Phase 5 后不允许新增 stub。

### 5.3 命名与类型

- Rust 类型名原样保留（`TurnContext`、`ToolOrchestrator`、`SessionState`），不做 Swift 化改名；
- 函数名按 Swift API 规范改写（`run_turn` → `runTurn`），但在追踪表中保持 codex 原名可检索；
- 与 Swift 标准库重名时以模块名限定（`CodexProtocol.Event`），不改类型名。

---

## 6. Rust → Swift 翻译规范

### 6.1 类型系统对照

| Rust | Swift | 备注 |
|---|---|---|
| `Option<T>` | `T?` | |
| `Result<T, E>` | `throws`（API 边界）/ `Result`（需显式传递或存储时） | 每个文件内保持一致 |
| `Arc<T>`（共享只读） | `final class: Sendable`，属性 `let` | |
| `Arc<Mutex<T>>` / `Arc<RwLock<T>>` | `actor`（首选）或 `OSAllocatedUnfairLock` 保护的 `final class: @unchecked Sendable` | 选择写在文件头摘要里 |
| `&self` 只读方法 | `nonmutating` / 值语义 `struct` | codex 大量 `struct` 可直接成 Swift `struct` |
| `trait` + `dyn Trait` | `protocol` + `any P` | |
| `impl Trait` 参数 | `some P` / 泛型 | |
| 生命周期标注 `<'a>` | 一般省略；涉及借用闭包时改 `borrowing` 语义或拷贝 | 逐处评审 |
| `Duration` / `Instant` | `Duration` / `ContinuousClock.Instant` | |
| `PathBuf` / `AbsolutePathBuf` | 移植 `utils/absolute-path` 的严格路径类型；底层用 `URL(filePath:)` | 禁止裸 `String` 当路径 |
| `Bytes` / `ByteBuf` | `Data` | |
| `HashMap` / `IndexMap` | `Dictionary` / 自实现有序字典（IndexMap 保序语义不能丢） | |
| `serde_json::Value` | 自实现 `JSONValue: Codable` enum（Phase 1 交付） | |
| `#[derive(thiserror::Error)]` | `enum: Error, CustomStringConvertible` | 错误消息文案对齐 |
| `tracing::info!/warn!` | `os.Logger`（适配层统一封装 `HarnessLog`） | |
| `OnceCell` / `LazyLock` | `lazy let`（类内）/ 一次性初始化 helper | |

### 6.2 并发模型对照（tokio → Swift Concurrency）

| tokio | Swift | 备注 |
|---|---|---|
| `tokio::spawn` | `Task {}` / `Task.detached {}` | |
| `tokio::sync::mpsc::channel` | `AsyncThrowingChannel` 风格封装 / actor 邮箱 | Phase 1 在 `CodexUtils` 交付统一封装 |
| `tokio::select!` | `async let` + 首个完成语义的 helper，或 `TaskGroup` | codex 的 select 语义（取消其余分支）必须保留 |
| `CancellationToken` | 结构化取消（`Task.isCancelled` / `withTaskCancellationHandler`） | token 的「同步立即取消」语义差异处逐处标注 |
| `spawn_blocking`（阻塞 IO/进程） | `Task.detached(priority:)` / 专用 `DispatchQueue` | 禁止阻塞 cooperative 线程池 |
| `tokio::time::sleep/timeout` | `Task.sleep` / `withThrowingTaskGroup` 竞速 | |
| `Notify` | `AsyncStream` 单元素 / `CheckedContinuation` 封装 | |

**隔离约定**：harness 核心类型（`Session`、`ActiveTurn`、工具运行时）用 `actor` 隔离 + `Sendable` 值类型；`@MainActor` 只允许出现在适配层/UI 桥接。现有 `turn.swift` 的 `@MainActor` 是过渡形态，Phase 5 迁移时 actor 化。

### 6.3 serde → Codable

codex 的 wire 格式由 serde 属性决定，必须逐字段核对：

| serde | Swift 写法 |
|---|---|
| 默认外部标签 enum | 手写 `Codable`（单键容器） |
| `#[serde(tag = "type")]` | 手写 discriminator 解码 |
| `#[serde(untagged)]` | 按字段存在性逐个尝试解码 |
| `rename_all = "snake_case"` | 显式 `CodingKeys`（不依赖全局 keyDecodingStrategy，避免误伤嵌套） |
| `#[serde(default)]` | `decodeIfPresent` + 默认值 |
| `#[serde(flatten)]` | 展平字段逐一解码 |
| `deny_unknown_fields` | `rejectUnknownFields(in: decoder, ...)`（serde_helpers.swift）。**陷阱**：raw-value enum `CodingKeys` 的 `allKeys` 会静默丢弃未知键（`init?(stringValue:)` 返回 nil），必须经 `JSONCodingKey` 容器读全量键 |
| `BTreeMap` / 键序 | `JSONValue.encodedString()` 提供 serde_json 语义（对象键排序）。**陷阱**：Foundation `JSONEncoder` 输出键序不定，struct 字段也无法按声明序输出；逐字节对拍必须走 `encodedString()`，`Codable` 直编仅保证语义等价 |

**验收**：Phase 1 交付时，用 codex 测试里的 JSON fixture 做双向 round-trip 对拍（编码结果与 Rust serde 输出逐字节一致）。

### 6.4 可见性

- Rust `pub(crate)` → Swift `internal`（同一 module 内，依赖 §4.1 的模块划分成立）；
- 跨 crate `pub` → `public`；
- 适配层需要而 codex 未公开的钩子点：标 `public` 并在文件头注明（对应 Rust 侧会是 `pub(crate)` + feature 钩子的位置）。

### 6.5 禁止事项

- 禁止在 Harness 层 import Sage app 模块/类型；
- 禁止用 `fatalError` 顶替错误处理（codex 的 `panic!`/`unwrap` 语义 → `preconditionFailure`，可恢复错误 → `throws`）；
- 禁止合并/拆分文件（R4）；
- 禁止静默改变行为语义（任何有意偏差 → 文件头 `adapted` 说明）。

---

## 7. 分阶段实施计划

> 每个 phase 独立可交付、可构建、可测试；phase 间按依赖排序。行数为 codex 侧非测试行数，用于量级估算。

### Phase 0 — 规范与追踪落地

- **产出**：① 本计划评审定稿；② 建立 `Harness/PORTING.md` 追踪表（以附录 A/B 为初始基线，391 + 依赖 crate 全量文件，逐文件状态）；③ 文件头 lint 脚本（检查 `Port of` / `Upstream revision` / `Port status` 三要素）；④ 确认 `ExecuteHarness` 包独立构建与测试 target 可用。
- **验收**：追踪表覆盖范围内 100% 文件；lint 在 CI/本地可跑。

### Phase 1 — 协议与基础类型层（~40,000 行）

- **范围**：`protocol` crate 全部 55 文件（`protocol.rs` 6,444 / `models.rs` 4,565 / `permissions.rs` 4,488 / `openai_models.rs` 1,935 / `config_types.rs` / `error.rs` / `items.rs` / `mcp.rs` / `approvals.rs` / `turn_input.rs` / `exec_output.rs` / `user_input.rs` / `session_id.rs` / `thread_id.rs` / `tool_name.rs` / `plan_tool.rs` …）；`utils` 子集（absolute-path、path、path-uri、path-utils、output-truncation、string、stream-parser、cache、home-dir、git-discovery、image）+ `async-utils`；core 的 `util.rs`、`utils/`。
- **产出**：`CodexProtocol`、`CodexUtils` 两个 SPM 模块；`JSONValue`、channel/取消封装等并发基础设施。
- **验收**：serde↔Codable round-trip 对拍测试（用 codex JSON fixture）；`permissions.rs` 的 profile 求交/校验逻辑单测移植。

### Phase 2 — 文件系统与补丁（~10,000 行）

- **范围**：`file-system` 补齐（`lib.rs` 712 全量、`environment_accessor.rs` 280、`find_up.rs` 126）；`apply-patch` 补齐（`lib.rs` 1,444 vs 现有 407——缺 verified apply / cwd 解析 / 调用链完整路径；`invocation.rs` 1,036 vs 现有 111；`streaming_parser.rs` 924 vs 现有 293；`standalone_executable.rs` 标记适配——进程内调用）；`git-utils` 子集（`info.rs`、`baseline.rs`、`apply.rs`、`trust.rs`——`turn_diff_tracker` 与基线 diff 需要）。
- **迁移**：现有 7 个 apply-patch 文件逐文件对照上游补全，文件头 `partial` → `faithful`。
- **验收**：现有 25 个 scenario fixture 继续全过 + codex `apply-patch` 的 parser/file_update/seek_sequence 单测移植全过。

### Phase 3 — 执行与沙盒（~24,000 行）

- **范围**：`sandboxing` crate（`seatbelt.rs` 1,122 全量、`manager.rs` 802、`policy_transforms.rs` 670、`spawn.rs`、`violation.rs`、`denial.rs`、`seatbelt_scratch.rs`、`terminal_queries.rs`；`landlock/bwrap/windows/mxc` 平台排除）；`shell-command`（`parse_command.rs` 2,766、`bash.rs`、`shell_detect.rs`、`command_safety/is_dangerous_command.rs`、`shell_snapshot*`；PowerShell/Windows 部分适配标注）；`execpolicy`（**风险项 §10.1，先做 spike**）；`utils/pty`（macOS `forkpty` 路径）；core 内 `exec.rs`、`exec_env.rs`、`exec_policy.rs` + `exec_policy/`、`shell.rs`、`shell_snapshot.rs` + `_sandbox`、`spawn.rs`、`safety.rs`、`sandbox_tags.rs`、`sandboxing/mod.rs`、`command_canonicalization.rs`、`user_shell_command.rs`、`unified_exec/` 全部 10 文件（4,105 行）。
- **产出**：`CodexShellCommand`、`CodexSandboxing`、`CodexExecPolicy` 模块；core 侧执行文件（先入 app target 过渡或直接入 `CodexCore`，视 Phase 4 节奏）。
- **验收**：seatbelt profile 生成与 codex 输出对拍；`parse_command` / 危险命令判定单测移植；`unified_exec` 进程管理（spawn/复用/输出截断/stdin 审批）行为测试。

### Phase 4 — 工具系统（~28,000 行）

- **范围**：core `tools/` 全量——`router.rs` 385、`registry.rs` 851、`spec_plan.rs` 1,479、`parallel.rs` 787、`orchestrator.rs` 551、`approvals.rs` 884、`events.rs` 885、`context.rs` 607、`lifecycle.rs`、`sandboxing.rs` 561、`network_approval.rs` 1,254、`executed_tool_calls*` ~1,200、`call_trace` / `tool_dispatch_trace` / `hook_names` / `hosted_spec` / `user_messaging` / `catalog_parameters` / `tool_namespaces_info` / `control_tool_analytics` / `multi_agent_tool`；`handlers/` 全部（`mod.rs` 616、`mcp.rs` 882、`extension_tools.rs` 640、`apply_patch.rs` 641 已有、`shell_spec.rs` 348、`unified_exec*` 873、`view_image.rs` 526、`tool_search.rs` 487、`request_user_input*` 465、`plan.rs` + spec、`sleep`、`current_time`、`request_permissions`、`new_context_window*`、`get_context_remaining*`、`test_sync*`、`send_message_to_user_async`、`dynamic.rs`、`mcp_resource*` ~800；`multi_agents*` / `request_plugin_install*` / `list_available_plugins*` 归 Phase 9）；`runtimes/` 全量（`mod.rs` 918、`unified_exec.rs` 975、`apply_patch.rs` 242、`zsh_fork.rs` 105 + `unix_escalation.rs` 875）；`function_tool.rs`；`network_policy_decision.rs`。
- **迁移**：现有 `orchestrator.swift` / `parallel.swift` / `approvals.swift` / `sandboxing.swift` / `network_approval.swift` / `handlers/apply_patch*.swift` 逐文件对照上游补全并迁入 `CodexCore`；`ToolBatchExecutor+Waves` 的波次语义收敛到 `parallel.rs` 准入模型；`SessionToolAllowlist` 与 `ApprovalStore` 合并为单一审批缓存（HUD 交互留在适配层）。
- **验收**：工具注册表/规格快照测试；orchestrator「审批→沙盒→尝试→升级重试」行为测试扩展现有 313 行套件；parallel 准入/并发票测试；每个 handler 至少一个行为用例。

### Phase 5 — 会话、回合与上下文（~49,000 行，核心中的核心）

- **范围**：
  - `state/` 全部 6 文件（`session.rs` 475、`turn.rs` 254、`service.rs`、`auto_compact_window.rs` 237、`turn_token_usage.rs`、`additional_context.rs`）；
  - `session/` 全部 ~40 文件（`mod.rs` 5,130、`turn.rs` 3,105、`session.rs` 1,915、`turn_context.rs` 1,386、`turn_input.rs` 765、`handlers.rs` 681、`input_queue.rs` 669、`mcp.rs` 1,206 + `mcp_runtime/prewarm/refresh`、`rollout_reconstruction.rs` 575、`step_activation/settings/context` 876、`environment.rs` 307、`world_state.rs` 295、`token_budget.rs` 248、`review.rs` 229、`time_reminder.rs`、`inject.rs`、`reasoning_effort.rs`、`thread_settings.rs`、`context_window.rs`、`turn_suspension.rs`、`extension_*`、`retained_context`、`rollout_budget`、`plugin_selection`、`code_mode_warning`、`submission`、`startup`、`daemon_recovery`、`guardian_checkpoint`；`multi_agents.rs` 归 Phase 9，`realtime_history.rs` 归 Phase 10）；
  - `tasks/` 全部（`mod.rs` 1,014——`SessionTask` 生命周期；`regular.rs` 126、`compact.rs` 76、`review.rs` 280、`user_shell.rs` 485、`lifecycle.rs` 119）；
  - `context/` 全部 ~60 文件（prompt fragments + `world_state/`）；`context_manager/`（`history.rs` 1,225、`normalize.rs` 420、`updates.rs`、`history_user_authorization.rs`）；
  - 压缩：`compact.rs` 852、`compact_remote_v2.rs` 1,273、`compact_remote_history.rs`、`compact_model_fallback.rs`、`compact_token_budget.rs`；
  - `stream_events_utils.rs` 586、`event_mapping.rs` 261、`turn_metadata.rs` 569、`turn_timing.rs` 443、`turn_diff_tracker.rs` 403；
  - `config/`（`mod.rs` 4,893、`permissions.rs` 893、`edit.rs` 1,001 等 ~9,200 行）：**适配桥接**——移植 `Config` 类型形状与合并/优先级语义，配置源接 Sage Settings（§10.4）；
  - MCP 接线：`mcp.rs` 394、`mcp_tool_call.rs` 2,504 + `mcp_tool_call/`、`mcp_tool_exposure.rs`、`mcp_skill_dependencies.rs`、`mcp_tool_approval_templates.rs`、`mcp_openai_file.rs`——harness 侧机制忠实移植，传输层适配 Sage `MCPStdioClient`（§10.6）。
- **迁移**：`session/turn.swift`（67 行骨架）与 `tasks/regular.swift`、`tasks/compact.swift` 被忠实 port 取代；`TurnCoordinator` 退化为持有 harness 会话、订阅事件；actor 化改造（§6.2）。
- **验收**：回合循环 golden 测试——用假 `ModelClient` 回放 `ResponseEvent` 流，对齐 codex `session/turn_tests.rs` 与 `session/tests.rs` 的关键场景（工具跟进、压缩触发、中断、转向输入）；`context_manager/history` 规范化与压缩边界测试；token 预算/占用率测试。

### Phase 6 — 模型客户端（~9,000 行）

- **范围**：`client.rs` 2,852、`client_common.rs` 141（`Prompt`/`ResponseEvent`/`ResponseStream`）、`responses_headers.rs`、`responses_metadata.rs` 592、`responses_retry.rs` 180、`prompt_debug.rs`、`image_preparation.rs` 428、`original_image_detail.rs`、`current_time.rs`、`web_search.rs`；`model-provider-info` 924；`codex-api` 的 SSE responses 子集（`sse/responses.rs` 2,124 等 ~4,000 行）。
- **适配**：HTTP/SSE 传输用 `URLSession` bytes 流（Sage 已有 SSE 实现，此处对齐 codex 的重试/退避/头语义）；鉴权走适配层（API Key / ChatGPT auth 暂缓）。
- **验收**：SSE 解析 golden 测试（codex sse fixture）；重试/限流（429 + `Retry-After`）行为与 Sage 现有 `RetryPolicy` 对齐合并。

### Phase 7 — 持久化与线程（~58,000 行，适配为主）

- **范围**：`rollout` crate（`recorder.rs` 2,249、`list.rs` 1,703、`compression.rs` 1,403、`state_db.rs` 744 等 9,334 行）——JSONL rollout **忠实移植**；`state` crate（20,362 行）与 `thread-store`（22,930 行）——**语义对齐、存储适配 GRDB**（Sage 已有 GRDB task store，schema 对齐 codex 表结构）；core 内 `rollout.rs`、`rollout_budget.rs`、`thread_rollout_truncation.rs` 305、`thread_manager.rs` 2,583 + `thread_manager/`、`codex_thread.rs` 1,065、`codex_delegate.rs`、`session_prefix.rs`、`thread_startup_metadata.rs`、`state_db_bridge.rs`、`session_rollout_init_error.rs`、`memory_usage.rs`、`installation_id.rs`、`feedback_config.rs`、`attestation.rs`。
- **验收**：rollout 写入→回放 round-trip（与 codex JSONL 格式逐字节对拍）；thread 列表/恢复/fork 行为测试；与 Sage 现有 task 持久化的迁移/共存方案评审。

### Phase 8 — Guardian、Hooks、Skills 完整版（~19,500 行）

- **范围**：`guardian/` 补齐到全量（`review_session.rs` 947、`approval_request.rs` 564、`prompt.rs` 365、`review.rs` 287、`review_session_setup.rs` 265、`review_request.rs` 224、`input_budget.rs` 197、`mod.rs` 208、`decision.rs` 132、`reviewer_config.rs` 109、`runtime.rs` 92、`request_budget.rs` 90、`coverage.rs`、`feedback.rs`、`review_session_context.rs`；现有 14 个薄文件逐一对照补全）+ `guardian_review.rs`；`hook_runtime.rs` 1,352（现有 170）+ `hook_mcp_executor.rs`；`hooks` crate 11,657 行（`engine/discovery.rs` 1,741、`schema.rs` 1,254、`events/pre_tool_use.rs` 820、`events/stop.rs` 723、`events/post_tool_use.rs` 637、`engine/dispatcher.rs` 656 等）；`skills` crate 1,493 + core `skills.rs` 210；`agent-roles` 592；`agents_md.rs` 562 + `agents_md_manager.rs`；`elicitation.rs`；`mention_syntax.rs`；`context-fragments`。
- **迁移**：`PreToolUseHooks`（声明式）与 `HookRuntime`/`hooks` crate 收敛为一套钩子语义（§3.3）；guardian 与 Sage Review 层的关系定稿（guardian 是 execute 内的隔离审查者；Review 层是任务级复盘——两者并存，文档化边界）。
- **验收**：guardian 决策/预算/证据链测试（对齐 `guardian/tests.rs` 关键场景）；hooks schema 校验与 discovery 单测；skills 加载/提及解析单测。

### Phase 9 — 多智能体与高级特性（~15,000 行，按需启动）

- **范围**：`agent/` 全部（~5,700 行，`control/spawn.rs` 1,380 等）；`tools/handlers/multi_agents*`（~4,000 行）；`session/multi_agents.rs`；`tools/code_mode/`（~2,000 行）；`plugins/`、`apps/`、`connectors.rs` 555、`environment_selection.rs` 2,311、`cyber_access_program.rs`。
- **对接**：此 phase 把 Sage 的 Plan/Execute/Review 三层编排映射到 codex 的 `ThreadManager`/`AgentControl` 语义——Plan agent = 上游 `plan` 工具/角色配置的 Sage 形态，Review agent = `tasks/review.rs` + guardian 的组合。启动前需单独评审 Sage 三层架构与 codex 多智能体模型的对应关系。
- **验收**：子 agent spawn/wait/消息传递行为测试。

### Phase 10 — 暂缓与平台项（收尾对齐）

- `realtime_*`（~6,100 行）：Sage 无语音形态，保持 `deferred`；若未来接入，按本规范复写。
- `otel_init.rs` / `otel` crate：裁剪为最小指标接口（turn 计时、token 用量），接 Sage 现有埋点。
- 平台排除项复核：确认所有 `excluded(platform)` 在追踪表中有记录且无 Swift 空文件。
- `lib.rs`（247 行门面）：最后移植，导出清单与 codex 对齐。

### 量级汇总

| Phase | codex 行数 | 主要内容 | 现有基础 |
|---|---:|---|---|
| 0 | — | 规范/追踪 | — |
| 1 | ~40,000 | 协议类型 + 工具库 | 无 |
| 2 | ~10,000 | file-system / apply-patch / git-utils | 🟡 部分 |
| 3 | ~24,000 | 沙盒 / shell / execpolicy / PTY / unified_exec | 无 |
| 4 | ~28,000 | 工具系统全量 | 🟡 骨架 |
| 5 | ~49,000 | 会话/回合/上下文/压缩/配置 | 🟡 骨架 |
| 6 | ~9,000 | 模型客户端 | 无（Sage 有 SSE 可桥） |
| 7 | ~58,000 | 持久化/线程（适配为主） | Sage GRDB 可桥 |
| 8 | ~19,500 | guardian/hooks/skills | 🟡 薄骨架 |
| 9 | ~15,000 | 多智能体/高级 | 无 |
| 10 | ~6,000+ | 暂缓/平台收尾 | — |
| **合计** | **~258,000** | | 已移植 ~4,700 |

---

## 8. 测试策略

1. **逐文件移植测试**：codex 的 `*_tests.rs`（~117,000 行）分级移植——
   - **P0 golden/行为级**（必做）：apply-patch scenarios（已有 25 fixture）、parser 套件、execpolicy 决策、seatbelt profile 对拍、`parse_command`、history 规范化、compact 占用率、rollout round-trip、SSE 解析、turn 循环回放；
   - **P1 单元级**：每个 ported 文件的核心纯函数；
   - **P2 集成级**：需要进程/网络的（unified_exec 端到端、MCP 全链路），用 Sage 测试宿主。
2. **fixture 共享**：直接从 `codex/` 仓库拷贝 fixture（沿用 `apply-patch/tests/fixtures/scenarios/` 的做法），不手抄。
3. **对拍**：凡 wire 格式（serde JSON、rollout JSONL、SSE 帧、seatbelt profile），用 Rust 侧输出做 golden 逐字节比对。
4. **回归**：每个 phase 结束时 `SageTests/ExecuteHarness/**` 全绿 + app 侧现有测试（TurnTests、ToolLoopPolicyTests 等）不回归。
5. 测试文件同样遵守 §5 映射与文件头规范。

---

## 9. 上游对齐与追踪机制

### 9.1 基线 pin

- 全量 pin 在 `0a2eb4696c26ac33204bcd255721ab30220a4774`；每个 Swift 文件头标注（§5.2）。
- 工作区 `codex/` 仓库保持只读引用，不在其中开发。

### 9.2 追踪表（`Harness/PORTING.md`，Phase 0 建立）

逐文件一行：`codex 路径 | Swift 路径 | 状态(未开始/stub/partial/adapted/faithful/excluded/deferred) | 上游 revision | 备注`。本计划附录 A/B 为初始基线。每次 PR 更新涉及行；文件头 lint 校验头与表一致。

### 9.3 上游升级流程

1. `cd codex && git fetch && git log --oneline <pin>..origin/main -- codex-rs/core codex-rs/protocol …`；
2. 按文件 diff，逐文件更新 Swift 实现与头部 revision；
3. 升级作为独立 PR，不与新 port 混杂；
4. 频率：每月一次，或上游出现 harness 行为级变更时即时跟进。

---

## 10. 风险与决策点

| # | 风险/决策 | 说明与对策 |
|---|---|---|
| 10.1 | **execpolicy 的 Starlark 求值器** | `execpolicy`（1,954 行）依赖 Rust `starlark` crate，Swift 无成熟等价物。Phase 3 先做 spike：① 移植 `parser.rs`/`policy.rs` 决策语义 + 实现规则子集求值器（前缀规则足够覆盖默认策略）；② 若子集不成立，标记 `adapted`，用 Sage 现有命令安全策略补齐，差异写进文件头。 |
| 10.2 | **tokio → Swift Concurrency 语义差** | `select!` 取消语义、`CancellationToken` 同步取消、`spawn_blocking` 线程模型不同。对策：§6.2 对照表 + 每处差异文件头标注 + Phase 1 交付统一并发封装。 |
| 10.3 | **PTY（`utils/pty` 5,302 行）** | macOS 有 `forkpty`，路径可行但行为差异（终端尺寸、信号、job control）需逐条核对；`unified_exec` 依赖它。Phase 3 早期验证。 |
| 10.4 | **`config/mod.rs` 4,893 行 vs Sage Settings** | codex 的 config.toml + managed config 体系与 Sage Settings 模型不同。对策：移植 `Config` 类型与合并/优先级语义，配置源桥接 Sage Settings；`config/edit.rs`（toml 编辑）标记适配。 |
| 10.5 | **`state`/`thread-store` 43,000 行 vs Sage GRDB** | 逐行复写收益低、风险高（与现有 task 持久化冲突）。对策：schema 与读写语义对齐，存储引擎用 GRDB；rollout JSONL 部分忠实移植（格式是跨工具契约）。 |
| 10.6 | **MCP：rmcp-client vs Sage `MCPStdioClient`** | harness 机制（工具暴露、审批模板、调用遥测）忠实移植；传输/进程管理适配 Sage 现有实现。 |
| 10.7 | **工作量** | ~25.8 万行 Rust 在范围内，是长期工程；每个 phase 独立可用，Phase 1→5 是 harness 对齐的关键路径（~15 万行），Phase 6 之后可按 Sage 产品节奏穿插。 |
| 10.8 | **双轨期行为漂移** | Phase 4–5 迁移期旧粘合层与新 port 短暂共存，必须遵守 §4.3「同一机制不得有两份语义」，切换以调用点为单位原子完成。 |

---

## 附录 A：`codex-rs/core` 全量文件映射表（391 文件，按 phase 分组）

> 状态图例：✅ 已移植（忠实）｜🟡 已移植（partial/adapted/薄）｜⬜ 待移植｜⛔ 平台排除｜💤 暂缓（deferred）｜➕ Sage 新增（无 codex 对应）
> Swift 目标路径按 §5.1 R1 机械推导（`Harness/<path>.swift`），不再逐行列出；仅标注例外。

### Phase 3 — 执行与沙盒（core 内）

| codex 文件（`core/src/`） | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `exec.rs` | 1,276 | ⬜ | |
| `exec_env.rs` | 117 | ⬜ | |
| `exec_policy.rs` | 1,175 | ⬜ | 依赖 execpolicy crate（§10.1） |
| `exec_policy/executable_identity.rs` | 107 | ⬜ | |
| `exec_policy/model_policy.rs` | 60 | ⬜ | |
| `shell.rs` | 104 | ⬜ | |
| `shell_snapshot.rs` | 1,169 | ⬜ | |
| `shell_snapshot_sandbox.rs` | 224 | ⬜ | |
| `spawn.rs` | 137 | ⬜ | |
| `safety.rs` | 144 | ⬜ | |
| `sandbox_tags.rs` | 114 | ⬜ | |
| `sandboxing/mod.rs` | 218 | ⬜ | → `sandboxing/mod.swift`（R3） |
| `command_canonicalization.rs` | 42 | ⬜ | |
| `user_shell_command.rs` | 44 | ⬜ | |
| `unified_exec/mod.rs` | 249 | ⬜ | |
| `unified_exec/process_manager.rs` | 1,881 | ⬜ | |
| `unified_exec/process.rs` | 652 | ⬜ | |
| `unified_exec/async_watcher.rs` | 482 | ⬜ | |
| `unified_exec/stdin_approval.rs` | 249 | ⬜ | |
| `unified_exec/shell_snapshot.rs` | 202 | ⬜ | |
| `unified_exec/head_tail_buffer.rs` | 169 | ⬜ | |
| `unified_exec/oneshot.rs` | 123 | ⬜ | |
| `unified_exec/errors.rs` | 71 | ⬜ | |
| `unified_exec/process_state.rs` | 27 | ⬜ | |
| `windows_sandbox.rs` | 456 | ⛔ | platform |
| `windows_sandbox_read_grants.rs` | 41 | ⛔ | platform |
| `windows_system_config.rs` | 35 | ⛔ | platform |

### Phase 4 — 工具系统

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `tools/mod.rs` | 147 | ⬜ | → `tools/mod.swift` |
| `tools/router.rs` | 385 | ⬜ | `ToolRouter` |
| `tools/registry.rs` | 851 | ⬜ | |
| `tools/spec_plan.rs` | 1,479 | ⬜ | 回合工具计划 |
| `tools/parallel.rs` | 787 | 🟡 | 波次替代 RWLock 准入，需收敛 |
| `tools/orchestrator.rs` | 551 | 🟡 | 形状对齐，去 `ToolInvocationPipeline` 依赖 |
| `tools/approvals.rs` | 884 | 🟡 | 与 `SessionToolAllowlist` 合并 |
| `tools/events.rs` | 885 | ⬜ | |
| `tools/context.rs` | 607 | ⬜ | |
| `tools/lifecycle.rs` | 175 | ⬜ | |
| `tools/sandboxing.rs` | 561 | 🟡 | Mac 适配版，需补全 |
| `tools/network_approval.rs` | 1,254 | 🟡 | 决策层已有，补全 |
| `tools/executed_tool_calls.rs` | 629 | ⬜ | |
| `tools/executed_tool_calls/mcp_attribution.rs` | 169 | ⬜ | |
| `tools/executed_tool_calls/request_metadata.rs` | 441 | ⬜ | |
| `tools/executed_tool_calls/seen_ids.rs` | 133 | ⬜ | |
| `tools/call_trace.rs` | 88 | ⬜ | |
| `tools/tool_dispatch_trace.rs` | 128 | ⬜ | |
| `tools/hook_names.rs` | 67 | ⬜ | |
| `tools/hosted_spec.rs` | 50 | ⬜ | |
| `tools/user_messaging.rs` | 33 | ⬜ | |
| `tools/catalog_parameters.rs` | 14 | ⬜ | |
| `tools/tool_namespaces_info.rs` | 111 | ⬜ | |
| `tools/control_tool_analytics.rs` | 58 | ⬜ | |
| `tools/multi_agent_tool.rs` | 133 | ⬜ | Phase 9 联动 |
| `tools/handlers/mod.rs` | 616 | ⬜ | |
| `tools/handlers/apply_patch.rs` | 641 | ✅ | 需随 runtimes 补全更新 |
| `tools/handlers/apply_patch_spec.rs` | 32 | 🟡 | JSON 工具形态（上游 freeform grammar，差异已标注） |
| `tools/handlers/shell_spec.rs` | 348 | ⬜ | |
| `tools/handlers/unified_exec.rs` | 159 | ⬜ | |
| `tools/handlers/unified_exec/exec_command.rs` | 569 | ⬜ | |
| `tools/handlers/unified_exec/write_stdin.rs` | 145 | ⬜ | |
| `tools/handlers/mcp.rs` | 882 | ⬜ | 传输适配 Sage MCP |
| `tools/handlers/mcp_resource.rs` | 414 | ⬜ | |
| `tools/handlers/mcp_resource/list_mcp_resource_templates.rs` | 102 | ⬜ | |
| `tools/handlers/mcp_resource/list_mcp_resources.rs` | 100 | ⬜ | |
| `tools/handlers/mcp_resource/read_mcp_resource.rs` | 99 | ⬜ | |
| `tools/handlers/mcp_resource_spec.rs` | 97 | ⬜ | |
| `tools/handlers/plan.rs` | 112 | ⬜ | 与 Sage Plan 层对接点 |
| `tools/handlers/plan_spec.rs` | 58 | ⬜ | |
| `tools/handlers/request_user_input.rs` | 175 | ⬜ | |
| `tools/handlers/request_user_input_async.rs` | 144 | ⬜ | |
| `tools/handlers/request_user_input_spec.rs` | 146 | ⬜ | |
| `tools/handlers/request_permissions.rs` | 209 | ⬜ | |
| `tools/handlers/new_context_window.rs` | 48 | ⬜ | |
| `tools/handlers/new_context_window_spec.rs` | 17 | ⬜ | |
| `tools/handlers/get_context_remaining.rs` | 94 | ⬜ | |
| `tools/handlers/get_context_remaining_spec.rs` | 36 | ⬜ | |
| `tools/handlers/view_image.rs` | 526 | ⬜ | |
| `tools/handlers/view_image_spec.rs` | 74 | ⬜ | |
| `tools/handlers/tool_search.rs` | 487 | ⬜ | |
| `tools/handlers/tool_search_spec.rs` | 221 | ⬜ | |
| `tools/handlers/sleep.rs` | 167 | ⬜ | |
| `tools/handlers/current_time.rs` | 130 | ⬜ | |
| `tools/handlers/dynamic.rs` | 251 | ⬜ | |
| `tools/handlers/extension_tools.rs` | 640 | ⬜ | |
| `tools/handlers/send_message_to_user_async.rs` | 109 | ⬜ | |
| `tools/handlers/test_sync.rs` | 196 | ⬜ | |
| `tools/handlers/test_sync_spec.rs` | 70 | ⬜ | |
| `tools/handlers/wait_for_environment.rs` | 182 | ⬜ | Phase 9 联动 |
| `tools/handlers/multi_agents.rs` | 99 | ⬜ | → Phase 9 |
| `tools/handlers/multi_agents/{spawn,wait,send_input,resume_agent,close_agent}.rs` | 1,056 | ⬜ | → Phase 9 |
| `tools/handlers/multi_agents_common.rs` | 157 | ⬜ | → Phase 9 |
| `tools/handlers/multi_agents_spec.rs` | 891 | ⬜ | → Phase 9 |
| `tools/handlers/multi_agents_v2.rs` + `multi_agents_v2/*` | 990 | ⬜ | → Phase 9 |
| `tools/handlers/request_plugin_install.rs` + spec | 740 | ⬜ | → Phase 9 |
| `tools/handlers/list_available_plugins_to_install.rs` + spec | 226 | ⬜ | → Phase 9 |
| `tools/runtimes/mod.rs` | 918 | ⬜ | |
| `tools/runtimes/apply_patch.rs` | 242 | 🟡 | 薄（42 行），补全 |
| `tools/runtimes/unified_exec.rs` | 975 | ⬜ | |
| `tools/runtimes/zsh_fork.rs` | 105 | ⬜ | |
| `tools/runtimes/zsh_fork/unix_escalation.rs` | 875 | ⬜ | macOS 可用，逐行核对 |
| `tools/code_mode/*`（7 文件） | 2,003 | ⬜ | → Phase 9 |
| `function_tool.rs` | 1 | ⬜ | |
| `network_policy_decision.rs` | 106 | ⬜ | |

### Phase 5 — 会话、回合、上下文、压缩、配置

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `state/mod.rs` / `service.rs` / `session.rs` / `turn.rs` / `auto_compact_window.rs` / `turn_token_usage.rs` / `additional_context.rs` | 1,175 | ⬜ | `SessionState`/`ActiveTurn`/`SessionServices` |
| `session/mod.rs` | 5,130 | ⬜ | 会话构造 + submission 循环 |
| `session/session.rs` | 1,915 | ⬜ | `Session` |
| `session/turn.rs` | 3,105 | 🟡 | 现有 67 行骨架，全量复写 |
| `session/turn_context.rs` | 1,386 | ⬜ | `TurnContext` |
| `session/turn_input.rs` | 765 | ⬜ | 输入准入 |
| `session/input_queue.rs` | 669 | ⬜ | 与 Sage `TurnInputQueue` 合并 |
| `session/handlers.rs` | 681 | ⬜ | |
| `session/mcp.rs` | 1,206 | ⬜ | 传输适配 |
| `session/mcp_runtime.rs` / `mcp_prewarm.rs` / `mcp_refresh.rs` | 519 | ⬜ | |
| `session/rollout_reconstruction.rs` | 575 | ⬜ | 依赖 Phase 7 rollout |
| `session/step_activation.rs` / `step_settings.rs` / `step_context.rs` | 876 | ⬜ | |
| `session/environment.rs` | 307 | ⬜ | |
| `session/world_state.rs` | 295 | ⬜ | |
| `session/token_budget.rs` | 248 | ⬜ | |
| `session/review.rs` | 229 | ⬜ | 与 Sage Review 层边界（§7 Phase 8） |
| `session/time_reminder.rs` | 202 | ⬜ | |
| `session/inject.rs` | 193 | ⬜ | |
| `session/reasoning_effort.rs` | 162 | ⬜ | |
| `session/thread_settings.rs` | 152 | ⬜ | |
| `session/context_window.rs` | 130 | ⬜ | |
| `session/turn_suspension.rs` | 119 | ⬜ | |
| `session/extension_interruption.rs` / `extension_metrics.rs` | 152 | ⬜ | |
| `session/retained_context.rs` / `rollout_budget.rs` / `plugin_selection.rs` / `code_mode_warning.rs` / `submission.rs` / `startup.rs` / `daemon_recovery.rs` / `guardian_checkpoint.rs` | 340 | ⬜ | |
| `session/multi_agents.rs` | 121 | ⬜ | → Phase 9 |
| `session/realtime_history.rs` | 56 | 💤 | → Phase 10 |
| `tasks/mod.rs` | 1,014 | ⬜ | `SessionTask` 生命周期 → `tasks/mod.swift` |
| `tasks/regular.rs` | 126 | ✅ | 需随 `mod.rs` 重构 |
| `tasks/compact.rs` | 76 | 🟡 | 补 remote V2 |
| `tasks/review.rs` | 280 | ⬜ | |
| `tasks/user_shell.rs` | 485 | ⬜ | |
| `tasks/lifecycle.rs` | 119 | ⬜ | |
| —（Sage 新增）`tasks/explore.swift` | 135 | ➕ | 保持标注，不占用 codex 映射 |
| `context/` 全部 ~45 文件 + `context/world_state/` 14 文件 | ~5,900 | ⬜ | prompt fragments / world state 渲染 |
| `context_manager/history.rs` | 1,225 | ⬜ | |
| `context_manager/normalize.rs` / `updates.rs` / `history_user_authorization.rs` / `mod.rs` | 594 | ⬜ | |
| `compact.rs` | 852 | ⬜ | |
| `compact_remote_v2.rs` | 1,273 | ⬜ | |
| `compact_remote_history.rs` / `compact_model_fallback.rs` / `compact_token_budget.rs` | 333 | ⬜ | |
| `stream_events_utils.rs` | 586 | ⬜ | |
| `event_mapping.rs` | 261 | ⬜ | |
| `turn_metadata.rs` / `turn_timing.rs` / `turn_diff_tracker.rs` | 1,415 | ⬜ | |
| `config/mod.rs` | 4,893 | ⬜ | 适配桥接（§10.4） |
| `config/edit.rs` + `edit/*` | 1,381 | ⬜ | 适配 |
| `config/permissions.rs` | 893 | ⬜ | |
| `config/network_proxy_spec.rs` | 546 | 🟡 | 已有 186 行，补全 |
| `config/managed_features.rs` / `network_config.rs` / `otel.rs` / `permission_*` / `requirements.rs` / `resolved_permission_profile.rs` / `schema.rs` / `token_budget_startup.rs` / `auth_keyring.rs` / `metrics.rs` / `windows_sandbox_config.rs` | ~1,700 | ⬜/⛔ | `windows_sandbox_config.rs` ⛔ |
| `mcp.rs` / `mcp_tool_call.rs` + `mcp_tool_call/*` / `mcp_tool_exposure.rs` / `mcp_skill_dependencies.rs` / `mcp_tool_approval_templates.rs` / `mcp_openai_file.rs` | 4,807 | ⬜ | 机制忠实，传输适配（§10.6） |
| `session_startup_prewarm.rs` | 328 | ⬜ | |

### Phase 6 — 模型客户端

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `client.rs` | 2,852 | ⬜ | `ModelClient`/`ModelClientSession` |
| `client_common.rs` | 141 | ⬜ | `Prompt`/`ResponseEvent` |
| `responses_headers.rs` / `responses_retry.rs` | 204 | ⬜ | |
| `responses_metadata.rs` | 592 | ⬜ | |
| `prompt_debug.rs` | 114 | ⬜ | |
| `image_preparation.rs` / `original_image_detail.rs` | 430 | ⬜ | |
| `current_time.rs` | 55 | ⬜ | |
| `web_search.rs` | 30 | ⬜ | |

### Phase 7 — 持久化与线程（core 内）

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `thread_manager.rs` + `thread_manager/{managed,shared_instructions}.rs` | 2,804 | ⬜ | `ThreadManager` 门面 |
| `codex_thread.rs` | 1,065 | ⬜ | |
| `codex_delegate.rs` | 382 | ⬜ | |
| `rollout.rs` / `rollout_budget.rs` | 182 | ⬜ | |
| `thread_rollout_truncation.rs` | 305 | ⬜ | |
| `session_prefix.rs` / `thread_startup_metadata.rs` / `session_rollout_init_error.rs` / `state_db_bridge.rs` | 235 | ⬜ | |
| `memory_usage.rs` / `installation_id.rs` / `feedback_config.rs` / `attestation.rs` | 307 | ⬜ | |

### Phase 8 — Guardian / Hooks / Skills（core 内）

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `guardian/mod.rs` | 208 | ⬜ | → `guardian/mod.swift` |
| `guardian/review_session.rs` | 947 | 🟡 | 现有 44 行，全量补全 |
| `guardian/approval_request.rs` | 564 | 🟡 | 现有 52 行 |
| `guardian/prompt.rs` | 365 | 🟡 | 现有 87 行 |
| `guardian/review.rs` | 287 | 🟡 | 现有 35 行 |
| `guardian/review_session_setup.rs` | 265 | 🟡 | 现有 33 行 |
| `guardian/review_request.rs` | 224 | 🟡 | 现有 23 行（routing 半） |
| `guardian/input_budget.rs` | 197 | 🟡 | 现有 25 行 |
| `guardian/decision.rs` | 132 | 🟡 | 现有 58 行 |
| `guardian/reviewer_config.rs` | 109 | 🟡 | 现有 29 行 |
| `guardian/runtime.rs` | 92 | 🟡 | 现有 28 行（仅 ReviewAction） |
| `guardian/request_budget.rs` | 90 | 🟡 | 现有 34 行 |
| `guardian/review_session_context.rs` | 73 | 🟡 | 现有 27 行 |
| `guardian/feedback.rs` | 44 | 🟡 | 现有 32 行 |
| `guardian/coverage.rs` | 33 | 🟡 | 现有 30 行 |
| `guardian_review.rs` | 7 | ⬜ | |
| `hook_runtime.rs` | 1,352 | 🟡 | 现有 170 行，补全事件与脚本 runner |
| `hook_mcp_executor.rs` | 57 | ⬜ | |
| `skills.rs` | 210 | ⬜ | |
| `agents_md.rs` / `agents_md_manager.rs` | 744 | ⬜ | |
| `elicitation.rs` | 100 | ⬜ | |
| `mention_syntax.rs` | 2 | ⬜ | |

### Phase 9 — 多智能体与高级（core 内）

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `agent/`（mod/api/types/status/registry/role/child_config/control + `control/*` 18 文件） | ~5,700 | ⬜ | |
| `agent_communication.rs` / `agent_message_board.rs` | 268 | ⬜ | |
| `plugins/`（6 文件） | 548 | ⬜ | |
| `apps/mod.rs` / `apps/render.rs` | 68 | ⬜ | |
| `connectors.rs` | 555 | ⬜ | |
| `environment_selection.rs` | 2,311 | ⬜ | 多环境选择 |
| `cyber_access_program.rs` | 12 | ⬜ | |
| （另见 Phase 4 表中标 → Phase 9 的 handlers/code_mode 项） | ~6,100 | ⬜ | |

### Phase 10 — 暂缓/收尾（core 内）

| codex 文件 | 行数 | 状态 | 备注 |
|---|---:|---|---|
| `realtime_context.rs` / `realtime_conversation.rs` + `realtime_conversation/*` / `realtime_history.rs` + `realtime_history/*` / `realtime_prompt.rs` | 6,100 | 💤 | 语音 realtime，Sage 无形态 |
| `otel_init.rs` | 111 | ⬜ | 裁剪为最小指标 |
| `lib.rs` | 247 | ⬜ | 最后移植，导出对齐 |
| `test_support.rs` | 264 | ⬜ | 各 phase 按需 |

## 附录 B：依赖 crate 文件清单（范围内）

| crate | 关键文件（行数） | Phase | 处理 |
|---|---|---|---|
| `protocol` | `protocol.rs`(6,444) `models.rs`(4,565) `permissions.rs`(4,488) `openai_models.rs`(1,935) `config_types.rs`(980) `error.rs`(890) `items.rs`(869) `legacy_events.rs`(685) `models/executed_tool_calls.rs`(612) `mcp.rs`(587) `approvals.rs`(548) `permission_profile_intersection.rs`(425) `shell_environment.rs`(322) `turn_input.rs`(252) `auth.rs`(249) `account.rs`(259) `agent_path.rs`(240) 及其余 34 文件 | 1 | 忠实 |
| `utils/*` | `pty`(5,302) `path-uri`(3,094) `stream-parser`(1,485) `absolute-path`(951) `string`(608) `image`(525) `plugins`(446) `path-utils`(427) `audio`(265) `output-truncation`(215) `cache`(193) `home-dir`(134) `git-discovery`(120) | 1/3 | 忠实（pty 在 Phase 3） |
| `async-utils` | `lib.rs`(93) `backoff.rs`(17) | 1 | 忠实 |
| `file-system` | `lib.rs`(712) `environment_accessor.rs`(280) `find_up.rs`(126) `exec_permission_profile_serde.rs`(22) | 2 | 忠实（现有 90 行补全） |
| `apply-patch` | `lib.rs`(1,444) `invocation.rs`(1,036) `streaming_parser.rs`(924) `parser.rs`(682) `file_update.rs`(335) `seek_sequence.rs`(193) `text_file.rs`(121) `standalone_executable.rs`(90) | 2 | 忠实；`standalone_executable`/`main.rs` 适配（进程内调用） |
| `git-utils` | `info.rs`(1,208) `apply.rs`(855) `baseline.rs`(756) `branch.rs`(256) `trust.rs`(183) `worktree.rs`(178) 等 | 2 | 忠实（子集优先：info/baseline/apply/trust） |
| `sandboxing` | `seatbelt.rs`(1,122) `manager.rs`(802) `policy_transforms.rs`(670) `windows.rs`(401) `violation.rs`(300) `bwrap.rs`(195) `spawn.rs`(141) `landlock.rs`(115) `terminal_queries.rs`(104) `lib.rs`(98) `denial.rs`(72) `seatbelt_scratch.rs`(69) `seatbelt_daemon.rs`(24) `windows_mxc.rs`(22) | 3 | seatbelt/manager/transforms/spawn/violation/denial 忠实；`landlock`/`bwrap`/`windows*`/`mxc` ⛔ platform |
| `shell-command` | `parse_command.rs`(2,766) `command_safety/windows_dangerous_commands.rs`(771) `shell_snapshot_literals.rs`(715) `bash.rs`(565) `shell_detect.rs`(495) `command_safety/powershell_tree_sitter.rs`(482) `shell_snapshot_capture.rs`(408) `command_safety/powershell_parser.rs`(373) `shell_snapshot_credentials.rs`(342) `command_safety/is_dangerous_command.rs`(323) `powershell.rs`(291) `shell_snapshot.rs`(112) `shell_snapshot_render.rs`(106) `shell_snapshot_exports.rs`(81) `startup.rs`(30) `lib.rs`(14) | 3 | bash/sh/通用部分忠实；powershell/windows 适配标注 |
| `execpolicy` | `parser.rs`(473) `policy.rs`(412) `amend.rs`(337) `rule.rs`(306) `sandbox_migration.rs`(123) `error.rs`(101) `execpolicycheck.rs`(95) `lib.rs`(33) `executable_name.rs`(29) `decision.rs`(27) | 3 | 风险项 §10.1 |
| `model-provider-info` | `lib.rs`(767) `gateway_oauth.rs`(157) | 6 | 忠实 |
| `codex-api` | `sse/responses.rs`(2,124) 等 SSE/responses 子集 ~4,000；realtime/websocket 部分 | 6/10 | 子集忠实；realtime 💤 |
| `rollout` | `recorder.rs`(2,249) `list.rs`(1,703) `compression.rs`(1,403) `state_db.rs`(744) 等 22 文件 | 7 | JSONL 忠实；SQLite 索引适配 GRDB |
| `state` | `runtime/memories.rs`(5,468) `runtime/threads.rs`(3,637) `runtime/logs.rs`(1,915) `runtime/goals.rs`(1,728) `model/thread_metadata.rs`(894) 等 36 文件 | 7 | 语义对齐，存储适配 GRDB（§10.5） |
| `thread-store` | `local/update_thread_metadata.rs`(2,431) `local/mod.rs`(2,137) `local/read_thread.rs`(1,641) `local/rollout_migration.rs`(1,386) `in_memory.rs`(1,204) `types.rs`(1,127) 等 50 文件 | 7 | 语义对齐，适配 |
| `hooks` | `engine/discovery.rs`(1,741) `schema.rs`(1,254) `events/pre_tool_use.rs`(820) `events/stop.rs`(723) `engine/dispatcher.rs`(656) `events/post_tool_use.rs`(637) 等 28 文件 | 8 | 忠实 |
| `skills` | `mentions.rs`(232) `parser.rs`(225) `lib.rs`(214) `selection.rs`(205) `interface.rs`(201) `invocation.rs`(160) `loading.rs`(119) `model.rs`(112) | 8 | 忠实 |
| `agent-roles` | `loader.rs`(335) `agent_role_config.rs`(209) `discovery.rs`(40) | 8 | 忠实 |
| `context-fragments` | `fragment.rs`(135) `additional_context.rs`(102) `annotated_content.rs`(98) `recap_prompt.rs`(67) `answered_question.rs`(60) | 8 | 忠实 |
| `otel` / `terminal-detection` | — | 10 | 裁剪/适配 |

## 附录 C：与 Sage 现有文档的关系

- `DEVELOPMENT_ROADMAP.md`：产品路线图；本计划是 Execute 层的工程对齐计划，Phase 完成度可回填到路线图的 Execute 条目。
- `Sage/Tools/TOOL_DESIGN.md`：Sage 工具设计标准；当 codex handler 与 Sage 工具规范冲突时，以 harness 对齐为准、Sage 规范约束适配层输出格式。
- `Harness/Package.swift` 头部注释：模块划分理由，随 §4.1 演进同步更新。
- `Harness/PORTING.md`（Phase 0 新建）：逐文件追踪表，本计划附录 A/B 为其初始基线。
