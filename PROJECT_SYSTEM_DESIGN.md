# Project 系统：产品设计与技术实现

> Sage 用 **Project** 作为代码工作的隔离边界；**Task** 仍是内部工作单元。  
> 多 project 并行；task 强制隶属 project（或 General）；路由 / 上下文 / 工具默认不跨界。  
>  
> 进度：完成一项将 `- [ ]` 改为 `- [x]`。细节实现以本文为准；若与 `DEVELOPMENT_ROADMAP.md` 冲突，以本文的 Project 范围为先。

## 状态总览

| Phase | 主题 | 状态 |
|-------|------|------|
| A | 数据模型 + Focus + Open/Create/Switch + 路由隔离 + PathGuard（理想策略）+ UI | **进行中（骨架已落地，待手工验收）** |
| B | 代码体验加深（默认 search/list、空项目引导、与 write-diff 联调） | 未开始 |
| C | `.sage` / 文件感知 / 多窗口 focus / 记忆分层 | 未开始 |

---

## 1. 产品模型

```text
Sage
├── General（project_id = NULL）
│   └── Tasks…
└── Projects[]（可并行存在）
    ├── Project A (root)
    │   └── Tasks…   # 只属于 A
    └── Project B (root)
        └── Tasks…
```

| 概念 | 含义 | 硬规则 |
|------|------|--------|
| **Project** | 绑定本地目录根的代码工程 | 有 `root_path`；可多开；**每个 Project 一个 window** |
| **General** | 无工程的默认 Sage | `project_id = NULL`；**独立 General window** |
| **Task** | 内部工作单元（不暴露为聊天列表） | **创建时写入归属**；不自动漂移；不可静默换 project |
| **串台防护** | — | 路由 / related / catalog **仅同 `project_id`**；tips 跟 window/session，不跟「全局 focus 切换」 |

### 1.1 用户动作

- **Open Project**：选目录 → 校验 → 注册或复用 Project → **打开/聚焦该 Project window**（恢复 `last_active_task` 或新建）
- **Create Project**：父目录 + 名称 → 建文件夹（可选 `git init`）→ 等同 Open
- **Switch Project**：打开/聚焦目标 Project window（不销毁当前窗；各窗独立 transcript / tips）
- **Close Project Window**：关闭该 Project window 并释放 session（tips 随窗作废）；General window 仅隐藏
- **Start Fresh**：仅在**当前 window** 内开新 task

### 1.2 并行含义

- 多个 project 可同时存在于库中；**多窗口各持一个 `AgentSession`（一窗一 focus）**
- 面板 transcript **只展示该窗 session** 的 active task
- Skill tips 绑定 session：**窗不关则 tip 不作废**；关窗 / Start Fresh（放弃 skill choice）才清理
- 共享：`projects` 表、Task DB、MCP hub、ModelSettings；skills catalog 按窗 reload

### 1.3 行为差异

| | General | Focused Project |
|--|---------|-----------------|
| 默认 cwd | `~` | `project.root` |
| PathGuard | 家目录沙箱（现状） | **项目根沙箱（见 §5）** |
| 系统提示 | 通用 | + root、优先在项目内修改 |
| Task 路由 | 仅 `project_id IS NULL` | 仅该 `project_id` |
| UI | Sage / General | 工程名或短路径徽章 |

---

## 2. 命名

| 用 | 不用（避免碰撞） |
|----|------------------|
| Product / 类型：`Project` / `ProjectRecord` / `SageProject` | 新实体叫 Workspace |
| UI 文案：Project | 与 `TaskWorkspaceSnapshot`、`AgentWorkspaceView` 混称同一概念 |

现有 `*Workspace*` 保留为「面板 / 快照」含义，不承载 Project 实体。

---

## 3. 数据模型

### 3.1 表 `projects`

| 列 | 说明 |
|----|------|
| `id` | UUID PK |
| `name` | 展示名（默认可为目录名） |
| `root_path` | 标准化绝对路径，**UNIQUE** |
| `created_at` / `updated_at` / `last_opened_at` | 时间戳 |
| `last_active_task_id` | NULLABLE FK → `tasks(id)` |
| 可选 | `is_pinned`, `git_present`（缓存） |

### 3.2 `tasks` 变更

- `project_id TEXT NULL REFERENCES projects(id)`  
  - `NULL` = General  
  - 非空 = 隶属该 project  
- 索引：`(project_id, updated_at DESC)`

### 3.3 `app_state` 变更

- `focused_project_id TEXT NULL`（NULL = General）
- 保留 `active_task_id`
- **不变量**：`active_task.project_id` 与 `focused_project_id` 同为 NULL，或相等

### 3.4 迁移

- Migrator 新版本（如 `addProjects`）：建 `projects`、`tasks.project_id`、`app_state.focused_project_id`
- 既有 tasks 全部为 General（`project_id = NULL`）
- 同一 `root_path` 再次 Open → 复用同一行，更新 `last_opened_at`

### 3.5 类型 / API（示意）

