# Sage 开发规划

> Sage 是一个原生 macOS Agent，通过全局热键唤起，帮助用户在 Mac 上完成各种工作。

## 当前状态

**已完成的核心架构：**

- **Agent Runtime**：完整的 agent 循环（submit → think → plan → confirm → execute → summarize）
- **Task 管理**：基于 GRDB 的 task 持久化、task 生命周期、workspace snapshot
- **Task 路由**：本地 MLX 模型（Qwen3-0.6B-4bit）做语义路由，自动判断 continue / resume / new
- **主题生成**：本地模型生成 topic + abstract，支持 resume 时更新
- **HuggingFace 端点解析**：Locale 预判 + HEAD 竞速，自动选择官方 vs 国内镜像
- **MCP 协议**：stdio 方式的 MCP client，支持 tools/list + tools/call
- **Skill 系统**：SkillRegistry 基础框架
- **HUD 窗口**：原生 NSWindow，⌘⇧Space 全局热键唤起
- **Settings**：API Key 配置、模型参数、MCP 服务器管理
- **内置工具**：list_directory、read_file、write_file、get/set_clipboard、send_notification、open_url

**待提交的修复（6 个文件 + 1 个新文件）：**

- `AgentRuntime.swift`：修复 beginNewTask 过期引用、topic 生成重入、updateTaskTopic 竞态
- `LocalModelService.swift`：修复 HubClient init、EOS tokens、LMInput Sendable、warmUp 编译错误、并发加载竞态
- `TaskRouter.swift` / `TopicGenerator.swift`：prompt 从原始 ChatML 重构为 system/user 元组
- `GRDBTaskRepository.swift`：修复 sequence 计算排序
- `TaskContextResolver.swift`：修复中文分词阈值
- `HubEndpointResolver.swift`（新文件）：端点自动选择

---

## Phase 0 — 收尾（立即）

当前修复的收尾工作，确保项目可以正常构建。

### 0.1 提交当前修复并集成 MLX 依赖

- [ ] 将 `HubEndpointResolver.swift` 添加到 Xcode 项目
- [ ] 添加 SPM 依赖：`mlx-swift-lm`、`swift-huggingface`、`swift-transformers`
- [ ] 提交所有修改

### 0.2 修复 Xcode 项目文件

- [ ] 修复 `project.pbxproj` 中损坏的 `isa` key
- [ ] 完整构建验证，确保所有 MLX API 签名编译通过

---

## Phase 1 — 核心体验完善（高优先级）

用户体感提升最大的改动，建议按顺序推进。

### 1.1 流式响应显示

当前 `ModelClient` 返回完整的 `ModelTurn`，用户需要等待整个响应生成完毕才能看到内容。

- [ ] `ModelClient` 改为 SSE 流式请求，返回 `AsyncStream<String>`
- [ ] `AgentRuntime` 支持增量更新 `lastAssistantText`
- [ ] UI transcript 实时追加 token，带打字光标效果
- [ ] 流式过程中支持 stop 中断

### 1.2 Markdown 渲染打磨

`MarkdownContentView` 已有基础，需要补齐细节。

- [x] 流式渲染性能优化（分块缓存 + 节流，`StreamingContentView.swift`）
- [ ] 代码块语法高亮（基于语言标注）— **代码已写好，待加 SPM 依赖**
- [ ] 代码块右上角复制按钮
- [ ] 链接可点击跳转
- [ ] 图片/文件路径渲染（工具结果中的路径可预览）
- [ ] 长文本折叠/展开

#### 代码块语法高亮 — SPM 依赖清单

方案：SwiftTreeSitter（AST 级解析，Xcode 同源技术，原生自适应配色）。

代码文件已就绪：
- `Sage/Highlighting/SageCodeTheme.swift` — Xcode 风格 light/dark 自适应配色
- `Sage/Highlighting/TreeSitterHighlighter.swift` — tree-sitter 引擎 + MarkdownUI `CodeSyntaxHighlighter` 适配
- `Sage/Panel/MarkdownContentView.swift` — 已接入 `.markdownCodeSyntaxHighlighter(TreeSitterCodeHighlighter())`

**需要在 Xcode 中添加的 SPM 依赖（File → Add Package Dependencies）：**

| Package URL | Version | 说明 |
|-------------|---------|------|
| `https://github.com/tree-sitter/swift-tree-sitter` | from `0.9.0` | 核心 Swift 绑定 |
| `https://github.com/alex-pinkus/tree-sitter-swift` | exact `0.7.3-with-generated-files` | Swift 语言解析器（必须用此 tag） |
| `https://github.com/tree-sitter/tree-sitter-python` | from `0.23.0` | Python |
| `https://github.com/tree-sitter/tree-sitter-javascript` | from `0.23.0` | JavaScript |
| `https://github.com/tree-sitter/tree-sitter-typescript` | from `0.23.0` | TypeScript / TSX |
| `https://github.com/tree-sitter/tree-sitter-rust` | from `0.24.0` | Rust |
| `https://github.com/tree-sitter/tree-sitter-go` | from `0.23.0` | Go |
| `https://github.com/tree-sitter/tree-sitter-c` | from `0.24.0` | C |
| `https://github.com/tree-sitter/tree-sitter-cpp` | from `0.23.0` | C++ |
| `https://github.com/tree-sitter/tree-sitter-json` | from `0.24.0` | JSON |
| `https://github.com/tree-sitter/tree-sitter-html` | from `0.23.0` | HTML |
| `https://github.com/tree-sitter/tree-sitter-css` | from `0.23.0` | CSS |
| `https://github.com/tree-sitter/tree-sitter-bash` | from `0.23.0` | Bash/Shell |
| `https://github.com/tree-sitter/tree-sitter-ruby` | from `0.23.0` | Ruby |
| `https://github.com/tree-sitter/tree-sitter-java` | from `0.23.0` | Java |
| `https://github.com/fwcd/tree-sitter-kotlin` | from `0.3.6` | Kotlin |

