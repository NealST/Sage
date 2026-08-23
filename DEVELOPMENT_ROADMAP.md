# Sage 开发规划

> Sage 是一个原生 macOS Agent，通过全局热键唤起，帮助用户在 Mac 上完成各种工作。

## 当前状态

代码已经超过这份文档最初写下时的范围。下面按「已落地 / 仍未做」对齐仓库，避免把已完成工作当成待办。

**已落地：**

- **Agent Runtime**：Plan → Execute（ReAct）→ Review；`act` 策略确认一次；observe/answer 不能走副作用工具
- **Task**：GRDB 持久化、窗口线程、workspace snapshot；默认粘住当前线程，显式「新任务」才开新 task；主题漂移是 Plan 给出的非阻塞提示；chrome Recents 菜单显式切线程
- **Transcript**：点回复时放开输入框焦点；窗口变 key 不抢焦点，便于选中复制
- **主题**：从首条用户消息确定性截取 topic + abstract（无本地模型）
- **流式**：SSE + transcript 增量渲染 + Stop
- **多窗口**：General / Project 各一扇独立 session；共享 settings / MCP hub / skill 状态
- **Schedules**：间隔 / 日历式定时；agent 与 script；从完成时刻算下次间隔；退出时 disarm
- **MCP**：stdio client、重连/心跳、Settings 启用开关、full-trust 文案（无 PathGuard）
- **Skills**：目录附录 + `load_skill` 渐进披露；`allowed-tools` 需显式声明 `run_skill_script` / `save_skill`；不是 embedding 语义匹配器
- **Settings**：API Key（Keychain fail-closed）、分角色模型、MCP / Skills / Login Item
- **工具**：文件、shell（cwd 沙盒、命令字符串可 `cd`）、剪贴板、AX、截图、提醒等

**明确未做（不要从上面推断已经有）：**

- `mcp.json` / Claude Desktop 导入
- tiktoken 级 token 计数
- 项目级 `.sage` 配置
- 完整 VoiceOver / 键盘导航验收
- 事件触发（文件变化、剪贴板、应用切换）
- 窗口间拖拽 task

---

## Phase 0 — 收尾（立即）

### 0.1 提交当前修复

- [x] 已移除本地 MLX / HuggingFace 下载链路，推理统一走云端
- [ ] 提交所有修改

### 0.2 修复 Xcode 项目文件

- [x] 修复 `project.pbxproj` 中损坏的 `isa` key（当前工程文件干净）
- [x] 完整构建验证

---

## Phase 1 — 核心体验完善（高优先级）

用户体感提升最大的改动，建议按顺序推进。

### 1.1 流式响应显示

当前 `ModelClient` 返回完整的 `ModelTurn`，用户需要等待整个响应生成完毕才能看到内容。

- [x] `ModelClient` 改为 SSE 流式请求，返回 `AsyncThrowingStream<StreamDelta, Error>`
- [x] `AgentRuntime` 支持增量更新 `streamingText`
- [x] UI transcript 实时追加 token，带呼吸光标效果（`StreamingContentView.swift`）
- [x] 流式过程中支持 stop 中断

### 1.2 Markdown 渲染打磨

`MarkdownContentView` 已有基础，需要补齐细节。

- [x] 流式渲染性能优化（分块缓存 + 节流，`StreamingContentView.swift`）
- [x] 代码块语法高亮（基于语言标注）— TreeSitter SPM 已接入，构建通过
- [x] 代码块右上角复制按钮（`MarkdownContentView.swift` Copy/Copied 动画反馈）
- [x] 链接可点击跳转（`PathTextSupport.swift` — 本地路径 Finder reveal / Quick Look，http/mailto 系统打开）
- [x] 图片/文件路径渲染（`QuickLookPresenter.swift` — 图片/PDF Quick Look 预览）
- [x] 长文本折叠/展开（助手回复高度折叠 + 代码块行数折叠 + 工具结果/调用可展开 chip）

#### 代码块语法高亮 — SPM 依赖说明

方案：SwiftTreeSitter（AST 级解析，Xcode 同源技术，原生自适应配色）。

- `Sage/Highlighting/SageCodeTheme.swift` — Xcode 风格 light/dark 自适应配色
- `Sage/Highlighting/TreeSitterHighlighter.swift` — tree-sitter 引擎 + MarkdownUI `CodeSyntaxHighlighter` 适配
- `Sage/Panel/MarkdownContentView.swift` — 已接入 `.markdownCodeSyntaxHighlighter(TreeSitterCodeHighlighter())`

Python / JavaScript / CSS 语法器用本地包（`ThirdParty/tree-sitter-*`）：上游 `Package.swift` 用 `FileManager` 探测 `scanner.c`，在 Xcode SPM 下会漏编导致链接失败。

### 1.3 内置工具扩展