- `ProjectRecord`（或 `SageProject`）
- Repository：`openProject`, `createProject`, `listProjects`, `switchFocus`, `closeToGeneral`；或并入 `TaskRepository`
- `TaskWorkspaceSnapshot` 演进：带 `focusedProject` + **已按归属过滤**的 `recentSummaries`

---

## 4. 运行时

```text
submit
  → snapshot(focusedProject, activeTask, summaries ∈ same scope)
  → Continuity / TaskRouter / Heuristic
       catalog 仅同 project_id（或仅 NULL）
  → beginNew / resume / continue 保持同一 project_id
  → model：system + project appendix + related（同 scope）
  → tools：PathGuard + 默认 cwd 取自 focus
```

### 4.1 `AgentRuntime` 状态

- `focusedProject: ProjectRecord?`
- `activeTask`（归属与 focus 一致）
- `recentSummaries`（已过滤）

### 4.2 关键规则

- `beginNewTask` / `startFresh`：写入当前 `focusedProject?.id`
- `activateTask`：若 `task.project_id ≠ focus` → 先 switch project（或拒绝并提示）
- 加载 `relatedTaskIDs` 时 **丢弃跨 project** 的 id
- Project 级 `last_active_task_id` 在切换离开时更新

---

## 5. PathGuard（P0 即理想策略）

不采用「先只改 cwd/prompt、后收紧」的过渡方案。Project focus 下从第一天起按下列策略执行。

### 5.1 策略枚举（实现形态）

```text
PathGuard.Policy
  · home          — General：解析后必须在 ~ 下（今日行为）
  · project(root) — Focused project：见下
```

运行时根据 `focusedProject` 注入 policy；工具不自行猜测。

### 5.2 Project 策略（合理默认）

| 操作类 | 规则 |
|--------|------|
| **写**（`write_text_file`、`delete_file`、`create_directory`、`move`/`copy`/`rename` 的目标侧等） | 解析后物理路径必须在 **project root 内**（含 root 自身） |
| **读**（`read_text_file`、`list_directory`、`search_files` 等） | 同上，默认仅 root 内 |
| **Shell `working_directory`** | 若省略 → **root**；若提供 → 必须在 root 内 |
| **相对路径** | 相对 **project root** 解析（不是随意 cwd） |
| **Symlink** | 解析后的真实路径必须仍在 root 内（防链出工程） |
| **Open / Create 校验** | root 必须存在（Create 则创建后存在）、为目录、解析后位于 **家目录内**（继承 Sage 总安全底线） |

### 5.3 家目录底线

- 任意 policy 下，路径仍不得逃出 `~`（与今日一致）
- Project root 在 Open/Create 时就必须通过「目录 + 在家目录内」校验；之后 project 策略是 **更严的子集**

### 5.4 显式跨根（P0 不做，留口子）

- P0：**禁止**读写 project root 之外（即使仍在 `~`）
- 若未来需要「读参考项目」，单独做显式能力（只读 + 不进 routing），不在 P0 放松沙箱

### 5.5 Shell 现实约束

- P0：强制/默认 cwd ∈ root，且 `working_directory` 参数受 PathGuard
- 进程内 `cd /elsewhere` 仍可能触及 root 外——在工具 description 中写明；完整 OS 级 sandbox 单独立项（不阻塞 Phase A）

### 5.6 错误文案

- General：`Only paths under ~/ are accessible.`
- Project：`Only paths under the active project root (<root>) are accessible.`（可附带短路径）

### 5.7 与系统提示一致

- Focused 时 system appendix 写明 root 与沙箱规则，与 PathGuard 行为一致，避免模型与运行时各说各话

---

## 6. UI 信息架构

- **Header**（`AgentWorkspaceView`）：Project 菜单 — 当前 General/工程名；最近列表；Open…；Create…；Close Project
- **Start Fresh**：仅当前 scope
- **Context chip**：仅同 project 的相关提示；可附短路径
- **Menu bar**：Open / 最近（次要）
- **窗口标题**：`Sage — General` / `Sage — <name>`

暂不做完整 task 列表；继续 routing + Fresh。Project 切换是用户可见主导航。

---

## 7. 决策记录

| 议题 | 决定 |
|------|------|
| 多 project 并行 | 要；UI focus 单一 |
| Task 绑定 | 强制；创建时写入 |
| Task 换 project | P0 不允许 |
| 跨 project 路由 / related | 禁止 |
| 跨 project 只读参考 | P0 不做 |
| PathGuard | **P0 即项目根沙箱（§5）** |
| 同 root 重复 Open | 复用同一 project |
| 删除 Project | P0 只 Close/隐藏；硬删另议 |
| 命名 | Project，不新造 Workspace 实体 |

---

## 8. 实现清单

### Phase A — 骨架（可合并交付）

#### A.1 数据层

- [x] `projects` 表 + GRDB 模型 `ProjectRecord`
- [x] `tasks.project_id` 迁移与读写
- [x] `app_state.focused_project_id` + active/focus 不变量校验
- [x] `last_active_task_id` 在 switch/close 时更新
- [x] `loadWorkspace` / summaries / catalog 按 `project_id` 过滤
- [x] 既有数据迁移为 General；同 `root_path` 唯一约束

#### A.2 PathGuard（理想策略，非过渡）

