# Task 路由与主题管理设计

> Sage 的 task 是内部工作单元，不暴露为用户可管理的 "chat"。本文档记录 task 生命周期管理的设计决策与实现方案。

## 核心问题

1. **Task 颗粒度**：如何定义一个 task 的边界？用户在同一个 task 里聊了多个不同主题时怎么办？
2. **Task 召回**：用户在新输入中提到之前 task 相关的内容时，如何自动恢复上下文？
3. **主题抽象**：如何为每个 task 生成高质量的语义标签，供路由和检索使用？

## 设计决策

### Task 颗粒度 = 单主题

每个 task 应该是**单主题**的。当检测到主题漂移时，自动关闭当前 task 并开新 task，而不是让多个主题堆积在一个 task 下。

好处：
- 每个 task 的 topic/abstract 天然准确，不需要综合多个主题
- 路由匹配更精确
- 上下文窗口不会被无关历史污染

### 路由方式 = continuity + 启发式

不再运行本地 MLX。顺序是：

1. `ContinuityTaskResolver`：显式「新任务 / start fresh」或没有 active task → `beginNew`
2. `HeuristicTaskFallback`：词面重叠（含中文 bigram）决定 resume / 主题漂移开新 task
3. 否则 continue 当前 task

语义分类交给云端对话，不在本地再跑一轮小模型。

### 主题摘要 = topic + abstract

每个 task 维护两个语义字段：
- **topic**：极短标签（≤20 字符），如 "整理 Downloads"、"PDF 合并脚本"
- **abstract**：一句话意图描述（≤80 字符），如 "把 Downloads 里的文件按类型分类到子文件夹"

这两个字段由 `TopicGenerator` 从首条（或 resume 时的新）用户消息截取，不调用模型。

## 整体流程

```
新 userInput 进来
    │
    ▼
ContinuityTaskResolver（处理显式关键词："start fresh"、"新任务" 等）
    │
    ├─ 匹配到关键词 → 直接开新 task
    │
    └─ 未匹配 → HeuristicTaskFallback
            │
            ├─ 空 active + 命中旧 task → resume
            ├─ 与当前 topic 几乎无重叠 → beginNew
            └─ 否则 continue
```

## Task 目录

启发式 resume 会扫 `workspace.recentSummaries` 的 topic / abstract / summary，不再构造给本地模型的 catalog prompt。

### 目录构建规则

- 从 `recentSummaries` 构建，排除当前 active task
- 只包含有 topic 的 task（没有 topic 的旧 task 不参与路由）
- 排除 `awaitingApproval` 状态的 task
- 最多 15 条，按 `updatedAt` 降序

## Topic 生成策略

### 生成时机

| 时机 | 触发条件 | 目的 |
|------|----------|------|
| Task 首次完成 | `phase → .completed` 且 `topic == nil` | 建立初始主题 |
| Task 被召回 | 旧 task 被 resume 且有新输入 | 更新主题以反映扩展的范围 |

### 生成 Prompt

**首次生成**（输入：首条 userInput + 末条 userInput + 末条 assistantResponse）：

```
Given this task's conversation history, produce a concise topic label and abstract.
- topic: max 20 characters, in the user's language
- abstract: one sentence, max 80 characters, in the user's language

Output ONLY: {"topic":"...","abstract":"..."}
```

**更新**（输入：现有 topic/abstract + 新输入）：

```
A task is being resumed with new content. Update the topic and abstract.
Keep the original intent but incorporate the new direction.

Output ONLY: {"topic":"...","abstract":"..."}
```

### 为什么用"首尾 events"而不是完整历史

- **first userInput** — 代表用户最初的意图
- **last userInput** — 如果和 first 不同，说明有追问或主题演进
- **last assistantResponse**（纯文本）— 代表最终结果

因为每个 task 是单主题的（主题漂移时会自动拆分），首条用户消息通常足够当标签。

## 技术实现

### 关键文件

| 文件 | 职责 |
|------|------|
| `Sage/Task/TopicGenerator.swift` | 从用户文本截取 topic / abstract |
| `Sage/Task/TaskContextResolver.swift` | 显式关键词 + 词面启发式 |
| `Sage/Task/TaskRoute.swift` | `CompositeTaskRouter`（continuity → heuristic） |

### 数据模型变更

`TaskRecord` 新增字段：
```swift
var topic: String?          // 短标签，≤20 字符
var abstract: String?       // 一句话描述，≤80 字符
var topicUpdatedAt: Date?   // 追踪是否需要刷新
```

DB migration：
```sql
ALTER TABLE tasks ADD COLUMN topic TEXT;
ALTER TABLE tasks ADD COLUMN abstract TEXT;
ALTER TABLE tasks ADD COLUMN topic_updated_at REAL;
```

### 容错设计

- 启发式不够自信时 **continue** 当前 task，不阻塞用户
- Topic 生成是异步后台任务，不阻塞主流程

## 启发式限制

`HeuristicTaskFallback` 使用 bag-of-words 重叠率：

```swift
let overlap = inputTokens.intersection(summaryTokens).count
let score = Double(overlap) / Double(inputTokens.count)
guard score >= 0.5, overlap >= 2
```

问题：
1. 纯词汇匹配，不是语义相关性
2. 中文词多为 2 字符，被 `count >= 3` 过滤，中文场景基本不生效
3. 无法检测主题漂移（只能匹配旧 task，不能判断"当前输入是否偏离当前 task"）
4. `summary` 是第一条消息的前 160 字符截断，质量差

## 未来方向

- **动态 context budget**：根据 `settings.model` 的上下文窗口大小调整 `ContextBudget` 限制
- **Task 历史搜索**：提供轻量入口让用户搜索/浏览过去的 task（类似 Spotlight）
- **Embedding 索引**：当 task 数量增长到 100+ 时，词面启发式可能不够，可以用 embedding 做预筛选