当前工具集（17 个）覆盖文件操作、Shell 执行、剪贴板、辅助功能和系统交互。下一步按优先级扩展：

#### Tier 1 — 高价值 / 高频 ✅ 已完成

| 工具 | 说明 | 状态 |
|------|------|------|
| `run_shell_command` | 沙盒化 shell 执行。异步 Process + terminationHandler，输出截断（stdout+stderr 合并，cap 50KB），可配置超时（默认 30s，最大 120s）。危险命令黑名单（rm -rf /、sudo 等）。工作目录限制在 ~/ 下。 | ✅ |
| `search_files` | 文件搜索：支持 glob 模式匹配文件名 + 可选的内容 grep（正则）。递归搜索，结果 cap 50 条。返回格式：每行一个匹配（路径 + 可选匹配行）。 | ✅ |
| `get_selected_text` | 通过 Accessibility API (AXUIElement) 获取当前前台应用的选中文本。需要辅助功能权限。返回选中文本或 "(no selection)"。 | ✅ |

#### Tier 2 — 场景补全 ✅ 已完成

| 工具 | 说明 | 状态 |
|------|------|------|
| `get_frontmost_app` | 获取当前前台应用信息：app name、bundle ID、窗口标题。通过 NSWorkspace + Accessibility API。 | ✅ |
| `type_text` | 通过 Accessibility API 将文本插入当前焦点位置（替换选中或插入光标处）。配合 get_selected_text 实现"选中→处理→替换"闭环。防止写入 Sage 自身窗口。双策略：优先 kAXSelectedTextAttribute，回退 kAXValueAttribute（仅限简单输入框）。 | ✅ |
| `get_screen_info` | 获取屏幕信息：分辨率、缩放比例、Retina 倍率、活跃显示器数量、当前窗口位置/尺寸。 | ✅ |

#### Tier 3 — 锦上添花 ✅ 已完成

| 工具 | 说明 | 状态 |
|------|------|------|
| `get_system_volume` / `set_system_volume` | CoreAudio 系统音量读取/设置（0–100）+ 静音控制 | ✅ |
| `toggle_appearance` | 切换 Light/Dark 模式，支持指定模式或 toggle。通过 AppleScript 控制 System Events。 | ✅ |
| `create_reminder` | 通过 EventKit 创建提醒事项，支持 due date（ISO 8601）、优先级、备注 | ✅ |
| `take_screenshot` | 截取屏幕/窗口截图，保存为 PNG。优先使用 CGWindowList API，回退 screencapture CLI。 | ✅ |

#### 实现原则

所有新工具必须遵循 `Sage/Tools/TOOL_DESIGN.md` 中的设计标准：
- Description 面向 AI 决策（含功能、限制、输出格式、副作用）
- 操作类结果 `[OK]` 前缀，查询类裸数据
- 错误信息 actionable（告知 AI 下一步怎么做）
- 使用 `decodeToolArgs` + `PathGuard`（文件类）
- 无阻塞同步调用，输出有大小上限
- 注册到 `ToolRegistry.makeDefault()` + `humanTitle(for:)`

### 1.4 错误恢复 UX

- [x] 网络超时指数退避重试（最多 3 次）— `RetryPolicy` 指数退避，网络错误/5xx/408 自动重试
- [x] 模型 API 限流检测（429），显示等待倒计时 — 解析 `Retry-After` header，`RetryCountdownView` 环形进度 + 秒数倒计时
- [x] 部分工具执行失败时的回滚/跳过策略（失败步骤标记 `.failed`，后续步骤 `.skipped`，支持 resume 重试）
- [x] 错误消息附带可操作建议 — 401→检查 API Key，403→权限不足，404→检查 URL，429→限流，5xx→服务端问题；UI 已有 Open Settings 按钮

### 1.5 本地模型（已移除）

- [x] 不再运行 on-device MLX；skill 召回与任务路由不再依赖本地推理
- [x] Dashboard 只保留 session tokens 与 MCP 状态

---

## Phase 2 — MCP 生态与能力扩展

### 2.1 MCP 服务器生命周期管理

当前 `MCPStdioClient` 是基础实现，缺少生产级的健壮性。

- [x] 进程崩溃自动重连（带退避）— `handleServerProcessExit` + `scheduleReconnect`，指数退避 1s→2s→4s，最多 3 次
- [x] 心跳健康检查 — 每 30s ping，5s 超时，失败触发重连
- [x] 优雅关闭（发送 shutdown JSON-RPC 后等待 3s 退出）— `MCPStdioClient.disconnect()` async
- [x] stderr 日志捕获和展示 — 50 行环形缓冲，Dashboard MCP 面板可展开查看
- [x] 无响应超时处理（`CapabilityStore` 20s 连接超时，`TaskGroup` 竞速）
- [x] Dashboard MCP 服务器状态面板 — 状态点 + 日志展开 + 手动重试

