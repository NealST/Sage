---
name: apple-hig-inputs
description: "Apple HIG Inputs reference covering gestures, focus and selection, keyboards, pointing devices, remotes, Apple Pencil and Scribble, gyroscope and accelerometer, nearby interactions, Action button, Camera Control, Digital Crown, eyes, and game controls, with platform support differences and spec tables (gesture matrix, keyboard shortcuts, hit-region padding, control sizes). Use when designing or reviewing how people input, control, and interact with Apple-platform apps and games, or checking input platform support and specs. Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), UI components (apple-hig-components-content-layout, apple-hig-components-menus-actions, apple-hig-components-presentation-input, apple-hig-components-status-system), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 手势, 键盘, 触控板, 遥控器, Apple Pencil, 数字表冠, 眼动追踪, Action 按钮, 相机控制, 游戏手柄, 摇一摇"
---

# Apple HIG — Inputs

Distilled from the Inputs section of https://developer.apple.com/design/human-interface-guidelines/ (scraped 2026-09-22). Covers 13 topics — gestures, focus and selection, keyboards, pointing devices, remotes, Apple Pencil and Scribble, gyroscope and accelerometer, nearby interactions, Action button, Camera Control, Digital Crown, eyes, and game controls — with per-platform differences ("Not supported in X" statements) and spec tables preserved: standard gesture support matrix, macOS mouse/trackpad gestures, standard keyboard shortcuts, pointer hit-region padding (12/24 pt), eye-target spacing (16 pt margin / 60 pt center distance), and game touch-control sizes (44/28 pt).

## Topic index

| Topic | Highlights | Reference |
|---|---|---|
| Gestures | Standard gesture support table, custom gesture criteria, visionOS indirect vs. direct gestures, watchOS double tap, visionOS system overlay deferral | [Gestures](./references/gestures.md) |
| Focus and selection | System focus effects, iPadOS focus groups and halo effect, tvOS five focus states, visionOS focus via keyboard/controller | [Gestures](./references/gestures.md) |
| Keyboards | Full Keyboard Access, standard keyboard shortcut table, custom shortcuts, modifier-key order (Control, Option, Shift, Command), visionOS shortcut interface | [Keyboards and pointers](./references/keyboards-pointer.md) |
| Pointing devices | iPadOS content effects (highlight, lift, hover), pointer accessories, magnetism, hit-region padding 12/24 pt, macOS gesture and pointer API tables, visionOS pointer context | [Keyboards and pointers](./references/keyboards-pointer.md) |
| Remotes | Siri Remote swipe/press gestures, button behavior table (app vs. game), Back-button parent rule, EPG buttons on compatible remotes | [Keyboards and pointers](./references/keyboards-pointer.md) |
| Apple Pencil and Scribble | Marks on touch, tilt/pressure/azimuth/barrel roll, hover previews, double tap, squeeze, Scribble text entry, PencilKit canvas and Dark Mode | [Stylus and motion](./references/stylus-motion.md) |
| Gyroscope and accelerometer | Motion data only with tangible benefit, required permission copy, no direct manipulation outside gameplay | [Stylus and motion](./references/stylus-motion.md) |
| Nearby interactions | Ultra Wideband distance/direction, portrait orientation, directional field of view, continuous multi-type feedback, session-scoped identifiers | [Stylus and motion](./references/stylus-motion.md) |
| Action button | Essential functions via App Shortcuts, 3-word verb labels, iOS Live Activities without leaving context, watchOS primary/secondary actions, pause via Action + side button | [Hardware inputs](./references/hardware-inputs.md) |
| Camera Control | Overlay sliders and pickers, SF Symbols for controls, prominent values, viewfinder space planning, locked camera capture extension | [Hardware inputs](./references/hardware-inputs.md) |
| Digital Crown | watchOS 10 navigation anchoring, visual feedback and speed matching, haptic detents (linear vs. row-based), visionOS system uses | [Hardware inputs](./references/hardware-inputs.md) |
| Eyes | visionOS hover effect, 16 pt margins / 60 pt center spacing, 1 m viewing distance, rounded targets, custom hover effect delays and stability | [Hardware inputs](./references/hardware-inputs.md) |
| Game controls | Virtual control placement and 44/28 pt minimum sizes, press states, controller button-to-UI mapping table, single-key bindings, WASD proximity, visionOS spatial controllers | [Hardware inputs](./references/hardware-inputs.md) |

## How to use

- Find the topic in the index, open the linked reference file, and read its sections in order: one-sentence definition, best practices (imperative do/don't bullets), platform considerations, and resources (API/framework names).
- Check the platform considerations first when targeting a specific platform — explicit support statements (e.g., "Not supported in iOS or watchOS" for focus and selection) are preserved verbatim and prevent designing unsupported input.
- Use the markdown tables as authoritative specs (gesture support matrix, keyboard shortcuts, hit-region padding, control sizes); don't paraphrase numeric values when citing them.
- For related guidance outside inputs, switch skills: accessibility and layout basics (apple-hig-foundations), input UI components like text fields and pickers (apple-hig-components-presentation-input), interaction flow patterns like drag and drop or undo (apple-hig-patterns).
