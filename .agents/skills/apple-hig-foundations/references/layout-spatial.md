> Source: https://developer.apple.com/design/human-interface-guidelines/layout
> Source: https://developer.apple.com/design/human-interface-guidelines/spatial-layout
> Source: https://developer.apple.com/design/human-interface-guidelines/right-to-left

## Layout
A consistent layout that adapts across display sizes, orientations, and multitasking configurations helps people understand and enjoy your app or game on all their devices.

### Best practices
**Visual hierarchy**
- Order content by relative importance: reading order is top to bottom, leading to trailing — put the most important items near the top and leading side; prefer standard system components to support RTL automatically.
- Align elements for scannability and use indentation to convey subordination; people assume aligned items are related.
- Group related items using negative space, container shapes, or separator lines.
- Use progressive disclosure (disclosure triangles, menus, nested views, scrollable sections) to reduce initially displayed content.
- Differentiate controls from content: use the Liquid Glass material and scroll edge effects instead of solid/semi-opaque control backgrounds; extend full-screen background content beneath sidebars, toolbars, and tab bars.
- If scaling a background image would hide content behind components, use a background extension effect (flips and blurs the image beneath adjacent components).

**Adaptability**
- Handle: regular/compact horizontal and vertical size classes; different screen sizes, orientations, aspect ratios; system features like the Dynamic Island; external displays, Display Zoom, resizable windows on iPad and Mac; text-size changes; locale-based features (layout direction, date/time/number formatting, font variation, text length). Use SwiftUI or Auto Layout.
- Design a layout that adapts gracefully and consistently: respect system-defined safe areas, margins, and guides; specify layout modifiers; even orientation-locked apps should resize well.
- Be prepared for text-size changes: support Dynamic Type (stack views vertically, grow container heights, allow multi-line rows); use Apple's accessibility plug-in for Unity games.
- Preview on multiple devices, size classes, localizations, and text sizes; test the largest and smallest layouts first; use Device Hub to check clipping (iPad resizing, iPhone Mirroring on Mac).
- Scale background artwork to fill the screen when the aspect ratio changes (don't letterbox); artwork may need to extend beyond a standard display's aspect ratio for very wide/short or tall/narrow windows.

**Size classes** (iOS and iPadOS)
- Each dimension is compact or regular; the system sets them from device type, window configuration, and multitasking state (full screen, Slide Over, iPhone Mirroring to Mac).
- Determine layout from size classes, not device type or orientation — orientation/idiom don't tell you available space; size classes also let apps adapt to freely resized windows.
- Consider all four combinations (compact/regular x horizontal/vertical).
- Keep functionality the same as size classes change; vary only how much functionality is visible (e.g., tab bar to sidebar, overflow menu exposure); keep the layout recognizable and familiar to the platform (idiom doesn't change when resizing).

**Guides and safe areas**
- Use layout guides (system-defined or custom) to position, align, and space content with standard margins and optimal text width.
- Respect safe areas (area not covered by hardware features or views like toolbars, tab bars, status bar) so system UI and features like the Dynamic Island don't obstruct content.

### Platform considerations
- macOS: avoid placing controls or critical information at the bottom of a window (people often move windows below the screen); avoid content behind the camera housing at the top edge.
- tvOS: inset primary content 60 pt from the top and bottom of the screen and 80 pt from the sides (visible regardless of overscan cropping); add padding between focusable elements (they grow on focus). Two-column grid: unfocused content width 860 pt, horizontal spacing 40 pt, minimum vertical spacing 100 pt; add vertical spacing around titled rows; keep spacing consistent; keep partially hidden offscreen content symmetrical. (UIKit collection view flow layout determines column count automatically.)
- visionOS: support resizing (standard behavior); keep content horizontally centered at very large sizes; optionally set minimum/maximum sizes (not to prevent resizing); use 3D content sparingly in windows (inset it); use volumes or immersive spaces for large 3D content; display supplemental content in an adjacent window (not an ornament); include enough space around controls — place button centers at least 60 pt apart so the hover effect doesn't obscure content.
- watchOS: no more than two or three controls side by side (three glyph buttons or two text buttons per row); full-width text buttons usually better; support autorotation in views people might show others (showing an image or QR code).

### Resources
UILayoutGuide, NSLayoutGuide, SafeAreaRegions, UserInterfaceSizeClass, UITraitChangeObservable, backgroundExtensionEffect(), UIBackgroundExtensionView, UICollectionViewFlowLayout, isAutorotating, defaultWindowPlacement(_:)

## Spatial layout
Spatial layout techniques help you take advantage of the infinite canvas of Apple Vision Pro and present your content in engaging, comfortable ways.

### Best practices
**Field of view**
- The system doesn't provide information about a person's field of view (it varies with Light Seal configuration and peripheral acuity).
- Center important content within the field of view; avoid distracting motion or bright, high-contrast objects in the periphery during immersive experiences.
- Avoid anchoring content to the wearer's head — it feels confining and obscures passthrough; anchor content in people's space instead.

**Depth**
- The system automatically uses color temperature, reflections, and shadow to convey depth; SwiftUI adds depth effects to views in 2D windows; use RealityKit for 3D objects and volumes (window-like components without a visible frame).
- Provide visual cues that accurately communicate depth — missing or conflicting cues cause visual discomfort.
- Use depth to communicate hierarchy (e.g., a window recedes along the z-axis as a sheet comes forward).
- Avoid adding depth to text — hovering text is hard to read and can cause discomfort.
- Make depth add value: separate large, important elements (tab bar vs window); avoid depth on small objects (a button's symbol standing off its background hurts legibility); people refocus their eyes for each depth change — too many, too fast is tiring.

**Scale**
- Dynamic scale: the system increases a window's scale as it moves away (and decreases it up close) so it appears the same size at all distances — visionOS defines a point as an angle, unlike 2D platforms where a point maps to pixels.
- Fixed scale: an object maintains its scale regardless of distance (appears smaller when farther away, like a physical object). Use sparingly, for noninteractive objects that need realism (e.g., a life-size product).

**General**
- Avoid displaying too many windows (overwhelming, hard to relocate).
- Prioritize standard, indirect gestures (hands stay in view/rest); reserve direct gestures for nearby objects inviting close, brief inspection.
- Rely on the Digital Crown for recentering windows (no app work needed).
- Include enough space around interactive components: place regular-size buttons so their centers are at least 60 pt apart with 16 pt or more between them; never let controls overlap other interactive elements.
- Let people use your app with minimal or no physical movement.
- Place large immersive content rising from the floor on a flat horizontal plane aligned with the floor.

### Platform considerations
- Not supported in iOS, iPadOS, macOS, tvOS, or watchOS (visionOS only).

### Resources
RealityKit, Presenting windows and spaces (visionOS), Positioning and sizing windows (visionOS), Adding 3D content to your app (visionOS)

## Right to left
Support right-to-left (RTL) languages like Arabic and Hebrew by reversing your interface as needed to match the reading direction of the related scripts.

System-provided UI frameworks support RTL by default and system components flip automatically; using system elements and standard layouts may require no changes. Fine-tune only for currencies, numerals, or mathematical symbols across locales.

### Best practices
**Text alignment**
- Adjust text alignment to match interface direction if the system doesn't (left-aligned LTR content becomes right-aligned in RTL).
- Align a paragraph (3+ lines) based on its language, not the current context; one- and two-line blocks align with the reading direction.
- Reverse alignment consistently for all items in a list, including items in a different script.

**Numbers and characters**
- Numerals vary by locale (Hebrew uses Western Arabic numerals; Arabic may use Western or Eastern); number-centric apps should identify the right representation per locale.
- Never reverse the order of digits within a specific number ("541", phone numbers, credit card numbers).
- Reverse the order of numerals showing progress or counting direction (progress bars, sliders, rating controls) — but never flip the numerals themselves.

**Controls**
- Flip controls that show progress between values (sliders, progress indicators), reversing accompanying glyphs/images for start/end values.
- Flip controls that navigate or access items in a fixed order (back buttons point right in RTL; next/previous buttons flip).
- Preserve the direction of controls that refer to actual directions or onscreen areas ("to the right" always points right).
- Visually balance adjacent Latin and RTL scripts: increase the Arabic/Hebrew font size by about 2 pt next to uppercased Latin text.

**Images**
- Avoid flipping photographs, illustrations, and general artwork (meaning changes; copyright risk) — create a new version instead when strongly tied to reading direction.
- Reverse the positions of images when their order is meaningful (chronological, alphabetical, favorites).

**Interface icons**
- SF Symbols provide RTL variants and localized symbols automatically; custom symbols can specify directionality.
- Flip icons representing text or reading direction (left-aligned bars become right-aligned).
- Create localized versions of icons that display text (SF Symbols offers Latin/Hebrew/Arabic variants for signature, rich-text, I-beam symbols); design text-free alternatives for non-script concepts.
- Flip icons depicting forward/backward motion (speaker sound waves emanate forward).
- Don't flip logos (legal risk) or universal signs/marks (checkmarks).
- Avoid flipping icons of real-world objects (clocks; right-handed tools — most people are right-handed).
- For complex custom icons, consider each component: keep design-language elements like backslashes consistent; flip badges only if they depict actual UI; preserve tool orientation while flipping the base image if needed.

### Resources
Localization, Creating custom symbol images for your app, Preparing views for localization (SwiftUI)
