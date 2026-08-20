# Tool Design Principles

本文档定义 Sage 工具系统的设计标准，确保所有工具对 AI 调用者和用户都表现一致。

## 核心原则

### 1. Description 面向 AI 决策

工具的 `description` 是 AI 选择工具的唯一依据。必须包含：

- **能做什么** — 核心功能一句话说清
- **不能做什么 / 限制** — 明确边界（如"只能删空目录"、"只支持 http/https/mailto"）
- **副作用警告** — 不可逆操作必须标注（如"WARNING: Overwrites existing file"）
- **输出格式** — 如果返回结构化数据，说明格式（如"one entry per line as kind\tsize\tpath"）
- **与相关工具的区分** — 避免 AI 混淆（如 move_file vs rename_file）

**反例**：`"Read a text file"` — 太模糊，AI 不知道大小限制、编码要求、返回格式。

**正例**：`"Read a UTF-8 text file under ~/. Returns raw file content (no line numbers). Full read capped at ~100KB — use line_start/line_end for larger files."`

### 2. 结果格式标准化

| 结果类型 | 格式 | 示例 |
|---------|------|------|
| 操作确认 | `[OK] 动作描述` | `[OK] Moved to /Users/x/file.txt` |
| 数据返回 | 原始数据（无前缀） | 文件内容、剪贴板文本、目录列表 |
| 错误 | `ERROR: 描述` (runtime 层加) | `ERROR: File does not exist: ~/missing.txt` |

规则：
- 操作类工具（写、移动、删除、打开）返回 `[OK]` 前缀 + 操作摘要
- 查询类工具（读文件、读剪贴板、列目录）直接返回数据，不加前缀
- 空结果用明确占位符：`"(clipboard empty)"`、`"(empty directory)"`

### 3. 错误信息必须 Actionable

每个错误都要告诉 AI **下一步该怎么做**：

| ❌ 不好 | ✅ 好 |
|---------|-------|
| `"Path not allowed: /etc/hosts"` | `"Path not allowed: /etc/hosts. Only paths under ~/ are accessible."`（Project 模式下改为 project root） |
| `"File too large"` | `"File too large (150KB). Use line_start/line_end to read a section."` |
| `"Permission denied"` | `"Notification permission denied. Enable in System Settings → Notifications → Sage."` |

### 4. 参数设计

- **命名**：snake_case，语义明确（`line_start` 而非 `start`）
- **可选参数**：提供合理默认值，在 description 中说明默认行为
- **约束**：代码中 clamp 越界值，但在结果中告知 AI 实际使用的值
- **路径参数**：统一支持 `~` 展开和绝对路径

### 5. 安全边界

- **PathGuard**：所有文件操作必须经过 PathGuard 验证。General：仅 `~/`；Focused Project：仅 project root（且仍 ⊆ `~/`）。相对路径在 Project 下相对 root 解析。Runtime 通过 `PathGuard.$policy` TaskLocal 注入策略。
- **大小限制**：读取操作有明确上限（ReadTextFile 100KB, Clipboard 10K chars）
- **全局 cap**：所有工具结果在 runtime 层截断到 50K 字符
- **超时**：所有工具执行有 30s 超时保护
- **Plan 是解题策略**（意图 + 做法），由 plan 子 agent 产出，不是工具步骤
- **act** 策略需确认一次；确认后文件工具可直接跑。`run_shell_command` 与 MCP 工具在本任务第一次出现该精确调用时仍会暂停（允许一次 / 允许本调用 / 允许该工具本任务 / 跳过）。定时任务的无人值守执行跳过这层门
- 工具失败会把 ERROR 结果交给模型并继续本批次其余步骤，而不是整批停住等人 Retry
- 连续的观察类工具可并行；写入 / shell / MCP / todo 仍串行
- 工具轮次默认 8 批，到达上限后询问是否再开 8 批（最多 64）。若模型在上限时仍给出 tool calls，先收进 pendingPlan，Continue 再执行
- `manage_todo_list` 只在 act 计划下暴露，用来跟踪剩余步骤，不重写 work plan
- **answer / observe** 不确认，直接进入执行

### 5.1 PreToolUse Hooks

Project 可在 `<project>/.sage/hooks.json`、Skill 可在其 `SKILL.md` 同目录放置
`hooks.json`。Hook 只声明规则，不执行脚本；所有调用仍经过 Plan、Skill policy、
PathGuard、参数 schema、超时与结果 cap。

```json
{
  "pre_tool_use": [
    {
      "tool": "run_*",
      "action": "ask",
      "reason": "Review shell commands"
    },
    {
      "tool": "run_shell_command",
      "action": "deny",
      "argument_contains": { "command": "sudo " },
      "reason": "sudo is not allowed in this project"
    }
  ]
}
```

- `tool` 支持 `*` 通配符
- `argument_equals` / `argument_contains` 对顶层参数做可选匹配
- 多条命中按 `deny > ask > allow` 合并
- `allow` 只表示 Hook 不拦截，不会绕过 Sage 自带的 shell / MCP 审批
- 配置文件存在但格式错误时 fail closed，并把可修复的错误作为 tool result 返回

### 5.2 Progressive MCP 与 Explore

- MCP 工具总数不超过 20 时直接暴露；超过后，未解锁的 Server 只暴露一个
  `mcp_group__<server>` 入口。解锁状态跟随 Task 持久化，避免切换任务或重启后丢失。
- `explore_subagent` 创建最多 6 个工具轮次的隔离子 Agent，只开放
  `list_directory`、`read_text_file`、`search_files`，并继承 PathGuard 与
  PreToolUse deny/ask 约束；子 Agent 不写主 transcript，只返回最终结论。
- `load_skill` 的 `mode: "fork"` 在上述 Explore 子 Agent 内运行 Skill；
  不把 Skill 激活进父 Agent，避免 Skill 指令和中间读取长期占用主上下文。

### 6. 性能要求

- **不阻塞协作线程**：Process 调用用 `terminationHandler` + continuation，不用 `waitUntilExit()`
- **流式处理大数据**：ReadTextFile 部分读取用 FileHandle 流式扫描，不全量加载
- **输出预算**：ListDirectory 有 500 条 cap，防止递归爆炸

## 新增工具 Checklist

添加新工具时确认：

- [ ] Description 包含：功能、限制、输出格式、副作用
- [ ] 使用 `decodeToolArgs` 统一解码
- [ ] 路径参数经过 `PathGuard.resolveAllowed`
- [ ] 操作结果以 `[OK]` 开头
- [ ] 错误信息包含修复建议
- [ ] 在 `ToolRegistry.makeDefault()` 中注册
- [ ] 在 `humanTitle(for:)` 中添加对应 case
- [ ] 无阻塞同步调用
- [ ] 输出大小有合理上限
