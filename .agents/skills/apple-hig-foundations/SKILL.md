---
name: apple-hig-foundations
description: "Apple HIG foundations: design principles; platform guides (iOS, iPadOS, macOS, tvOS, visionOS, watchOS, games, iPhone Duo); accessibility, inclusion; privacy and permissions; color, Dark Mode, materials (Liquid Glass); typography, Dynamic Type, SF Symbols, icons, app icons; layout, safe areas, spatial layout, right-to-left; motion, images, immersion; writing, branding. Spec tables: Dynamic Type sizes, minimum text/control sizes, contrast ratios, icon dimensions. Use when designing/reviewing Apple-platform UI foundations, checking platform differences, or looking up HIG specs. Do not use for: UX flow patterns (apple-hig-patterns), input methods (apple-hig-inputs), UI components (apple-hig-components-content-layout, apple-hig-components-menus-actions, apple-hig-components-presentation-input, apple-hig-components-status-system), technology integrations (apple-hig-technologies-system, apple-hig-technologies-domain). 中文触发词: 苹果设计规范, HIG, iOS 设计, 设计原则, 无障碍, 深色模式, SF Symbols, Dynamic Type, 安全区, Liquid Glass"
---

# Apple HIG — Foundations

Distilled from https://developer.apple.com/design/human-interface-guidelines/ Foundations + Getting started sections, scraped 2026-09-22. Covers 27 topics across iOS/iPadOS/macOS/tvOS/visionOS/watchOS, with key spec tables preserved: Dynamic Type font sizes per platform, minimum text/control sizes, WCAG contrast ratios, app icon dimensions, tvOS grid metrics, watchOS image scales.

## Topic index

| Topic | Highlights | Reference |
|---|---|---|
| Design principles | Purpose, agency, responsibility, familiarity, flexibility, simplicity, craft, delight | [Design principles](./references/design-principles.md) |
| Designing for iOS | Medium display, one-handed ergonomics, appearance adaptivity, platform-data integration | [Platform guides](./references/platform-guides.md) |
| Designing for iPadOS | Large display, combined input modes, multitasking, macOS transition | [Platform guides](./references/platform-guides.md) |
| Designing for macOS | Menu bar, resizable windows, precision input, keyboard shortcuts, personalization | [Platform guides](./references/platform-guides.md) |
| Designing for tvOS | Focus system, Siri Remote, 10-foot legibility, multiuser sign-in | [Platform guides](./references/platform-guides.md) |
| Designing for visionOS | Shared/Full Space, passthrough, eyes + hands, immersion levels, comfort | [Platform guides](./references/platform-guides.md) |
| Designing for watchOS | Glanceable single-screen interactions, Digital Crown, complications, Always On | [Platform guides](./references/platform-guides.md) |
| Designing for games | Fast start, per-platform text/button/interaction specs, accessibility, Game Center | [Platform guides](./references/platform-guides.md) |
| Designing for iPhone Duo | Dual displays, device poses, reserved regions, vertical controls, arrangement views | [Platform guides](./references/platform-guides.md) |
| Accessibility | Vision/hearing/mobility/speech/cognitive guidance; text size, contrast, control size tables | [Accessibility and inclusion](./references/accessibility-inclusion.md) |
| Inclusion | Welcoming language, gender identity, avoiding stereotypes, localization readiness | [Accessibility and inclusion](./references/accessibility-inclusion.md) |
| Privacy | Minimal data requests, purpose strings, pre-alert screens, tracking rules, location button, data protection | [Privacy](./references/privacy.md) |
| Color | System/dynamic colors, Liquid Glass color, wide color, per-platform palettes | [Color and materials](./references/color-materials.md) |
| Dark Mode | Base/elevated backgrounds, adaptive colors, 4.5:1 / 7:1 contrast, icons and text in both modes | [Color and materials](./references/color-materials.md) |
| Materials | Liquid Glass regular/clear variants, 35% dimming layer, standard materials, vibrancy levels | [Color and materials](./references/color-materials.md) |
| Typography | SF/NY fonts, text styles, Dynamic Type spec tables per platform, tracking, custom fonts | [Typography and icons](./references/typography-icons.md) |
| SF Symbols | Rendering modes, variable color, weights/scales, variants, animations, custom symbols | [Typography and icons](./references/typography-icons.md) |
| Icons | Simplified consistent glyphs, optical alignment, standard action symbols, macOS document icons | [Typography and icons](./references/typography-icons.md) |
| App icons | Layer design, shapes, appearance variants, per-platform size specs | [Typography and icons](./references/typography-icons.md) |
| Layout | Visual hierarchy, adaptability, size classes, safe areas, per-platform margins | [Layout and spatial](./references/layout-spatial.md) |
| Spatial layout | Field of view, depth, dynamic vs fixed scale, visionOS-only | [Layout and spatial](./references/layout-spatial.md) |
| Right to left | Text alignment, numerals, control flipping, images and icons, +2 pt script balancing | [Layout and spatial](./references/layout-spatial.md) |
| Motion | Purposeful animation, feedback, 30–60 fps games, visionOS comfort (0.2 Hz) | [Motion, images, immersive](./references/motion-images-immersive.md) |
| Images | Scale factors, formats, tvOS layered images/parallax, visionOS spatial photos, watchOS scaling | [Motion, images, immersive](./references/motion-images-immersive.md) |
| Immersive experiences | Shared/Full Space, immersion styles (mixed/progressive/full), 1.5 m boundary, environments | [Motion, images, immersive](./references/motion-images-immersive.md) |
| Writing | Voice and tone, action-oriented labels, error messages, per-device copy | [Writing and branding](./references/writing-branding.md) |
| Branding | Accent color restraint, custom fonts, familiar components, trademark rules | [Writing and branding](./references/writing-branding.md) |

## How to use

- Locate a topic in the index above and open the reference file; each topic starts with a one-sentence definition, then condensed best practices.
- Check the "Platform considerations" subsection of each topic for per-platform differences and "not supported in X" statements before applying guidance cross-platform.
- Numeric specifications live in the tables (Dynamic Type sizes, minimum text/control sizes, contrast ratios, icon dimensions, margins); read values from the table for the platform you target, not from prose.
- For anything not covered here — full tracking tables, RGB values of system colors, artwork, or change history — consult the `> Source:` URLs at the top of each reference file.
