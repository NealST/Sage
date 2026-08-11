# Skill 自动提炼与经验沉淀 — 设计文档

> 对应 Roadmap 2.3（Skill 系统完善）和 3.1（长期记忆/知识库）中的"经验自动沉淀"能力。  
> 本文档与当前实现同步（识别 → 确认后生成、global/project 作用域、管理 UI）。

## 背景

Sage 的 Skill 系统已支持按需激活（`SkillMatcher` 本地模型语义匹配 + `load_skill` 工具）。经验自动沉淀让 agent 在完成任务后识别可复用经验，经用户确认后再生成并写入 skill 文件，供后续任务召回。

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
- **Project 切换**：清空 pending tips，丢弃切换后才返回的识别结果
- **`save_skill`**：支持 `scope: project \| global`，语义与 banner 一致

### 粒度

**选择：一个 task 合并为一条经验**

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
| `SkillSuggestionQueue.swift` / `SkillSaveJob.swift` | tip 队列 + 后台保存任务 |
| `SkillWriter.swift` | 按 scope 写入；create 标记 `source: auto-generated`；enhance 保留原 source |
| `SkillSuggestionBanner.swift` | tip UI + scope 分段选择 |
| `SkillSaveStatusIndicator.swift` | composer 状态 chip |
| `SkillsManageView.swift` | Everywhere / This Project 分组管理 |
| `AgentRuntime.swift` | 触发、确认、`save_skill`、project 切换作废 |

## Prompt 设计

### 识别

- 值得：非显而易见 workaround、试错最佳实践、可复用工作流、难摸的领域知识
- 不值得：琐碎 Q&A、过窄场景、常识
- Catalog：`name [global|project]: description`（+ body 预览）
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
- Create：`source: auto-generated`；Enhance：保留原 frontmatter `source`（手写 skill 不被改成 auto）
- 工作区内 skill 名唯一（create 撞名 → 应 enhance）

## 未来扩展

- ContextBudget / matcher 限流、skill 过期衰减
- 跨 task 经验聚合

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
- Handler 只依赖 `SlashCommandHost`；`AgentRuntime` 在同文件内实现该协议，保持内部 API 私有
