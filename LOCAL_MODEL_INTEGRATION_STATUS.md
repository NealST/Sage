# 本地模型集成（MLX + Hugging Face）—— 方案与进度快照

> 状态：**暂停**（2026-10-23）。代码已全部写完，卡在 Metal Toolchain 缺失导致无法编译验证。
> 原始方案全文见 `/Users/mozheng/.qoder/plans/early-rock-sparrow.md`。

## 一、方案架构（定稿）

核心思路：**请求链路完全由 `ModelSettingsSnapshot` 驱动**。本地模型经由进程内
localhost OpenAI 兼容服务器提供，`ModelSettings.snapshot(for:)` 在选中本地模型时把
baseURL 路由到本地服务器 —— ModelClient / Harness / probe / 重试 / 定时任务全部零改动复用。

1. **数据层**：`ModelSelection { origin: cloud|local, identifier }`，`ModelSettings`
   增加 defaultSelection + plan/execute/review 三阶段可选覆盖（nil = 跟随默认），
   含旧 `llm.model` 字符串 → 新结构的 UserDefaults 迁移。
2. **MLX 引擎**：`LocalModelEngine`（actor）单模型常驻、按需换载、warm-up 预热、
   内存压力自动卸载；流式生成 + 工具调用解析（mlx-swift-lm 自带 ToolCallProcessor）。
3. **进程内服务器**：`LocalModelServer`（Hummingbird 2，监听 127.0.0.1 动态端口），
   提供 `GET /v1/models` 与 `POST /v1/chat/completions`（非流式 + SSE + tool_calls）。
4. **HF 下载**：`HubEndpointResolver`（官方/镜像竞速 + 24h 缓存，CN 地区自动
   hf-mirror.com）+ 精选目录（mlx-community Qwen3 4bit 系列）+ HubApi 搜索 + Repo ID 手动添加。
5. **UI**：composer statusRow 模型下拉菜单（云端/本地分组、当前项 checkmark、
   origin 徽章）+ Settings 新增 Models pane（默认/分阶段模型选择、云端目录、
   本地下载管理、删除确认）。
6. **Intel 防护**：MLX 相关文件 `#if arch(arm64)` 包裹，非 arm64 下本地源置灰。

## 二、当前进度

### 已完成

| 模块 | 文件 | 状态 |
|---|---|---|
| SwiftPM 依赖 | `Sage.xcodeproj/project.pbxproj` | ✅ mlx-swift 0.31.4 / mlx-swift-lm 3.31.4 / swift-huggingface 0.9.0 / hummingbird 2.28.0 全部解析成功（Package.resolved 已写入） |
| 历史恢复 | `Sage/Agent/Model/HubEndpointResolver.swift`、`MemoryPressureMonitor.swift` | ✅ 从 git 历史 (a7dc806) 恢复并适配 |
| 数据层 | `Sage/Agent/Model/ModelSelection.swift`、`ModelSettings.swift` | ✅ 代码完成，**未经编译验证** |
| 引擎 | `Sage/Agent/Model/LocalModelEngine.swift` | ✅ 代码完成，API 已逐一对照 mlx-swift-lm 3.31.4 真实源码核验 |
| 服务器 | `LocalModelServer.swift`、`+HTTP.swift`、`+Wire.swift` | ✅ 代码完成，Hummingbird 2.28.0 API 已逐一核验；SSE wire 与 `ModelClientWire.swift` 客户端解码器兼容性已核验 |
| 目录/下载 | `Sage/Agent/Model/ModelCatalog.swift` | ✅ 代码完成（云端 /models 拉取缓存、精选列表、搜索、下载状态机、删除） |
| Composer UI | `Sage/Panel/Composer/AgentComposerView+ModelPicker.swift`、`AgentComposerView.swift`、`Design/ModelOriginBadge.swift` | ✅ 代码完成 |
| Settings UI | `Sage/Settings/SettingsModelsSection.swift`、`LocalModelBrowseView.swift`、`SettingsPane.swift`、`SettingsView.swift`、`AppDelegate.swift` | ✅ 代码完成 |
| 单测 | `SageTests/AgentTests/LocalModelServerTests.swift` 等 | ✅ 已写，**未运行** |

