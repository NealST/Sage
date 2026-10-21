# scripts/

Build/porting 辅助脚本。均从仓库根目录执行。

## harness_port.py — codex → Swift 移植追踪

移植状态与 lint 工具（`Docs/EXECUTE_HARNESS_PORT_PLAN.md` Phase 0）。

```sh
python3 scripts/harness_port.py generate   # 生成/更新 Sage/Agent/Execute/Harness/PORTING.md（保留手改状态与备注）
python3 scripts/harness_port.py check      # lint 文件头 + 覆盖完整性 + 表一致性，违规退出码 1
python3 scripts/harness_port.py stats      # 打印分 phase 进度统计
```

路径约定：`codex-rs/core/src/<path>.rs` → `Sage/Agent/Execute/Harness/<path>.swift`；文件头保留上游路径与 Apache-2.0 出处。

## harness_test.sh — 无 xcodebuild 的 Harness 测试

在 Xcode license 提示阻塞 `swift build` 的机器上，直接用 Xcode toolchain 的 swiftc 编译
ExecuteHarness 模块并跑测试。自带最小 XCTest 实现（`xctest_shim.swift`）。
跑过 `sudo xcodebuild -license accept` 后请改用 `xcodebuild test`。

```sh
scripts/harness_test.sh
```

注意：生成的 runner 是 async main，测试按顺序 await。不要用 Task + DispatchSemaphore
桥接 sync→async —— 阻塞主线程会死锁所有继承 main-actor 隔离的 Task。

## rebrand_and_strip_codex_product.py / rebrand_remaining_codex_identifiers.py

一次性品牌迁移脚本（codex → Sage）。保留用于历史追溯，日常开发不需要执行；
两者都跳过 `PORTING.md`、`Docs/EXECUTE_HARNESS_PORT_PLAN.md` 与 `harness_port.py`（这些文件需要保留上游 codex 标识）。
