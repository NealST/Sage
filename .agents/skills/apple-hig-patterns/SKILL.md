---
name: apple-hig-patterns
description: "Apple HIG Patterns: launching, onboarding, offering help, full screen, live-viewing apps, entering data, drag and drop, undo/redo, file management, printing, managing accounts, settings, ratings and reviews, feedback, loading, playing audio/haptics/video, modality, multitasking, collaboration and sharing, managing notifications, searching, charting data, workouts. Use when designing/reviewing Apple-platform app flows (launch, onboarding, data entry, modals, notifications, media, search) or checking platform differences and spec tables (audio categories, interruption levels, video encodings). Do not use for: design foundations (apple-hig-foundations), input methods (apple-hig-inputs), UI components (apple-hig-components-content-layout, apple-hig-components-menus-actions, apple-hig-components-presentation-input, apple-hig-components-status-system), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 启动页, 新手引导, 加载, 弹窗, 通知, 搜索, 拖拽, 撤销重做, 账号, 设置"
---

# Apple HIG — Patterns

Distilled from the [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) **Patterns** section, scraped 2026-09-22. Covers 25 topics across iOS/iPadOS/macOS/tvOS/visionOS/watchOS, with per-platform differences and "Not supported in X" statements preserved, plus spec tables: AVAudioSession categories, notification interruption levels, watchOS video encoding recommendations, playback aspect-ratio defaults.

## Topic index

| Topic | Highlights | Reference |
|---|---|---|
| Launching | Launch instantly; launch screen rules (iOS/iPadOS/tvOS only); restore state; splash screens | [Launching](./references/onboarding-launching.md) |
| Onboarding | Fast, fun, optional; teach by doing; context-specific tips; permission timing | [Onboarding](./references/onboarding-launching.md) |
| Offering help | Inline help vs tutorials; tip types and eligibility rules; tooltip limits (60–75 chars) | [Offering help](./references/onboarding-launching.md) |
| Going full screen | When to support; no programmatic resizing; Dock access; deferred exit gestures | [Going full screen](./references/onboarding-launching.md) |
| Live-viewing apps | One-tap playback; live badges; EPG; cloud DVR; content footer; instant channel-change feedback | [Live-viewing apps](./references/onboarding-launching.md) |
| Entering data | Pre-gather from system; secure fields; choices over typing; live validation | [Entering data](./references/data-input.md) |
| Drag and drop | Move vs copy rules; multi-item drags; drag feedback; spring loading; Option key | [Drag and drop](./references/data-input.md) |
| Undo and redo | Predictable, visible results; unlimited undos; shake alert wording; Edit menu | [Undo and redo](./references/data-input.md) |
| File management | Autosave; Quick Look; document launcher (iOS 18+); file provider extensions | [File management](./references/data-input.md) |
| Printing | Discoverable print actions; dim when impossible; custom print panel categories | [Printing](./references/data-input.md) |
| Managing accounts | Delay sign-in; passkeys; authentication naming; account-deletion requirements | [Managing accounts](./references/account-settings.md) |
| Settings | Smart defaults; minimal settings; task options in context; macOS settings window | [Settings](./references/account-settings.md) |
| Ratings and reviews | Ask after engagement; natural breaks; 3 prompts per 365 days; system prompt | [Ratings and reviews](./references/account-settings.md) |
| Feedback | Match significance to delivery; accessible multi-channel feedback; alert restraint | [Feedback](./references/feedback-media.md) |
| Loading | Show something immediately; background loading; determinate vs indeterminate | [Loading](./references/feedback-media.md) |
| Playing audio | Silence/volume/rerouting expectations; audio category table; interruption handling | [Playing audio](./references/feedback-media.md) |
| Playing haptics | Documented pattern meanings; transient vs continuous events; UIFeedbackGenerator types | [Playing haptics](./references/feedback-media.md) |
| Playing video | System player; aspect-ratio defaults; TV app integration; watchOS encoding table | [Playing video](./references/feedback-media.md) |
| Modality | Clear benefit only; simple, short tasks; obvious dismissal; one modal at a time | [Modality](./references/modality-multitasking.md) |
| Multitasking | Save/restore context; pause on switch; audio interruption responses; per-platform modes | [Multitasking](./references/modality-multitasking.md) |
| Collaboration and sharing | Share button placement; permission summaries; Collaboration button; Messages events | [Collaboration and sharing](./references/sharing-notifications.md) |
| Managing notifications | Interruption level table (Passive/Active/Time Sensitive/Critical); Focus; marketing rules | [Managing notifications](./references/sharing-notifications.md) |
| Searching | Primary placement; single search location; scope display; suggestions; Spotlight indexing | [Searching](./references/sharing-notifications.md) |
| Charting data | When to chart; keep simple; accessible charts; consistency and continuity | [Charting data](./references/sharing-notifications.md) |
| Workouts | watchOS session layout; glanceable metrics; end-of-session summary; Activity rings | [Workouts](./references/sharing-notifications.md) |

## How to use

- Consult a topic's **Best practices** bullets when designing or reviewing a feature; they are written as imperative do/don't guidance distilled from the HIG prose.
- Always check **Platform considerations** before porting a pattern — several patterns (drag and drop, undo/redo, printing, going full screen, workouts, multitasking) are unsupported on specific platforms, and details differ per platform.
- Use the preserved tables as authoritative specs: audio session categories, notification interruption-level behaviors, watchOS video encoding values, and video playback aspect-ratio defaults.
- For related foundational topics (layout, color, typography), UI components (alerts, sheets, progress indicators), or technologies (SharePlay, widgets, Live Activities), use the sibling apple-hig-* skills listed in the description.