添加后需要在 target 的 Frameworks 中链接：`SwiftTreeSitter`、`SwiftTreeSitterLayer`，以及所有 `TreeSitter<Lang>` products。

> ⚠️ 如果 `Predicate.TextProvider` 初始化器签名与当前代码不匹配，需要根据实际 API 微调 `TreeSitterHighlighter.swift` 中的 `makeTextProvider` 函数。

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

- [ ] 网络超时指数退避重试（最多 3 次）
- [ ] 模型 API 限流检测（429），显示等待倒计时
- [ ] 部分工具执行失败时的回滚/跳过策略
- [ ] 错误消息附带可操作建议（如 "检查 API Key" 按钮直接跳转 Settings）

### 1.5 MLX 模型内存压力卸载

- [ ] 监听 `DispatchSource.makeMemoryPressureSource()` 的 warning/critical 事件
- [ ] 内存压力时自动调用 `LocalModelService.unload()`
- [ ] 下次推理时自动重新加载
- [ ] Settings 中显示模型状态（未下载 / 已下载 / 已加载 / 内存占用）

---

## Phase 2 — MCP 生态与能力扩展

### 2.1 MCP 服务器生命周期管理

当前 `MCPStdioClient` 是基础实现，缺少生产级的健壮性。

- [ ] 进程崩溃自动重连（带退避）
- [ ] 心跳健康检查
- [ ] 优雅关闭（发送 shutdown 请求后等待退出）
- [ ] stderr 日志捕获和展示
- [ ] 无响应超时处理

### 2.2 MCP 服务器发现与管理

- [ ] Settings 中的 MCP 服务器浏览/安装 UI
- [ ] 支持 `mcp.json` 配置格式
- [ ] 自动检测已安装的 MCP 服务器（如从 Claude Desktop 配置导入）
- [ ] 服务器启用/禁用开关

### 2.3 Skill 系统完善

`SkillRegistry` 已有基础框架，需要补齐功能。

- [ ] Skill 编辑器 UI（prompt 模板 + 参数定义）
- [ ] 参数化 prompt 模板（变量插值）
- [ ] Skill 链式调用
- [ ] 基于上下文的 skill 自动激活
- [ ] 内置常用 skill（翻译、摘要、代码审查、写作润色）

---

## Phase 3 — 上下文与记忆

### 3.1 长期记忆 / 知识库

超越 task 历史的持久化记忆。

- [ ] 用户偏好自动学习（语言、风格、常用路径）
- [ ] 本地向量嵌入存储（SQLite + 嵌入向量）
- [ ] 跨 session 的语义检索
- [ ] 记忆管理 UI（查看、删除、编辑）

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

- [ ] 支持打开多个 agent 窗口
- [ ] 每个窗口独立的 task 上下文
- [ ] 共享 model client 和 tool registry
- [ ] 窗口间 task 拖拽/转移

### 4.3 无障碍支持

`AccessibilityPreferences.swift` 已有基础。

- [ ] 完整 VoiceOver 支持
- [ ] 全键盘导航
- [ ] 减少动效模式
- [ ] 高对比度模式
- [ ] 动态字体缩放

### 4.4 新手引导

- [ ] 首次启动引导流程
- [ ] API Key 设置向导
- [ ] 热键说明与演示
- [ ] 第一个示例任务
- [ ] MCP 服务器推荐

---

## Phase 5 — 高级功能

### 5.1 多模型支持

- [ ] 模型选择器（按 task 类型选择不同模型）
- [ ] 模型 fallback 链（主模型失败时切换备用）
- [ ] 用量/成本追踪
- [ ] 本地模型作为 API 不可用时的降级方案

### 5.2 高级 Agent 规划

当前 plan 是扁平的步骤列表，缺少复杂任务处理能力。

- [ ] 条件分支（if tool result contains X, then...）
- [ ] 循环检测与终止
- [ ] 子任务分解（大任务拆分为多个小 task）
- [ ] 基于工具结果的计划修订
- [ ] 步骤并行执行

### 5.3 自动化 / 定时任务

- [ ] Cron 式定时 agent 运行
- [ ] 事件触发任务（文件变化、剪贴板内容、应用切换）
- [ ] 后台监控 + 通知推送结果
- [ ] 自动化工作流编辑器

---

## 建议推进顺序

```
Phase 0 (收尾)
    │
    ▼
Phase 1.1 (流式响应) ← 用户体感提升最大
    │
    ├─→ Phase 1.2 (Markdown)
    ├─→ Phase 1.3 (工具扩展) ─→ Phase 2 (MCP) ─→ Phase 5.2 (规划)
    ├─→ Phase 1.4 (错误恢复)
    └─→ Phase 1.5 (内存管理)
         │
         ▼
    Phase 3 (上下文) ─→ Phase 4 (UI) ─→ Phase 5 (高级)
```

Phase 1 内部可以并行推进，**流式响应是最高优先级**。
