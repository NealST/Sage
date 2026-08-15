# Task 路由与主题管理设计

> Sage 的 task 是窗口里的**当前线程**，不是用户可管理的 chat 列表。  
> 默认粘住当前线程；新开只来自用户确认。

## 核心问题

1. **线程边界**：什么时候结束当前 task、开一条新的？
2. **召回**：用户想接上旧工作怎么办？（本轮不做 Recent 点选，保留 `activateTask`）
3. **标题**：topic / abstract 只做展示，不驱动自动拆分。

## 设计决策

### 默认 = continue 当前 task

新输入写入当前 `TaskRecord` 并立刻开跑。不因词面不像就静默 `beginNew` 或 resume 旧 task。

Topic 是标题（首条用户消息截取），允许和后来的内容不完全对齐。标题过时不是换线程的理由。

### 新开 = 用户确认

只在这些情况下创建新 task，入口都叫 **Start Fresh**（同一语义：新开一条当前正在做的事）：

| 入口 | 行为 |
|------|------|
| Chrome / 菜单 **Start Fresh** | 无漂移提示：关闭整条当前线程，开空白新 task。有提示：把刚发出的那一轮带到新 task |
| 输入含「新任务 / start fresh」等 | 先拆再写入本条（本条成为新线程首条） |
| 主题漂移提示条 **Start Fresh** | 同上，有提示时带走最后一轮 |
| 提示条关闭（x） | 继续当前线程，本线程不再提示 |

自动 resume / 自动拆 task 已从提交路径移除。

### 主题漂移提示 = 邀请，不是闸门

`TopicDriftDetector` 只决定要不要出条，**不**返回 `TaskRoute`。

消息照常进当前 task。Chrome 下方出一条非阻塞提示（与系统 inline banner 同密度，无警告色、无弹窗）：

> This doesn’t look like “整理 Downloads”.

- **Start Fresh**：新开一条。若提示条认为刚那句不像当前标题，只带走**最后一条用户输入**（意图分叉），旧线程停在分叉前；那一轮里混上下文的回复/计划丢掉，在新线程重跑。否则归档整条、开空白。
- **Keep going**（x）：关掉提示，记下 `suppressedDriftOfferTaskID`，本线程不再问。

检测必须保守（宁可不问）：

- 已有 topic/abstract/summary 锚点
- 当前 task `events.count >= 4`
- 输入 ≥ 16 字符且有效 token ≥ 4
- 与锚点 **零重叠**
- 本线程未被抑制，且本条不是显式「新任务」

## 整体流程

```
新 userInput
    │
    ▼
ContinuityTaskResolver
    ├─ 「start fresh」/「新任务」等 → beginNew（写入本条之前）
    ├─ 无 active task → beginNew
    └─ 否则 continue
            │
            ▼
commit 用户事件并开跑
            │
            ▼
若 continue 且检测器认为漂移 → 出 TopicDriftOffer
```

## Topic 生成

仍由 `TopicGenerator` 从首条用户消息截取，不调用模型。

- Continue 不改标题
- 剥离后：旧 task 保持原标题；新 task 用挪过去的那条用户消息生成

## 技术实现

| 文件 | 职责 |
|------|------|
| `Sage/Task/TaskRoute.swift` | `CompositeTaskRouter`（仅 continuity） |
| `Sage/Task/TaskContextResolver.swift` | 显式新鲜开始用语 |
| `Sage/Task/TopicDrift.swift` | `TopicDriftDetector` + `TopicDriftOffer` |
| `Sage/Agent/AgentTaskStore.swift` | `splitOffTurn`：原子剥离最后一轮 |
| `Sage/Panel/TranscriptNoticeBar.swift` | 漂移提示 + 既有 context hint |
| `Sage/Panel/WorkspaceChromeView.swift` | 当前线程标题（有其它 recents 时变成弹出菜单）+ Start Fresh |

- 剥离 / Start Fresh 后新 task **不**继承旧线程的 `relatedTaskIDs` 或已激活 skill，避免「新开」后模型仍吃到上一件工作
- 点选 Recents 是显式切线程：`activateTask`，不写 context hint（不是静默 resume）

## Recents

对照 Apple **Open Recent / 当前选择弹出**（Xcode scheme、titlebar 分支菜单），不是会话管理器：

- 有其它带标题的 task 时，当前标题变成 borderless 菜单；当前项打勾
- 当前还没标题（刚 Start Fresh）时，菜单标签为 **New Task**
- 最多 10 条，按 `updatedAt`，跟当前窗口同一 scope（Project / General）
- 无其它 recents 时保持静态标题，不单独加时钟按钮（避免和 General 的 Recent Projects 抢语义）

## 明确不做

- 云端/模型分类每轮路由
- 发送前 Continue / New 弹窗
- 为了对齐标题自动改 topic

## 未来方向

- **动态 context budget**：按模型窗口压缩旧轮次（脏上下文靠截断，不靠拆 task）
