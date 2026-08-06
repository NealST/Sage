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

- [ ] 代码块语法高亮（基于语言标注）
- [ ] 代码块右上角复制按钮
- [ ] 链接可点击跳转
- [ ] 图片/文件路径渲染（工具结果中的路径可预览）
- [ ] 长文本折叠/展开

### 1.3 内置工具扩展

当前工具集覆盖文件和剪贴板，缺少系统交互能力。

- [ ] `run_shell_command`：沙盒化的 shell 命令执行（超时、输出截断、危险命令拦截）
- [ ] `search_files`：glob 模式文件搜索 + 内容 grep
- [ ] `get_frontmost_app`：获取当前前台应用信息
- [ ] `type_text`：通过 Accessibility API 模拟键入
- [ ] `get_selected_text`：获取当前选中文本
- [ ] `open_app`：按名称打开应用

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
