# Sage

macOS 端 AI 编码代理。核心 agent runtime 从 codex-rs 移植为 Swift（`Sage/Agent/Execute/Harness/`，
见 `Docs/EXECUTE_HARNESS_PORT_PLAN.md` 与 `Harness/PORTING.md` 的移植状态表），外围是自有的
任务路由、计划/评审、技能、定时调度与 SwiftUI 桌面 UI。

## 构建与测试

```sh
xcodebuild -project Sage.xcodeproj -scheme Sage -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Sage.xcodeproj -scheme Sage -configuration Debug -destination 'platform=macOS' test
```

无 Xcode license 环境可用 `scripts/harness_test.sh` 只跑 Harness 模块测试（见 `scripts/README.md`）。

## 目录结构

| 目录 | 职责 |
|---|---|
| `Sage/App/` | 应用壳：AppDelegate、AppState、窗口管理、启动引导与草稿持久化 |
| `Sage/Agent/` | Agent runtime 主体：AgentRuntime、AgentTaskStore、TurnCoordinator（Orchestration/）、Plan / Review 子代理、Streaming（上下文压缩、流式泵） |
| `Sage/Agent/Execute/` | Execute 胶水层：TaskHarness（每任务持久 Session）、PhaseTurnRunner、ExecuteTask；**Harness/ 子目录是 codex-rs 忠实移植，结构不改动** |
| `Sage/Capabilities/` | 能力扩展：CapabilityStore、Skills/（技能加载与策略）、MCP/（stdio 客户端） |
| `Sage/Tools/` | 内置工具实现与执行沙箱（seatbelt）、ToolDefinition 协议 |
| `Sage/Task/` | 任务数据层：TaskRecord / GRDB 仓储、ContextBudget、ConversationFold、Topics/ |
| `Sage/Panel/` | 主面板 UI：Composer/、Transcript/、ToolCalls/、Skills/、Workspace/、Markdown/ |
| `Sage/Schedule/` | 定时任务：ScheduleRunner、JobQueue、Record |
| `Sage/Commands/` `Sage/Dashboard/` `Sage/MenuBar/` `Sage/HUD/` `Sage/Hotkey/` | 其余 UI 表面 |
| `Sage/Settings/` | 设置界面与存储 |
| `Sage/Util/` | 基础工具（路径、diff、git 读取、ProjectAgentsMarkdown 解析） |
| `SageTests/` | 测试；子目录镜像 `Sage/` 分区（AgentTests/、ToolsTests/…），ExecuteHarness/ 为上游移植测试 |
| `Docs/` | 设计文档：项目系统设计、agent runtime 集成计划、移植计划、调度与任务路由设计 |
| `scripts/` | 移植追踪 lint、离线测试脚本（见 `scripts/README.md`） |
| `ThirdParty/` | vendored 上游依赖（swift-markdown-engine 等） |

## 分层规则

- `Agent/`（逻辑）不 import `Panel/`（UI）；UI 只经 Agent 层意图方法写状态。
- `Agent/Execute/Harness/` 是 codex-rs 忠实移植，改动需同步 `Harness/PORTING.md`；
  Sage 自有胶水（TaskHarness、PhaseTurnRunner、ExecuteTask）放在其外层。
- 纯 Foundation 逻辑（如 ToolCallPresentation）归 Agent 层，UI 只做渲染。

## 关键文档

- `Docs/PROJECT_SYSTEM_DESIGN.md` — 项目整体系统设计
- `Docs/AGENT_RUNTIME_INTEGRATION_PLAN.md` — agent runtime 集成里程碑（M0–M5）
- `Docs/EXECUTE_HARNESS_PORT_PLAN.md` — codex-rs → Swift 移植计划
- `Docs/DEVELOPMENT_ROADMAP.md` — 开发路线图
- `Docs/SCHEDULES_DESIGN.md`、`Docs/TASK_ROUTING_DESIGN.md`、`Docs/TOOL_DESIGN.md` — 专题设计