### 2.2 MCP 服务器发现与管理

- [ ] Settings 中的 MCP 服务器浏览/安装 UI（商店式发现；现有列表 + 启用开关不算）
- [ ] 支持 `mcp.json` 配置格式导入
- [ ] 自动检测已安装的 MCP 服务器（如从 Claude Desktop 配置导入）
- [x] 服务器启用/禁用开关

### 2.3 Skill 系统完善

长期记忆（踩坑经历、最佳实践）通过 Skill 文件实现，按需注入。当前按需路径是 **catalog 附录 + `load_skill`**，不是 embedding / 语义匹配器。

- [x] **Skill 按需加载（渐进披露）**— 系统提示只带 catalog；正文经 `load_skill` / 用户选择注入。不是按输入 embedding 自动激活
- [x] 踩坑/最佳实践沉淀 — 任务结束后可生成 skill 建议并写入 `.md`
- [ ] Skill 编辑器 UI（prompt 模板 + 参数定义）
- [ ] 参数化 prompt 模板（变量插值）
- [ ] Skill 链式调用
- [ ] 内置常用 skill（翻译、摘要、代码审查、写作润色）

### 3.1 长期记忆 / 知识库

> **设计决策**：长期记忆复用 Skill 系统。不引入独立的向量存储层。

- [x] Skill 按需加载（见 2.3；不是向量召回）
- [x] 经验沉淀触发（任务结束建议 + 用户确认保存）
- [x] 跨项目 skill 共享（`~/Library/Application Support/Sage/Skills/`）
- [ ] 记忆/skill 管理 UI（查看、删除、编辑）

### 3.2 上下文窗口优化

`ContextBudget` 已有基础，需要更智能的策略。

- [ ] 旧事件智能摘要（保留关键信息，压缩冗余）
- [ ] 基于优先级的上下文包含策略
- [ ] 准确的 token 计数（tiktoken 或模型 tokenizer）
- [ ] 多 task 上下文混合（相关 task 的摘要注入）

### 3.3 工作区 / 文件感知

- [ ] 监听用户活跃项目目录的文件变化
- [ ] 自动提供文件树上下文
- [ ] 检测用户当前工作类型（代码 / 文档 / 系统管理）
- [ ] 项目级 `.sage` 配置文件支持

---

## Phase 4 — UI/UX 打磨

### 4.1 流畅动画与过渡

- [ ] Thinking 状态动画指示器
- [ ] 消息出现/消失过渡动画
- [ ] Plan 卡片展开/折叠动画
- [ ] 平滑滚动到底部
- [ ] 打字指示器

### 4.2 多窗口支持

- [x] 支持打开多个 agent 窗口（General + 每个 Project）
- [x] 每个窗口独立的 task 上下文
- [x] 共享 model settings、tool registry、MCP hub
- [ ] 窗口间 task 拖拽/转移

### 4.3 无障碍支持

`AccessibilitySettings.swift` 已有 Reduce Motion / Increase Contrast / Dynamic Type 观察。

- [ ] 完整 VoiceOver 支持
- [ ] 全键盘导航
- [x] 减少动效模式
- [x] 高对比度模式（部分控件）
- [x] 动态字体缩放（`sageScaledTypography`）

### 4.4 新手引导

- [ ] 首次启动引导流程
- [ ] API Key 设置向导
- [ ] 热键说明与演示
- [ ] 第一个示例任务
- [ ] MCP 服务器推荐

---

## Phase 5 — 高级功能

### 5.1 多模型支持

- [x] 分角色模型（Plan / Execute / Review，空则回退 `model`）
- [ ] 模型 fallback 链（主模型失败时切换备用）
- [ ] 用量/成本追踪
- [x] 云端 API 不可用时的明确错误（不再回落到本地模型）

### 5.2 高级 Agent 规划

当前 work plan 是策略卡片，工具批是扁平步骤列表。

- [ ] 条件分支（if tool result contains X, then...）
- [ ] 循环检测与终止
- [ ] 子任务分解（大任务拆分为多个小 task）
- [ ] 基于工具结果的计划修订
- [ ] 步骤并行执行

### 5.3 自动化 / 定时任务

- [x] 间隔 / 日历式定时 agent 与 script（`ScheduleService`；间隔从完成时刻起算）
- [ ] 事件触发任务（文件变化、剪贴板内容、应用切换）
- [x] 运行结束通知（成功/失败）
- [ ] 可视化工作流编辑器（当前是自然语言草稿 + 表单）

---

## 建议推进顺序

未做项优先：长线程 context 压缩、无障碍补齐、首次启动向导。`mcp.json`、token 计数、`.sage`、事件触发可以后做。流式、Schedules、多窗口、Recents 已经在主路径上。
