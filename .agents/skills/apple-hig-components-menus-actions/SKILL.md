---
name: apple-hig-components-menus-actions
description: "Apple HIG distilled reference for Components > Menus and actions and Navigation and search groups: buttons, pull-down buttons, pop-up buttons, menus, context menus, edit menus, dock menus, the menu bar, activity views, Home Screen quick actions, ornaments, toolbars, path controls, search fields, sidebars, tab bars, token fields. Use when designing, implementing, or reviewing these components, choosing among menu, action, or navigation controls, checking platform availability (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), or verifying numeric specs (hit targets, button sizes, tab bar metrics). Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), input methods (apple-hig-inputs), other component groups (apple-hig-components-content-layout, apple-hig-components-presentation-input, apple-hig-components-status-system), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 按钮, 菜单, 菜单栏, 工具栏, 侧边栏, 标签栏, 搜索框"
---

# Apple HIG — Components: Menus, Actions & Navigation

Distilled from https://developer.apple.com/design/human-interface-guidelines/ — Components > "Menus and actions" and "Navigation and search" groups, scraped 2026-09-22. 17 components across 4 reference files; best practices, platform support (iOS, iPadOS, macOS, tvOS, visionOS, watchOS), and numeric specifications are preserved from the source pages.

## Component index

| Component | Highlights | Reference |
|---|---|---|
| Buttons | Style/content/role; 44x44 pt hit region (60x60 pt visionOS); macOS push/square/help/image buttons; visionOS sizes and shapes | [buttons.md](./references/buttons.md) |
| Pull-down buttons | Menu of commands related to the button's purpose; aim for ≥3 items; destructive-item confirmation | [buttons.md](./references/buttons.md) |
| Pop-up buttons | Flat list of mutually exclusive options; useful default selection; iPadOS popover/modal use | [buttons.md](./references/buttons.md) |
| Menus | Labels, icons, organization, submenus (one level, ~5 items), toggled items; iOS small/medium/large layouts; visionOS breakthrough effects | [menus.md](./references/menus.md) |
| Context menus | Relevant frequent actions only; hide (don't dim) unavailable items; previews; max ~3 groups | [menus.md](./references/menus.md) |
| Edit menus | Prefer system-provided; context-relevant commands; undo/redo support; compact vs vertical styles | [menus.md](./references/menus.md) |
| Dock menus | macOS secondary-click Dock icon menu; high-value custom items available elsewhere too | [menus.md](./references/menus.md) |
| The menu bar | Standard menu order (app, File, Edit, Format, View, app-specific, Window, Help); per-menu item tables; iPadOS vs macOS differences; menu bar extras | [menus.md](./references/menus.md) |
| Activity views | Share sheet with system and app-specific activities; share/action extensions; ~70x70 px custom icons | [actions.md](./references/actions.md) |
| Home Screen quick actions | App actions from the Home Screen; max 4; succinct titles; SF Symbols (no emoji) | [actions.md](./references/actions.md) |
| Ornaments | visionOS-only floating controls beside a window; keep visible; width ≤ window width | [actions.md](./references/actions.md) |
| Toolbars | Leading/center/trailing groupings; max 3 groups; titles < 15 chars; per-platform placement and behavior | [actions.md](./references/actions.md) |
| Path controls | macOS-only file system path display; standard and pop-up styles; window body only | [navigation-search.md](./references/navigation-search.md) |
| Search fields | Placement patterns (tab, toolbar, inline); scope bars and tokens; suggestions; per-platform guidance | [navigation-search.md](./references/navigation-search.md) |
| Sidebars | Max 2 hierarchy levels; customization and hiding; Liquid Glass content extension | [navigation-search.md](./references/navigation-search.md) |
| Tab bars | Navigation, not actions; tvOS metrics (68 pt height, 46 pt top offset); visionOS vertical look-and-tap | [navigation-search.md](./references/navigation-search.md) |
| Token fields | macOS-only text-to-token conversion; suggestions delay; context menus on tokens | [navigation-search.md](./references/navigation-search.md) |

## How to use

- Find the component in the index, open its reference file, and apply the "Best practices" bullets (imperative do/don't guidance condensed from the source pages).
- Check the "Platform considerations" section before committing to a component — several are macOS-only (dock menus, path controls, token fields), visionOS-only (ornaments), or unsupported on watchOS/tvOS.
- Preserve numeric specifications exactly as tabulated: hit regions, visionOS button sizes, tvOS tab bar metrics, iOS menu layouts, and item-count limits.
- For topics outside this skill, see the sibling skills listed in the description's "Do not use for" clause (foundations, patterns, inputs, other component groups, technologies).
