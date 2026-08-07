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
| `"Path not allowed: /etc/hosts"` | `"Path not allowed: /etc/hosts. Only paths under ~/ are accessible."` |
| `"File too large"` | `"File too large (150KB). Use line_start/line_end to read a section."` |
| `"Permission denied"` | `"Notification permission denied. Enable in System Settings → Notifications → Sage."` |

### 4. 参数设计

- **命名**：snake_case，语义明确（`line_start` 而非 `start`）
- **可选参数**：提供合理默认值，在 description 中说明默认行为
- **约束**：代码中 clamp 越界值，但在结果中告知 AI 实际使用的值
- **路径参数**：统一支持 `~` 展开和绝对路径

### 5. 安全边界

- **PathGuard**：所有文件操作必须经过 PathGuard 验证，只允许 ~/ 下的路径
- **大小限制**：读取操作有明确上限（ReadTextFile 100KB, Clipboard 10K chars）
- **全局 cap**：所有工具结果在 runtime 层截断到 50K 字符
- **超时**：所有工具执行有 30s 超时保护
- **不可逆操作**：description 中标注，依赖 approval 流程保护

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