- [x] `PathGuard.Policy`（`home` / `project(root)`）
- [x] `resolveAllowed(_:policy:)`（或等价 API）；symlink 后仍须落在允许根内
- [x] Project：相对路径相对 root；读写均限 root；仍须 ⊆ `~`
- [x] Open/Create 时校验 root（目录、∈ `~`）
- [x] 所有文件类工具 + Shell `working_directory` 走 policy
- [x] `ToolError.pathNotAllowed` 文案区分 General / Project
- [x] 更新 `TOOL_DESIGN.md` / 工具 description 中的路径边界说明

#### A.3 运行时

- [x] `AgentRuntime`：`focusedProject`、scope 感知的 `beginNew` / `startFresh` / `activateTask`
- [x] `openProject` / `createProject` / `switchProject` / `closeToGeneral`
- [x] TaskRouter / Continuity / Heuristic：catalog 与 resume 同 scope
- [x] Related 注入过滤跨 project id
- [x] System prompt project appendix（root + 沙箱说明）
- [x] 工具执行前注入当前 PathGuard policy（及默认 cwd = root）

#### A.4 UI

- [x] Header Project 菜单（General / 最近 / Open / Create / Close）
- [x] Open：`NSOpenPanel` 选目录
- [x] Create：选父目录 + 名称（可选 `git init`）
- [x] 窗口标题反映 focus
- [ ] Menu bar 次要入口（可选，可与 Header 同 PR）
- [x] Start Fresh 文案/行为限当前 scope

#### A.5 验收

- [ ] General 回归：无 project 时行为与现网一致（含 PathGuard = `~`）
- [ ] A 中创建的 task 不会被 B 的路由 resume
- [ ] 同路径多次 Open 复用 project 并恢复 last task
- [ ] Project 下写 root 外路径失败；相对路径写在 root 内成功
- [ ] Project 下 Shell 默认 cwd 为 root；非法 `working_directory` 失败

---

### Phase B — 代码体验 / Project 工作台

> 决策（2026-08-13）：Project 窗升级为轻量工程工作台；General 仍为单面板对话。

#### 已拍板

| 议题 | 决定 |
|------|------|
| `.sage` | Open/Create 时幂等创建 `<root>/.sage/` + `skills/`；**不**默认写入 `.gitignore` |
| Chrome | 只展示工程信息（名、root 短路径、分支）；**无**「切回 General」入口 |
| 分支 | 有 git 时展示当前分支，并支持切换本地分支 |
| Tabs | Task（默认）\| Files \| History；后两者 **先纯浏览** |
| 空引导 | 空 task 时一句「Tell me what to do」类提示即可（无 starter checklist） |

#### 清单

- [x] Open/Create 确保 `.sage` + `.sage/skills`
- [x] Project chrome：名 + root 路径（可点 Finder）；无 General 返回按钮
- [x] 分支菜单：列出本地分支并 `checkout`（失败表面错误）
- [x] 多 tab 壳：Task / Files / History（Files/History 浏览优先）
- [x] Project 空 transcript：Tell me what to do
- [x] `search_files` / `list_directory` 缺省 path → root
- [ ] write-file / 工具结果项目相对路径联调
- [ ] 开窗 bootstrap 无串台闪烁

---

### Phase C — 加深（对齐路线图）

- [ ] 项目级 `.sage` 配置（instructions / ignore；skills 目录已有）
- [ ] Files tab 真文件树 + 可选变更感知（FSEvents）
- [ ] History tab 真 commit log
- [x] 多窗口各持 focus（4.2），共享 projects / MCP / settings；tips 随 window lifecycle
- [ ] 记忆：project 级 vs global 分层（3.1）— enhance 主路径已强化
- [ ] Shell 更强隔离（若需要）单独立项
- [ ] 显式跨 project 只读参考（若需要）单独立项
- [ ] Project 硬删 / 归档策略

---

## 9. 成功标准（Phase A）

1. Task 归属与 focus 不一致的状态无法被 commit  
2. 路由与 related 永不跨 project  
3. Project focus 下 PathGuard 拒绝 root 外读写  
4. General focus 下 PathGuard 行为与今日一致  
5. Open / Create / Switch / Close 可完成且可恢复 last task  

---

## 10. 相关文档

- `TASK_ROUTING_DESIGN.md` — task 路由；Project 上线后 catalog 必须加 scope  
- `Sage/Tools/TOOL_DESIGN.md` — 工具文案与错误标准；PathGuard 文案需同步  
- `DEVELOPMENT_ROADMAP.md` — 3.3 / 4.2 等与 Phase C 对齐  

---

## 11. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-08-09 | 初稿：多 project、task 绑定、Phase A–C；P0 PathGuard 采用项目根沙箱（非过渡方案） |
| 2026-08-09 | Phase A 骨架落地：DB / PathGuard / Runtime / Header UI；A.5 手工验收待勾 |
| 2026-08-13 | Phase B 工作台决策：`.sage` 不进 gitignore；chrome 无 General 入口；分支可切换；Task/Files/History 多 tab（后两者先浏览）；空引导 Tell me what to do |