### 已核验的关键技术事实（恢复工作前必读）

- **Qwen3 工具调用无需修改**：`mlx-swift-lm Evaluate.swift:1504` 中
  `toolCallFormat ?? .json` 会兜底到 `.json` 解析器，其标记正是 Qwen3 的
  `⟪tool_call⟫` 格式。之前担心的 "infer 不识别 qwen3" 不是问题。
- **Hummingbird 2 API**：`request.body.collect(upTo:)`（NIOCore 的
  `AsyncSequence where Element == ByteBuffer` 扩展，返回 `ByteBuffer`）、
  `Response(status:headers:body:)`、`ResponseBody { writer in ... }`、
  `writer.write(ByteBuffer)` / `writer.finish(nil)`、`Router().get/post(path) { req, ctx in }`、
  `Application(router:configuration:onServerRunning:)`、
  `ApplicationConfiguration(address: .hostname(port: 0))` —— 全部与 2.28.0 源码签名一致。
- **swift-huggingface 0.9.0**：`HubClient(host:)`、
  `downloadSnapshot(of:revision:matching:localFilesOnly:progressHandler:)`（progressHandler
  为 `@MainActor @Sendable (Progress) -> Void`）、`listModels(search:author:...)`、
  `HubCache.default` —— 已核验。
- **swift-huggingface 没有 `HuggingFaceDownloaderError`** —— 引擎里用的是自定义
  `ModelCatalogError.invalidRepositoryID`。
- **新文件无需改 pbxproj**：Sage / SageTests 均为 fileSystemSynchronizedRootGroups。
- **CLI 构建需要 `-skipMacroValidation`**：mlx-swift-lm 的 `MLXHuggingFaceMacros`
  宏插件在命令行构建时会被 Xcode 宏信任门拦下。

### 卡点（暂停原因）

1. **Metal Toolchain 缺失（直接原因）**：本机 Xcode 无法编译 mlx-swift 的
   `.metal` 内核，报错：
   `error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`
   尝试 `xcodebuild -downloadComponent MetalToolchain` 下载时 Apple 资产目录拉取失败
   （`Failed fetching catalog for assetType (com.apple.MobileAsset.MetalToolchain)`），
   疑与当前网络（VPN）有关。
2. **整体未编译**：所有新代码未经过编译验证，预期会有一批常规编译错误需要修。

## 三、恢复步骤（建议顺序）

1. **装 Metal Toolchain**：在 Xcode → Settings → Components 里下载 Metal Toolchain，
   或在网络通畅时重跑 `xcodebuild -downloadComponent MetalToolchain`。
   （若彻底无法获取，替代方案：把 `Cmlx` 换成预编译 air 的 mlx-swift 版本，或改用
   Swift Chat / MLX 终端等已编译产物验证思路，但代价较大。）
2. **首次构建**：
   ```
   xcodebuild -project Sage.xcodeproj -scheme Sage -configuration Debug \
     -destination 'platform=macOS' -derivedDataPath .derivedData \
     -skipMacroValidation build
   ```
   首次全量编译较慢（MLX C++/Metal 内核）。
3. **修编译错误**（预期集中在：Sendable/actor 隔离、@Observable 宏与 Swift 5 模式、
   Hummingbird 上下文类型推断）。
4. **跑单测**：`SageTests`（LocalModelServerTests 需要服务器能启动；迁移测试、
   解析器测试与 MLX 无关应先绿）。
5. **端到端**：下载 Qwen3-0.6B-4bit（最小体积验证全链路）→ composer 选择 →
   带工具调用的任务（观察 SSE 与 tool_calls）→ 分阶段换模型（验证换载）→
   删除确认 → 重启验证持久化/迁移 → curl `/v1/models`、`/v1/chat/completions`。

## 四、风险备忘（方案中已定对策）

- 小模型跑 Plan 的 JSON 契约不可靠 → 精选列表标注适用规模，推荐 4B+。
- 三阶段选不同本地模型会反复换载（10s+）→ 服务器串行排队 + statusRow 提示。
- 本地 4bit 模型上下文 ~32k → 靠现有 ContextCompactor 兜底。
- Intel Mac → `#if arch(arm64)` 隔离 + UI 置灰。
