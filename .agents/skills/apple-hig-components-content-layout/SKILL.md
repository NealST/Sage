---
name: apple-hig-components-content-layout
description: "Apple HIG distilled reference for Components > Content views and Layout and organization groups: charts, image views, text views, web views, collections, column views, outline views, lists and tables, labels, lockups, boxes, disclosure controls, split views, tab views. Use when designing, implementing, or reviewing these components, choosing among content-display or layout controls, checking platform availability (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), or verifying guidance like chart accessibility, label color tiers, and pane/tab count limits. Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), input methods (apple-hig-inputs), other component groups (apple-hig-components-menus-actions, apple-hig-components-presentation-input, apple-hig-components-status-system), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 图表, 集合视图, 列表, 表格, 标签, 大纲视图, 分栏视图, 选项卡视图, 折叠控件, 图像视图, 文本视图, 网页视图"
---

# Apple HIG — Components: Content & Layout

Distilled from https://developer.apple.com/design/human-interface-guidelines/ — Components > "Content views" and "Layout and organization" groups, scraped 2026-09-22. 14 components across 4 reference files; best practices, platform support (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), and numeric specifications are preserved from the source pages.

## Component index

| Component | Highlights | Reference |
|---|---|---|
| Charts | Mark types (bar/line/point), fixed vs. dynamic axis ranges, tick sequences, grid-line density, Audio Graphs and per-element accessibility labels, color-plus-shape differentiation | [content-views.md](./references/content-views.md) |
| Image views | Display-only images (typically noninteractive); consistent sizes for animated sequences; macOS image wells and image buttons; visionOS 2D/stereoscopic/spatial photos | [content-views.md](./references/content-views.md) |
| Text views | Multiline styled text, optionally editable; Dynamic Type and legibility; selectable useful text; per-platform keyboard and tvOS input limits | [content-views.md](./references/content-views.md) |
| Web views | In-app HTML/websites via WKWebView; enable forward/back navigation when needed; never replicate a web browser | [content-views.md](./references/content-views.md) |
| Collections | Ordered, highly visual image-based content; standard row/grid layouts; standard insert/delete/reorder animations; not supported in watchOS | [collections.md](./references/collections.md) |
| Column views | macOS browser for deep hierarchies navigated back and forth; root level in first column; resizable columns | [collections.md](./references/collections.md) |
| Outline views | macOS hierarchical columns/rows; sortable headings (primary heading sorts per level); Option-click expands all subcontainers; retained expansion state | [collections.md](./references/collections.md) |
| Lists and tables | Text-first rows; edit mode in iOS/iPadOS; selection feedback patterns; info button vs. disclosure indicator; per-platform styles | [lists-labels.md](./references/lists-labels.md) |
| Labels | Static text everywhere in the interface; four system label color tiers (label/secondary/tertiary/quaternary); watchOS date and timer components | [lists-labels.md](./references/lists-labels.md) |
| Lockups | tvOS focus-expanding units (content view + header + footer): cards, caption buttons, monograms, posters; consistent sizes, adequate spacing | [lists-labels.md](./references/lists-labels.md) |
| Boxes | Small grouped containers with border/title; padding over nested boxes; sentence-style titles (colon only in settings panes) | [layout-views.md](./references/layout-views.md) |
| Disclosure controls | Triangles (inward/down states) and buttons (down/up states); hide advanced details by default; max one disclosure button per view | [layout-views.md](./references/layout-views.md) |
| Split views | Primary/secondary/tertiary panes with persistent selection highlight; macOS 1-pt thin dividers and hideable panes; tvOS default 1/3–2/3 split; watchOS full-screen list/detail | [layout-views.md](./references/layout-views.md) |
| Tab views | Mutually exclusive panes; noun labels with title-style capitalization; avoid pop-up switching; no more than six tabs | [layout-views.md](./references/layout-views.md) |

## How to use

- Find the component in the index, open its reference file, and apply the "Best practices" bullets (imperative do/don't guidance condensed from the source pages).
- Check the "Platform considerations" section before committing to a component — several are macOS-only (column views, outline views, tab views), tvOS-only (lockups), or unsupported on watchOS/tvOS (collections, web views, boxes, disclosure controls).
- Preserve numeric specifications and tables exactly as given: the four label color tiers, the one-point thin divider style, the six-tab maximum, and the tvOS split-view pane proportions.
- For topics outside this skill, see the sibling skills listed in the description's "Do not use for" clause (foundations, patterns, inputs, other component groups, technologies).
