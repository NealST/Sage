> Source: https://developer.apple.com/design/human-interface-guidelines/typography
> Source: https://developer.apple.com/design/human-interface-guidelines/sf-symbols
> Source: https://developer.apple.com/design/human-interface-guidelines/icons
> Source: https://developer.apple.com/design/human-interface-guidelines/app-icons

## Typography
Your typographic choices help you display legible text, convey an information hierarchy, communicate important content, and express your brand or style.

### Best practices
**Ensuring legibility**
- Use font sizes most people can read easily at various viewing distances (defaults/minimums below, for custom and system fonts); with a thin font weight, aim larger than recommended.
- Test legibility in different contexts; if text is hard to read, increase size, increase contrast, or use legibility-optimized typefaces like the system fonts.
- Avoid light font weights: prefer Regular, Medium, Semibold, or Bold; avoid Ultralight, Thin, and Light, especially at small sizes.

**Conveying hierarchy**
- Adjust font weight, size, and color to emphasize important information; maintain relative hierarchy as text sizes change.
- Minimize the number of typefaces you use — mixing too many obscures hierarchy and hinders readability.
- Prioritize important content when text size changes: not every word must scale (e.g., tab titles and transient hit-damage values don't need to grow with content).

**System fonts**
- San Francisco (SF) — SF Pro, SF Compact, SF Arabic, SF Armenian, SF Georgian, SF Hebrew, SF Mono; rounded variants coordinate with soft/rounded UI. New York (NY) is the serif family. Download from Apple; variable font format with dynamic optical sizes (no discrete Text/Display optical sizes needed).
- Weights range Ultralight to Black; SF also has Condensed and Expanded widths; SF Symbols match weights exactly.
- Prefer built-in text styles (weight + size + leading combinations like body and headline) — they scale with Dynamic Type and larger accessibility sizes.
- Modify text styles with symbolic traits if needed (bold trait, leading adjustments); use loose leading for wide columns/long passages, tight leading for height-constrained rows — but avoid tight leading with 3+ lines of text.
- Don't embed system fonts: use Font.Design constants (e.g., Font.Design.default, Font.Design.serif).
- Adjust tracking in interface mockups only — a running app's system font adjusts tracking dynamically at every point size.

**Custom fonts**
- Make sure custom fonts are legible at various distances and conditions (follow the minimum sizes in Specifications).
- Implement accessibility features for custom fonts: Dynamic Type and Bold Text must work as with system fonts (use Apple's Unity plug-ins in Unity-based games, or provide other text-size adjustment).

**Dynamic Type** (iOS, iPadOS, tvOS, visionOS, watchOS; not macOS)
- Make your layout adapt to all font sizes; verify legibility with Larger Accessibility Text Sizes on.
- Scale meaningful interface icons with font size (SF Symbols scale automatically).
- Minimize text truncation as font size increases: aim to show as much useful text at the largest accessibility size as at the largest standard size; avoid truncation in scrollable regions unless a detail view exists; configure labels to use as many lines as needed.
- Adjust layout at large sizes: stack text above secondary items instead of inline; reduce column count as size increases.
- Keep information hierarchy consistent regardless of font size (keep primary elements at top).

### Platform considerations
- iOS/iPadOS: SF Pro is the system font; NY also available.
- macOS: SF Pro is the system font; NY available for Mac Catalyst apps; Dynamic Type isn't supported. Use dynamic system font variants to match standard controls: controlContentFont(ofSize:), labelFont(ofSize:), menuFont(ofSize:), menuBarFont(ofSize:), messageFont(ofSize:), paletteFont(ofSize:), titleBarFont(ofSize:), toolTipsFont(ofSize:), userFont(ofSize:), userFixedPitchFont(ofSize:), boldSystemFont(ofSize:), systemFont(ofSize:).
- tvOS: SF Pro is the system font; NY also available.
- visionOS: SF Pro is the system font; specify text styles when using NY. Uses bolder Dynamic Type body/title styles; adds Extra Large Title 1 and 2 for wide editorial layouts. Prefer 2D text (depth hurts readability); test legibility at different scales; maximize text/background contrast (system default text is white); bold text with no background instead of adding shadows; billboard text attached to 3D objects so it faces the wearer (rotate around y-axis).
- watchOS: SF Compact is the system font; NY also available; complications use SF Compact Rounded.

### Specifications

| Platform | Default text size | Minimum text size |
|---|---|---|
| iOS, iPadOS | 17 pt | 11 pt |
| macOS | 13 pt | 10 pt |
| tvOS | 29 pt | 23 pt |
| visionOS | 17 pt | 12 pt |
| watchOS | 16 pt | 12 pt |

Emphasized variants use symbolic traits (bold() in SwiftUI; traitBold in UIFontDescriptor). Tables below show each platform's default size level and first accessibility level; full per-level tables (xSmall–xxxLarge, AX1–AX5 on iOS, AX1–AX3 on watchOS) are at the source URL and in Apple Design Resources.

**iOS, iPadOS Dynamic Type sizes (Large, default)**

| Style | Weight | Size (pt) | Leading (pt) | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 31 | 38 | Bold |
| Title 1 | Regular | 25 | 31 | Bold |
| Title 2 | Regular | 19 | 24 | Bold |
| Title 3 | Regular | 17 | 22 | Semibold |
| Headline | Semibold | 14 | 19 | Semibold |
| Body | Regular | 14 | 19 | Semibold |
| Callout | Regular | 13 | 18 | Semibold |
| Subhead | Regular | 12 | 16 | Semibold |
| Footnote | Regular | 12 | 16 | Semibold |
| Caption 1 | Regular | 11 | 13 | Semibold |
| Caption 2 | Regular | 11 | 13 | Semibold |

**iOS, iPadOS larger accessibility sizes (AX1)**

| Style | Weight | Size (pt) | Leading (pt) | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 44 | 52 | Bold |
| Title 1 | Regular | 38 | 46 | Bold |
| Title 2 | Regular | 34 | 41 | Bold |
| Title 3 | Regular | 31 | 38 | Semibold |
| Headline | Semibold | 28 | 34 | Semibold |
| Body | Regular | 28 | 34 | Semibold |
| Callout | Regular | 26 | 32 | Semibold |
| Subhead | Regular | 25 | 31 | Semibold |
| Footnote | Regular | 23 | 29 | Semibold |
| Caption 1 | Regular | 22 | 28 | Semibold |
| Caption 2 | Regular | 20 | 25 | Semibold |

**macOS built-in text styles**

| Text style | Weight | Size (pt) | Line height (pt) | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 26 | 32 | Bold |
| Title 1 | Regular | 22 | 26 | Bold |
| Title 2 | Regular | 17 | 22 | Bold |
| Title 3 | Regular | 15 | 20 | Semibold |
| Headline | Bold | 13 | 16 | Heavy |
| Body | Regular | 13 | 16 | Semibold |
| Callout | Regular | 12 | 15 | Semibold |
| Subheadline | Regular | 11 | 14 | Semibold |
| Footnote | Regular | 10 | 13 | Semibold |
| Caption 1 | Regular | 10 | 13 | Medium |
| Caption 2 | Medium | 10 | 13 | Semibold |

**tvOS built-in text styles**

| Text style | Weight | Size (pt) | Leading (pt) | Emphasized |
|---|---|---|---|---|
| Title 1 | Medium | 76 | 96 | Bold |
| Title 2 | Medium | 57 | 66 | Bold |
| Title 3 | Medium | 48 | 56 | Bold |
| Headline | Medium | 38 | 46 | Bold |
| Subtitle 1 | Regular | 38 | 46 | Medium |
| Callout | Medium | 31 | 38 | Bold |
| Body | Medium | 29 | 36 | Bold |
| Caption 1 | Medium | 25 | 32 | Bold |
| Caption 2 | Medium | 23 | 30 | Bold |

**watchOS Dynamic Type sizes (Large, default)**

| Style | Weight | Size (pt) | Leading (pt) | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 30 | 32.5 | Bold |
| Title 1 | Regular | 28 | 30.5 | Semibold |
| Title 2 | Regular | 24 | 26.5 | Semibold |
| Title 3 | Regular | 17 | 19.5 | Semibold |
| Headline | Semibold | 14 | 16.5 | Semibold |
| Body | Regular | 14 | 16.5 | Semibold |
| Caption 1 | Regular | 13 | 15.5 | Semibold |
| Caption 2 | Regular | 12 | 14.5 | Semibold |
| Footnote 1 | Regular | 11 | 13.5 | Semibold |
| Footnote 2 | Regular | 10 | 12.5 | Semibold |

**watchOS larger accessibility sizes (AX1)**

| Style | Weight | Size (pt) | Leading (pt) | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 44 | 46.5 | Bold |
| Title 1 | Regular | 42 | 44.5 | Semibold |
| Title 2 | Regular | 34 | 41 | Semibold |
| Title 3 | Regular | 24 | 26.5 | Semibold |
| Headline | Semibold | 21 | 23.5 | Semibold |
| Body | Regular | 21 | 23.5 | Semibold |
| Caption 1 | Regular | 18 | 20.5 | Semibold |
| Caption 2 | Regular | 17 | 19.5 | Semibold |
| Footnote 1 | Regular | 16 | 18.5 | Semibold |
| Footnote 2 | Regular | 15 | 17.5 | Semibold |

**Tracking values (SF Pro; identical for iOS/iPadOS/visionOS, macOS, and tvOS)** — for interface mockups; representative sizes:

| Size (pt) | Tracking (1/1000 em) | Tracking (pt) |
|---|---|---|
| 6 | +41 | +0.24 |
| 10 | +12 | +0.12 |
| 12 | 0 | 0.0 |
| 14 | -11 | -0.15 |
| 17 | -26 | -0.43 |
| 20 | -23 | -0.45 |
| 24 | +3 | +0.07 |
| 28 | +14 | +0.38 |
| 34 | +12 | +0.40 |
| 40 | +10 | +0.37 |
| 48 | +8 | +0.35 |
| 56 | +6 | +0.30 |
| 64 | +4 | +0.22 |
| 72 | +2 | +0.14 |
| 80 | 0 | 0 |
| 96 | 0 | 0 |

watchOS (SF Compact) tracking differs: +50 (1/1000 em) at 6 pt, 0 at 16 pt, increasingly negative up to -28 / -2.62 pt at 96 pt — full tables at the source URL.

### Resources
Font.Design (SwiftUI), leading(_:) (SwiftUI), numberOfLines, isAccessibilityCategory, Fonts (AppKit), Text input and output (SwiftUI), Apple's Unity plug-ins

## SF Symbols
SF Symbols provides thousands of consistent, highly configurable symbols that integrate seamlessly with the San Francisco system font, automatically aligning with text in all weights and sizes.

### Best practices
**Rendering modes** (symbols are organized into layers: primary, secondary, tertiary)
- Monochrome: one color for all layers.
- Hierarchical: one color, varying opacity per layer — use for depth/emphasis.
- Palette: two or more colors, one per layer.
- Multicolor: intrinsic colors that enhance meaning (e.g., green leaf, red trash.slash).
- Use system colors so symbols adapt to accessibility settings, vibrancy, and Dark Mode; verify the chosen rendering mode works at every size and background (the automatic setting uses a symbol's preferred mode).
- Gradients (SF Symbols 7+): smooth linear gradient from a single source color, available in all rendering modes, best at larger sizes.

**Variable color**
- Represents a characteristic that changes over time (capacity, strength) by coloring layers as a value crosses thresholds between 0 and 100%; layers can opt out.
- Use variable color to communicate change, not depth (use Hierarchical for depth).

**Weights and scales**
- Nine weights (ultralight to black) matching SF font weights for precise weight matching with adjacent text.
- Three scales — small, medium (default), large — defined relative to the SF cap height; scale adjusts emphasis without disrupting weight matching.

**Design variants**
- Outline (most common; resembles text), fill (solid areas, more emphasis — good for iOS tab bars, swipe actions, accent-colored selection), slash (unavailable), enclosed (circle/square/rectangle, more legible at small sizes).
- Language- and script-specific variants (Latin, Arabic, Hebrew, Hindi, Thai, Chinese, Japanese, Korean, Cyrillic, Devanagari, Indic numerals) adapt automatically to device language.
- The displaying view often determines variant (iOS tab bar prefers fill; toolbar takes outline).

**Animations** (all symbols, all modes/weights/scales, and custom symbols; configurable playback)
- Available: Appear, Disappear, Bounce, Scale, Pulse, Variable color (cumulative/iterative; open- vs closed-loop layer arrangement), Replace (down-up, up-up, off-up), Magic Replace (smart transition between related shapes; falls back to down-up), Wiggle, Breathe (opacity + size), Rotate (whole symbol or by layer), Draw On / Draw Off (SF Symbols 7+).
- Apply animations judiciously; ensure each serves a clear purpose; use them to communicate efficiently; consider your app's tone.

**Custom symbols**
- Export a similar symbol's template and modify it; match system symbols in detail, optical weight, alignment, position, perspective; keep it simple, recognizable, inclusive, directly related to its meaning.
- Annotate layers with colors or hierarchical levels; assign negative side margins for optical alignment (naming pattern like "left-margin-Regular-M").
- Annotate layers to animate by layer (Z-order controls color application order); test all animation presets; draw with whole shapes + erase-layer offset paths for expected motion.
- Use the component library for common variants instead of building enclosures/badges yourself; provide alternative text labels (VoiceOver).
- Don't replicate Apple products; don't customize symbols badged as depicting Apple products/features.

### Resources
Symbols framework, SymbolEffect, renderingMode(_:), imageScale(_:), UIImage.SymbolScale, NSImage.SymbolConfiguration, SF Symbols app

## Icons
An effective icon (interface icon or glyph) is a graphic asset that expresses a single concept in ways people instantly understand.

Unlike app icons, interface icons use streamlined shapes and touches of color; they can be custom or SF Symbols. Both use black and clear colors to define shapes; the system applies other colors.

### Best practices
- Create a recognizable, highly simplified design with familiar visual metaphors directly related to the action or content.
- Maintain visual consistency across all interface icons: same size, level of detail, stroke thickness, and perspective; adjust dimensions per icon as needed for visual weight.
- Match the weights of icons and adjacent text unless emphasizing one.
- Add padding to asymmetric icons to achieve optical alignment (geometric centering can look unbalanced).
- Provide a selected-state version only if necessary — system components update selected appearance automatically.
- Use inclusive images: gender-neutral figures, recognizable across cultures.
- Include text only when essential; localize displayed characters; flip icons that suggest reading direction for RTL.
- Use vector format (PDF or SVG) for custom icons so the system scales them; PNG requires multiple versions.
- Provide alternative text labels for custom icons (VoiceOver).
- Avoid replicas of Apple hardware products; use Apple Design Resources or SF Symbols images instead.

**Standard icons (SF Symbols) for common actions**
- Editing: scissors (Cut), document.on.document (Copy), document.on.clipboard (Paste), checkmark (Done/Save), xmark (Cancel/Close), trash (Delete), arrow.uturn.backward (Undo), arrow.uturn.forward (Redo), square.and.pencil (Compose), plus.square.on.square (Duplicate), pencil (Rename), folder (Move to/Folder), paperclip (Attach), plus (Add), ellipsis (More)
- Selection: checkmark.circle (Select), xmark (Deselect), trash (Delete)
- Text formatting: textformat.superscript, textformat.subscript, bold, italic, underline, text.alignleft, text.aligncenter, text.justify, text.alignright
- Search: magnifyingglass (Search), text.page.badge.magnifyingglass (Find), line.3.horizontal.decrease (Filter)
- Sharing: square.and.arrow.up (Share), printer (Print)
- Users: person.crop.circle (Account/User/Profile)
- Ratings: hand.thumbsdown (Dislike), hand.thumbsup (Like)
- Layers: square.3.layers.3d.top.filled (Bring to Front), square.3.layers.3d.bottom.filled (Send to Back), square.2.layers.3d.top.filled (Bring Forward), square.2.layers.3d.bottom.filled (Send Backward)
- Other: alarm, archivebox, calendar

### Platform considerations
- macOS document icons: supply background fill, center image, and/or text — the system composites them onto the folded-corner shape (or auto-generates from your app icon + extension). Design simple images legible at 16x16 px; reduce detail in small versions; keep important content out of the top-right corner (folded corner). Background fill sizes: 512, 256, 128, 32, 16 px @1x (2x doubles). Center image = half the canvas (e.g., 16x16 for a 32x32 icon), sizes 256, 128, 32, 16 px @1x; keep ~80% of the image within a 10% margin. Supply a short descriptive term instead of an unfamiliar extension (auto-capitalized, auto-scaled).

### Resources
SF Symbols, VoiceOver, Parallax Previewer (tvOS/visionOS)

## App icons
A unique, memorable icon expresses your app's or game's purpose and personality and helps people recognize it at a glance.

### Best practices
**Layer design**
- iOS, iPadOS, macOS, watchOS: background layer + one or more foreground layers coalescing into dimensionality with Liquid Glass attributes (specular highlights, refraction, translucency) that adapt to size, platform, and system version. Assemble in Icon Composer (Xcode).
- tvOS: two to five layers create dynamism; the icon elevates, sways, and illuminates on focus (parallax). Add layers directly to an image stack in Xcode.
- visionOS: background + one or two top layers form a 3D object that subtly expands when viewed; system adds shadows and embossing via the alpha channel.
- Prefer clearly defined edges in foreground layers (no soft/feathered edges); vary opacity for depth and liveliness; design a background that stands out and emphasizes foreground content (solid color or gradient; imported backgrounds must be full-bleed and opaque); prefer vector graphics (SVG/PDF) for layers; PNG for mesh gradients and raster art.

**Icon shape**
- iOS, iPadOS, macOS: square layers, system applies rounded-corner masking. tvOS: rectangular layers, rounded corners. visionOS, watchOS: square layers, circular masking. Never pre-mask — it damages specular highlights and makes edges jagged.
- Keep primary content centered to avoid truncation (especially visionOS/watchOS); use the grids in the app icon production templates.

**Design**
- Embrace simplicity: one concept capturing the essence, minimal shapes, simple background; details get lost at small sizes.
- Provide a visually consistent design across all platforms.
- Consider filled, overlapping shapes for depth; include text only when essential (text doesn't support accessibility or localization; avoid nonessential words like "Watch"/"Play"/"New"; in tvOS keep text above other layers so parallax doesn't crop it).
- Prefer illustrations to photos; avoid replicating UI components or screenshots; avoid extremely thin lines and sharp corners.
- Don't use replicas of Apple hardware products.

**Visual effects**
- Let the system handle blurring, highlights, shadows, bevels, glows; custom static effects conflict with dynamic system effects — if used, test carefully in Icon Composer/Device Hub/on device.
- Group layers to apply effects at group level with extra Liquid Glass customization.

**Appearances**
- iOS, iPadOS, macOS: people can choose default, dark, clear, or tinted Home Screen icons; design variants for each (the system generates missing ones).
- Keep core visual features the same across appearances; don't swap elements per variant.
- Dark icons are subdued, clear/tinted more so — use your light icon as the basis, complementary colors, color backgrounds for contrast; the icon must be recognizable in every variant.
- Alternate app icons (iOS, iPadOS, tvOS, compatible visionOS apps): each must stay closely related to your content; alternates need their own dark, clear, and tinted variants; all are subject to app review.

### Platform considerations
- tvOS: keep a safe zone — the system crops edges on focus; the safe zone varies with image size, layer depth, and motion; foreground layers crop more than background.
- visionOS: avoid shapes that look like holes or concave areas in the background layer (shadows and highlights make them stand out).
- watchOS: avoid black backgrounds — lighten them so the icon doesn't blend into the display.

### Specifications

| Platform | Layout shape | After masking | Layout size | Style | Appearances |
|---|---|---|---|---|---|
| iOS, iPadOS, macOS | Square | Rounded rectangle | 1024x1024 px | Layered | Default, dark, clear light/dark, tinted light/dark |
| tvOS | Rectangle (landscape) | Rounded rectangle | 800x480 px | Layered (Parallax) | N/A |
| visionOS | Square | Circular | 1024x1024 px | Layered (3D) | N/A |
| watchOS | Square | Circular | 1088x1088 px | Layered | N/A |

The system automatically scales icons for smaller locations (Settings, notifications). Supported color spaces: sRGB, Gray Gamma 2.2, Display P3 (iOS, iPadOS, macOS, tvOS, watchOS only).

### Resources
Icon Composer, asset catalogs, Parallax Previewer and Parallax Exporter plug-in, App Review Guidelines
