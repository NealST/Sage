> Source: https://developer.apple.com/design/human-interface-guidelines/color
> Source: https://developer.apple.com/design/human-interface-guidelines/dark-mode
> Source: https://developer.apple.com/design/human-interface-guidelines/materials

## Color
Judicious use of color can enhance communication, evoke your brand, provide visual continuity, communicate status and feedback, and help people understand information.

### Best practices
- Avoid using the same color to mean different things; use color consistently, especially for status or interactivity.
- Make all colors work in light, dark, and increased-contrast contexts: use system colors (variants already defined), or supply light + dark variants and an increased-contrast option for each custom color; provide both light and dark colors even in a single-appearance app to support Liquid Glass adaptivity.
- Test your color scheme under varied lighting (colors look darker/muted in bright light, brighter/saturated in dim light; in visionOS, surrounding objects affect color) and on different devices (True Tone, HD/4K TVs, color profiles like P3 and sRGB).
- Consider how artwork and translucency affect nearby colors; adjust nearby colors to maintain visual continuity (e.g., Maps switches schemes between map and satellite mode).
- If people can choose colors, prefer system-provided color controls (consistent experience, colors accessible from any app).

### Inclusive color
- Never rely on color alone to differentiate objects, indicate interactivity, or communicate essential information — provide the same information via text labels or glyph shapes.
- Avoid color combinations that are hard to perceive (insufficient contrast, indistinguishable to color-blind people).
- Consider culture-specific color meanings per locale (red = danger in some cultures, positive in others; Stocks uses green for gains in English, red in Chinese).

### System colors
- Don't hard-code system color values in your app — documented values fluctuate between releases; use APIs like Color.
- Dynamic system colors are semantically defined by purpose; don't redefine their semantic meanings (e.g., never use separator as a text color).

