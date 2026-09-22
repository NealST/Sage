---
name: apple-hig-technologies-system
description: "Apple HIG distilled reference for system, intelligence, and media technologies: AirPlay, Always On, App Clips and App Clip Codes, Mac Catalyst, NFC, generative AI, machine learning, Siri and App Intents, Maps, Live Photos, photo editing, iMessage apps and stickers, VoiceOver, iCloud. Use when designing features that stream media via AirPlay, create lightweight App Clip experiences, port iPad apps to the Mac, integrate generative AI or ML, expose app actions to Siri, embed maps or place cards, handle photos or stickers, support the VoiceOver screen reader, or sync content via iCloud. Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), input methods (apple-hig-inputs), UI components (apple-hig-components-*), domain tech like Apple Pay/HealthKit/AR/HomeKit (apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, AirPlay, App Clips, Mac Catalyst, NFC, 生成式 AI, 机器学习, Siri, 地图, Live Photos, 照片编辑, iMessage 贴纸, VoiceOver, iCloud"
---

# Apple HIG — Technologies: System & Intelligence

Distilled from the Apple Human Interface Guidelines Technologies section (https://developer.apple.com/design/human-interface-guidelines/), scraped 2026-09-22. Covers 14 technologies in three groups — system integration, intelligence, and media/content — with platform availability differences and numeric specifications preserved.

## Topic index

| Technology | Highlights | Reference |
|---|---|---|
| AirPlay | Wireless streaming, custom player rules, icon and trademark usage | [system-integration](./references/system-integration.md) |
| Always On | Dimmed glanceable interfaces on iPhone 14 Pro and Apple Watch | [system-integration](./references/system-integration.md) |
| App Clips | Lightweight on-the-go/demo experiences; App Clip Code and printing specs | [system-integration](./references/system-integration.md) |
| Mac Catalyst | iPad apps on the Mac: idioms, navigation, gesture conversion | [system-integration](./references/system-integration.md) |
| NFC | In-app and background tag reading, approachable scanning copy | [system-integration](./references/system-integration.md) |
| Generative AI | Responsible AI design, transparency, privacy, hallucination handling | [intelligence](./references/intelligence.md) |
| Machine learning | ML UX patterns: feedback, calibration, mistakes, confidence, attribution | [intelligence](./references/intelligence.md) |
| Siri | App Intents and schema integration, dialogue and editorial rules | [intelligence](./references/intelligence.md) |
| Maps | Interactive maps, place cards, indoor maps, watchOS snapshots | [intelligence](./references/intelligence.md) |
| Live Photos | Frame-consistent adjustments, badges, sharing | [media-content](./references/media-content.md) |
| Photo editing | Photos app editing extensions | [media-content](./references/media-content.md) |
| iMessage apps and stickers | Compact/expanded views; icon, sticker size, and format specs | [media-content](./references/media-content.md) |
| VoiceOver | Accessibility labels, grouping, rotor, visionOS gesture behavior | [media-content](./references/media-content.md) |
| iCloud | Transparent sync, storage etiquette, conflict resolution | [media-content](./references/media-content.md) |

## How to use
- Find the technology in the topic index, open its reference file, and apply the Best practices bullets; every entry follows the same structure (definition, best practices, platform considerations, resources).
- Check Platform considerations before designing — Always On, App Clips, NFC, photo editing, and iMessage apps are unsupported on several platforms, and Maps, Live Photos, and VoiceOver have watchOS/visionOS-specific behavior.
- Treat numeric specifications as exact requirements, not suggestions: App Clip Code minimum sizes and distance ratios, iMessage icon/sticker dimensions and file-size limits, Maps padding values, and Mac Catalyst scaling percentages.
- For AI features, read Generative AI and Machine learning together; Siri integration additionally depends on the App Intents framework and app schema domains.
