# Skill 自动提炼与经验沉淀 — 设计文档

> 对应 Roadmap 2.3（Skill 系统完善）和 3.1（长期记忆/知识库）中的"经验自动沉淀"能力。

## 背景

Sage 的 Skill 系统已支持按需激活（`SkillMatcher` 本地模型语义匹配 + `load_skill` 工具），但缺少自动识别和提炼生成 skill 的能力。用户在使用过程中积累的踩坑经验、最佳实践、工作流模式等，需要手动创建 SKILL.md 文件才能复用。

本方案实现"经验自动沉淀"——agent 完成任务后自动识别有价值的经验，经用户确认后保存为 skill 文件，供后续任务按需召回。

## 设计决策

### 触发时机

**选择：Task 切换时（`beginNewTask` 关闭旧 task）**

- 此时 task 已有完整的 events 记录
- 用户正在开启新话题，不会打断当前工作流
- 比 `phase = .completed` 更可靠（后者只是 UI 状态，表示"当前回合结束"）

### 识别策略

**选择：Cloud model 判断（方案 A）**

- 直接用 cloud model 分析 task transcript，判断是否包含可复用经验
- 判断质量高，能理解语义上下文
- 备选方案（未采用）：
  - 本地模型初筛：小模型判断不够准确
  - 规则启发式：覆盖面窄，容易漏

### 去重策略

**选择：提交已有 skills 的 name + description 给 cloud model**

- 模型在识别时同时看到已有 skill 目录
- 由模型判断：新增 skill / 增强已有 skill / 不值得保存
- 增强时，模型结合旧内容和新经验生成完整新版 SKILL.md（替换旧版）

### 粒度

**选择：一个 task 合并为一条经验**

- 一个 task 主要专注解决一类问题
- 沉淀的经验应该是内聚的、围绕同一主题

### UI 交互

**选择：底部 inline banner（输入框上方）**

- 不用 toast（打扰过重）
- Apple inline suggestion 风格：轻量、不遮挡、不打断
- 显示 skill 名称 + 描述预览
- "Save" / "×" 两个操作
- 新增提示 "New experience: xxx"，增强提示 "Enhance skill: xxx"
- 30s 无操作自动消失

### 频率控制

**选择：10 秒 debounce + 展示队列聚合**

- 流程：closing task → 立即异步调 model → 结果入展示队列 → 10s debounce → 聚合 UI 提示
- 识别尽早触发（不阻塞），debounce 只控制 UI 展示节奏
- 理论上 task 切换不会频繁发生，10s 足够
- 极端情况（快速连续切换）下聚合展示

## 整体流程

```
beginNewTask() closing 旧 task（events ≥ 4 且 API 已配置）
    │
    ├─ 持久化 task、生成 topic（已有逻辑）
    │
    └─ scheduleSkillExtraction(for: closingTask)
         │
         ▼
    Task.detached(priority: .utility)
         │
         ├─ SkillExtractionService.analyze(task, existingSkills, settings)
         │    ├─ 构建 transcript（cap 6000 字符）
         │    ├─ 构建 prompt（含已有 skills catalog）
         │    └─ Cloud model 调用 → 解析 JSON 响应
         │
         ├─ 结果为 .skip → 结束
         │
         └─ 结果为 .newSkill / .enhance
              │
              ▼
         SkillSuggestionQueue.enqueue(suggestion)
              │
              ├─ 加入 buffer
              └─ 10s debounce timer
                   │
                   ▼
              flush() → pendingSuggestions 更新 → UI banner 显示
                   │
                   ├─ 用户点击 "Save"
                   │    ├─ new → SkillWriter.createSkill()
                   │    └─ enhance → SkillWriter.enhanceSkill()
                   │    └─ CapabilityStore.reloadSkills()
                   │
                   └─ 用户点击 "×" 或 30s 超时 → 丢弃
```

## 文件结构

| 文件 | 职责 |
|------|------|
| `Sage/Capabilities/SkillExtractionService.swift` | Actor，调用 cloud model 分析 task transcript |
| `Sage/Capabilities/SkillSuggestionQueue.swift` | @Observable 队列，debounce + 聚合展示 |
| `Sage/Capabilities/SkillWriter.swift` | 写入/替换 SKILL.md 文件到磁盘 |
| `Sage/Panel/SkillSuggestionBanner.swift` | 底部 inline banner UI |
| `Sage/Agent/AgentRuntime.swift` | 集成触发点（`scheduleSkillExtraction`） |
| `Sage/Panel/AgentWorkspaceView.swift` | 插入 banner 到 composer 上方 |

## Prompt 设计

### 识别 Prompt 要点

- System prompt 定义"经验分析师"角色
- 明确什么值得保存（非显而易见的解决方案、试错后的最佳实践、可复用的工作流）
- 明确什么不值得保存（简单 Q&A、过于特定的场景、广为人知的信息）
- 提供已有 skills 目录供去重参考
- 输出格式：严格 JSON（action: skip/new/enhance）
- 生成的 SKILL.md 遵循标准 frontmatter 格式

### Transcript 构建

- 从 task events 提取关键交互（user input、assistant response、tool calls + results）
- 跳过 system instructions
- 总长度 cap 6000 字符（避免过多 token 消耗）
- 超长时截断早期事件，保留近期

## 约束与边界

- **最少 4 个 events** 才触发识别（过滤掉简单问答）
- **需要 API 配置** 才触发（`settings.isConfigured`）
- **不阻塞主流程** — 全程 `Task.detached(priority: .utility)`
- **失败静默** — model 调用失败或解析失败时返回 nil，不影响用户体验
- **auto-generated 标记** — 自动生成的 skill 在 frontmatter 中标记 `source: auto-generated`
- **写入用户级目录** — `~/Library/Application Support/Sage/Skills/`

## 未来扩展

- 用户显式触发（"记住这个"）— 可复用 SkillExtractionService，跳过"是否值得"判断
- 经验管理 UI — 查看、编辑、删除自动生成的 skills
- 更智能的触发条件 — 检测"错误→重试→成功"模式，提高识别率
- 跨 task 经验聚合 — 多个相关 task 的经验合并为一个 skill