### Liquid Glass color
- By default Liquid Glass has no inherent color and takes color from content directly behind it; color can be applied to elements (colored/stained glass) or to symbols/text on the material.
- Apply color sparingly: reserve it for elements that benefit from emphasis (status indicators, primary actions); emphasize primary actions with background color (like the system's prominent Done button), not by coloring labels; don't color the background of multiple controls.
- On smaller elements (toolbars, tab bars), the system adapts Liquid Glass between light and dark appearance; symbols/text default to monochrome (darker over light content, lighter over dark); larger elements like sidebars are more opaque for legibility.
- With colorful backgrounds, prefer monochromatic toolbars/tab bars or an accent color with sufficient differentiation; in monochromatic apps, the brand accent color can be effective.
- Avoid overlapping similar colors between content and controls; ensure the resting state of scrolling content stays legible.

### Color management
- Apply color profiles to images (sRGB is accurate on most displays).
- Use wide color (Display P3, 16 bits per pixel per channel, PNG export) on compatible displays for richer photos, videos, and status indicators; design on a wide color display.
- Provide color-space-specific image/color variations via the asset catalog when similar P3 colors or gradients clip on sRGB displays.

### Platform considerations
- iOS/iPadOS: two dynamic background sets — system (systemBackground/secondary/tertiary) and grouped (systemGroupedBackground/...); use grouped for grouped table views. Primary = overall view, secondary = content grouped within the view, tertiary = content grouped within secondary. Foreground dynamic colors: label, secondaryLabel, tertiaryLabel, quaternaryLabel, placeholderText, separator, opaqueSeparator, link (UIKit).
- macOS: dynamic system colors include controlAccentColor, controlBackgroundColor, controlColor, controlTextColor, currentControlTint, disabledControlTextColor, alternatingContentBackgroundColors, selectedContentBackgroundColor, selectedControlColor/TextColor, selectedMenuItemTextColor, selectedTextBackgroundColor/Color, separatorColor, shadowColor, labelColor, secondaryLabelColor, tertiaryLabelColor, quaternaryLabelColor, linkColor, placeholderTextColor, textColor, textBackgroundColor, underPageBackgroundColor, windowBackgroundColor, windowFrameTextColor, highlightColor, findHighlightColor, gridColor, headerTextColor, keyboardFocusIndicatorColor, alternateSelectedControlTextColor, unemphasized variants. App accent color (macOS 11+) customizes buttons, selection highlighting, and sidebar icons when the system accent is multicolor; fixed-color sidebar icons aren't overridden.
- tvOS: choose a limited palette coordinating with your app logo; never use color alone to indicate focus (subtle scaling and responsive animation denote focus).
- visionOS: use color sparingly, especially on glass (surroundings show through); prefer color in bold text and large areas; in fully immersive experiences keep brightness balanced — avoid bright objects on very dark backgrounds, especially flashing or moving ones.
- watchOS: use background color to support content or add information (e.g., Activity ring colors), not decoration; avoid full-screen background colors in long-lived views (workout, audio); people may prefer tinted-mode graphic complications over full color.

### Specifications (system color APIs)
| Color | SwiftUI API |
|---|---|
| Red / Orange / Yellow / Green / Mint / Teal / Cyan / Blue / Indigo / Purple / Pink / Brown | red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown |

visionOS system colors use the default dark color values. iOS/iPadOS grays (UIKit): systemGray, systemGray2, systemGray3, systemGray4, systemGray5, systemGray6 (SwiftUI equivalent of systemGray is gray).

### Resources
Color (SwiftUI), UIColor (UIKit), Color (AppKit), ColorPicker, UIWhitePointAdaptivityStyle

## Dark Mode
Dark Mode is a systemwide appearance setting that uses a dark color palette to provide a comfortable viewing experience tailored for low-light environments.

### Best practices
- Avoid offering an app-specific appearance setting — it makes more work for people and your app may seem broken when it ignores the systemwide choice.
- Look good in both modes, including the Auto setting that switches while your app runs.
- Test legibility in both modes, including Dark Mode with Increase Contrast and Reduce Transparency on (separately and together).
- In rare cases, a permanently dark appearance can make sense (e.g., immersive media viewing, like Stocks) so the UI recedes.

### Dark Mode colors
- Dark palette: dimmer backgrounds, brighter foregrounds; not necessarily inversions of light counterparts.
- Embrace adaptive colors: use semantic colors (labelColor, controlColor in macOS; separator in iOS/iPadOS) or add a Color Set asset with bright/dim variants; avoid hard-coded values.
- Aim for sufficient contrast in all appearances: at minimum 4.5:1 between foreground and background colors; strive for 7:1 for custom colors, especially small text.
- Soften white backgrounds of content images so they don't glow in a dark context.

### Icons and images
- Use SF Symbols wherever possible — they adapt automatically (tint with dynamic colors or add vibrancy).
- Design separate interface icons for light and dark appearances if necessary (e.g., a border for contrast on dark backgrounds).
- Make full-color images look good in both appearances: use one asset when possible, or modify/create separate assets combined in an asset catalog.

### Text
- Use system-provided label colors (primary, secondary, tertiary, quaternary) — they adapt automatically.
- Use system views for text fields and text views so vibrancy and contrast adjust automatically.

### Platform considerations
- Dark Mode isn't supported in visionOS or watchOS.
- iOS/iPadOS: two background sets — base (dimmer, recedes) and elevated (brighter, advances) — enhance perceived depth when dark interfaces layer; background color switches from base to elevated automatically for foreground interfaces (popovers, modal sheets) and separates apps in multitasking and windows; prefer system background colors.
- macOS: with the graphite accent color, window backgrounds pick up color from the desktop picture (desktop tinting); include transparency in custom component backgrounds (only components with a visible background/bezel, only in neutral states) so they harmonize with tinting.

### Resources
Color (SwiftUI), asset catalogs (Color Set), SF Symbols

## Materials
A material is a visual effect that creates a sense of depth, layering, and hierarchy between foreground and background elements.

Two types: Liquid Glass (dynamic material unifying the design language, for controls and navigation floating above content) and standard materials (visual differentiation within the content layer).

### Liquid Glass
- Forms a distinct functional layer for controls and navigation (tab bars, sidebars); content scrolls and peeks through beneath it.
- Don't use Liquid Glass in the content layer (e.g., app backgrounds — use standard materials); exception: transient interactive controls in the content layer (sliders, toggles) take on Liquid Glass when activated.
- Use Liquid Glass effects sparingly on custom controls; standard components pick it up automatically; limit custom usage to the most important functional elements.
- Two variants: regular (blurs and adjusts luminosity of background content; scroll edge effects further enhance legibility; most system components; use for legibility issues or text-heavy components like alerts, sidebars, popovers) and clear (highly translucent, prioritizes underlying content visibility; for components floating above media like photos and videos).
- Dimming layer behind clear Liquid Glass: add a dark dimming layer of 35% opacity if the underlying content is bright; skip it if content is sufficiently dark or you use standard AVKit media playback controls.

### Standard materials
- Use standard materials and effects (blur, vibrancy, blending modes) to convey structure in the content layer beneath Liquid Glass.
- Choose materials based on semantic meaning and recommended usage, not the apparent color they impart (system settings can change appearance).
- Use system-defined vibrant colors on top of materials to guarantee legibility.
- Contrast/separation trade-off: thicker, more opaque materials give better contrast for fine features; thinner, more translucent materials preserve background context.

### Platform considerations
- iOS/iPadOS: four standard materials for the content layer — ultraThin, thin, regular (default), thick. Vibrant label colors: label (default), secondaryLabel, tertiaryLabel, quaternaryLabel (avoid quaternary on thin/ultraThin — contrast too low); fills: fill (default), secondaryFill, tertiaryFill; one default separator vibrancy.
- macOS: several standard materials with designated purposes (NSVisualEffectView.Material) and vibrant versions of all system colors; choose when to allow vibrancy in custom views; choose a background blending mode (behind window or within window).
- tvOS: Liquid Glass appears in navigation elements and system experiences (Top Shelf, Control Center); image views and buttons adopt Liquid Glass on focus. Standard materials define structure in the content layer:

| Material | Recommended for |
|---|---|
| ultraThin | Full-screen views that require a light color scheme |
| thin | Overlay views that partially obscure content, light color scheme |
| regular | Overlay views that partially obscure content |
| thick | Overlay views that partially obscure content, dark color scheme |

- visionOS: windows use the unmodifiable system material glass, which adapts to the luminance of objects behind it (no separate Dark Mode); prefer translucency to opaque colors (opacity blocks people's view and constrains them); use thin material for interactive elements (buttons, selected items), regular to visually separate sections (sidebars, grouped tables), thick to create a dark, visually distinct element. Vibrancy is applied to text, symbols, and fills: label (standard text), secondaryLabel (footnotes, subtitles), tertiaryLabel (inactive elements not needing high legibility).
- watchOS: use materials to provide context in full-screen modal views (layers orient people and distinguish controls); don't remove or replace default material backgrounds for modal sheets.

### Resources
glassEffect(_:in:) (SwiftUI), Material (SwiftUI), UIVisualEffectView (UIKit), NSVisualEffectView (AppKit), UIVibrancyEffectStyle
