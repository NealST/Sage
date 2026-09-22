---
name: apple-hig-components-status-system
description: "Apple HIG distilled reference for Components > Status and System experiences groups: progress indicators, gauges, rating indicators, activity rings, notifications, Live Activities (Dynamic Island), snippets, App Shortcuts, controls, status bars, Top Shelf (tvOS), watch complications, watch faces, widgets (families, rendering modes, size tables). Use when designing, implementing, or reviewing these components, checking platform availability (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), or verifying numeric specs (widget/Live Activity dimensions, complication sizes). Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), input methods (apple-hig-inputs), other component groups (apple-hig-components-content-layout, apple-hig-components-menus-actions, apple-hig-components-presentation-input), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 通知, 实时活动, 小组件, 表盘, 复杂功能, 进度条, 状态栏"
---

# Apple HIG — Components: Status & System Experiences

Distilled from https://developer.apple.com/design/human-interface-guidelines/ — Components > "Status" and "System experiences" groups, scraped 2026-09-22. 14 components across 4 reference files; best practices, platform support (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), and numeric specifications are preserved from the source pages.

## Component index

| Component | Highlights | Reference |
|---|---|---|
| Progress indicators | Determinate vs indeterminate; accurate, even pacing; Cancel/Pause; refresh controls (iOS); macOS indeterminate bars | [indicators.md](./references/indicators.md) |
| Gauges | Value within a range; standard vs capacity styles; accessory variant for Lock Screen widgets; macOS level indicators | [indicators.md](./references/indicators.md) |
| Rating indicators | macOS-only star rankings; no partial symbols; inline rank editing | [indicators.md](./references/indicators.md) |
| Activity rings | Move/Exercise/Stand only; black background, unchanged colors; single person; HKActivityRingView | [indicators.md](./references/indicators.md) |
| Notifications | Consent-first, glanceable; up to 4 actions; badges; preview-hidden text; watchOS short/long looks and double tap | [notifications.md](./references/notifications.md) |
| Live Activities | ≤8 h tasks; compact/minimal/expanded/Lock Screen presentations; 2 s animation cap; 14 pt margins; full dimension tables (iOS, iPadOS, CarPlay, watchOS, Dynamic Island widths) | [notifications.md](./references/notifications.md) |
| Snippets | Siri/App Shortcut confirmation and result views; ≤400 pt custom view height; descriptive primary button | [notifications.md](./references/notifications.md) |
| App Shortcuts | Up to 10 per app; app schemas vs unique features; parameter values; activation phrases; Spotlight ordering | [system-experiences.md](./references/system-experiences.md) |
| Controls | Control Center/Lock Screen/Action button buttons and toggles; symbol+title+value; tinted states; locked-device camera capture (iOS 18+) | [system-experiences.md](./references/system-experiences.md) |
| Status bars | iOS/iPadOS only; obscure content beneath (scroll edge effect); hide only temporarily for media | [system-experiences.md](./references/system-experiences.md) |
| Top Shelf | tvOS-only; carousel actions/details, sectioned content row, scrolling inset banner; image size tables (poster/square/16:9, 1920 px width) | [system-experiences.md](./references/system-experiences.md) |
| Complications | watchOS-only; WidgetKit families (circular, corner, inline, rectangular) with per-case-size image tables; legacy ClockKit templates; 2 pt+ line widths | [watch-widgets.md](./references/watch-widgets.md) |
| Watch faces | watchOS-only; shareable faces with your complications; Series 3 compatibility fallbacks | [watch-widgets.md](./references/watch-widgets.md) |
| Widgets | System + accessory families per platform; full-color/accented/vibrant rendering modes; 16 pt margins, ≥11 pt text; dimension tables for iOS, iPadOS, visionOS, watchOS | [watch-widgets.md](./references/watch-widgets.md) |

## How to use

- Find the component in the index, open its reference file, and apply the "Best practices" bullets (imperative do/don't guidance condensed from the source pages).
- Check "Platform considerations" before committing to a component — several are single-platform (rating indicators and status bars, Top Shelf, complications, watch faces) and many are explicitly unsupported on tvOS or visionOS.
- Preserve numeric specifications exactly as tabulated: widget/Live Activity dimensions per device, Dynamic Island widths, complication image sizes per Apple Watch case, Top Shelf image sizes, and count/duration limits (10 App Shortcuts, 4 notification actions, 8-hour Live Activities, 2-second animations, 400-pt snippets).
- For topics outside this skill, see the sibling skills listed in the description's "Do not use for" clause (foundations, patterns, inputs, other component groups, technologies).
