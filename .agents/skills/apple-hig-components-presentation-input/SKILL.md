---
name: apple-hig-components-presentation-input
description: "Apple HIG distilled reference for Components > Presentation and Selection/input: alerts, action sheets, sheets, windows, panels, popovers, page controls, scroll views, text fields, combo boxes, digit entry views, virtual keyboards, pickers, segmented controls, sliders, steppers, toggles, color wells, image wells. Use when designing or reviewing these components, choosing among modal presentations (alert vs action sheet vs sheet) or selection/input controls, or checking platform support (iOS, iPadOS, macOS, tvOS, visionOS, watchOS). Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), input methods like gestures/keyboards hardware (apple-hig-inputs), other component groups (apple-hig-components-content-layout, apple-hig-components-menus-actions, apple-hig-components-status-system), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 弹窗, 警告框, 动作面板, 半屏, 浮层, 窗口, 面板, 输入框, 文本框, 选择器, 分段控件, 滑块, 开关, 复选框, 滚动视图"
---

# Apple HIG — Components: Presentation & Selection/Input

Distilled from https://developer.apple.com/design/human-interface-guidelines/ — Components > "Presentation" and "Selection and input" groups, scraped 2026-09-22. 19 components across 5 reference files; best practices, platform support (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), and numeric specifications are preserved from the source pages.

## Component index

| Component | Highlights | Reference |
|---|---|---|
| Alerts | Title + optional text + up to 3 buttons; sparing use; Cancel never default; visionOS accessory view max 154 pt high, 16-pt corner radius | [alerts-sheets.md](./references/alerts-sheets.md) |
| Action sheets | Choices tied to an intentional action; destructive style at top; watchOS max 4 buttons incl. Cancel | [alerts-sheets.md](./references/alerts-sheets.md) |
| Sheets | Scoped tasks; one sheet at a time; pair Done with Cancel/Back; iOS detents (large/medium) + grabber; iPadOS page/form styles | [alerts-sheets.md](./references/alerts-sheets.md) |
| Windows | Primary vs auxiliary; no custom window UI; macOS main/key/inactive states; visionOS default 1280x720 pt window + volumes | [windows-panels.md](./references/windows-panels.md) |
| Panels | macOS-only floating supplementary controls; inspectors; HUD usage rules | [windows-panels.md](./references/windows-panels.md) |
| Popovers | Transient, few related tasks; one at a time, no cascades; save work on auto-close; macOS detachable | [windows-panels.md](./references/windows-panels.md) |
| Page controls | Ordered flat page lists; max ~10 dots; max 2 indicator images; automatic/prominent/minimal backgrounds | [containers.md](./references/containers.md) |
| Scroll views | Content larger than the view; no same-orientation nesting; scroll edge effects; visionOS Look to Scroll; watchOS Digital Crown | [containers.md](./references/containers.md) |
| Text fields | Small specific input; placeholder + separate label; secure fields; validation timing; number formatter | [text-input.md](./references/text-input.md) |
| Combo boxes | macOS-only text field + pull-down; meaningful default; labels end with colon | [text-input.md](./references/text-input.md) |
| Digit entry views | tvOS-only full-screen PIN-style entry; secure digit fields | [text-input.md](./references/text-input.md) |
| Virtual keyboards | Match keyboard type to content (12 types); custom input views vs custom keyboard extensions | [text-input.md](./references/text-input.md) |
| Pickers | Medium-to-long lists; date picker styles (compact/inline/wheels) + 4 modes; countdown max 23 h 59 min | [controls.md](./references/controls.md) |
| Segmented controls | 2+ segments as buttons; ~5-7 segments wide, ~5 on iPhone; text or images, not both | [controls.md](./references/controls.md) |
| Sliders | Thumb between min and max; familiar directions; not for volume (iOS); macOS tick marks, linear vs circular | [controls.md](./references/controls.md) |
| Steppers | Increment/decrement pair; pair with text field for large ranges; macOS Shift-click (10x) | [controls.md](./references/controls.md) |
| Toggles | Opposing on/off states; iOS switch only in list rows; macOS switches vs checkboxes vs radio buttons (groups of 2-5) | [controls.md](./references/controls.md) |
| Color wells | Adjust element colors; system color picker; macOS highlight + drag and drop | [controls.md](./references/controls.md) |
| Image wells | macOS-only editable image view; revert to default image; standard copy/paste | [controls.md](./references/controls.md) |

## How to use

- Find the component in the index, open its reference file, and apply the "Best practices" bullets (imperative do/don't guidance condensed from the source pages).
- Check "Platform considerations" before committing to a component — several are macOS-only (panels, combo boxes, image wells), tvOS-only (digit entry views), or unsupported on specific platforms (action sheets not in visionOS; segmented controls not in watchOS; windows not in iOS/tvOS/watchOS).
- Preserve numeric specifications exactly as tabulated: alert button limits, visionOS alert/window dimensions, sheet detents, watchOS action-sheet button counts, segment-count limits, and radio-button group sizes.
- For topics outside this skill, see the sibling skills listed in the description's "Do not use for" clause (foundations, patterns, inputs, other component groups, technologies).
