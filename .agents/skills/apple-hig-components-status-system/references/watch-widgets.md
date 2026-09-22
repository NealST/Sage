> Source: https://developer.apple.com/design/human-interface-guidelines/complications
> Source: https://developer.apple.com/design/human-interface-guidelines/watch-faces
> Source: https://developer.apple.com/design/human-interface-guidelines/widgets

Note: All watch complication sizes below are in points (pt); HIG lists @2x pixel dimensions that are exactly double the pt values.

## Complications

A complication displays timely, relevant information on the watch face, where people can view it each time they raise their wrist. Most watch faces show at least one complication; some show four or more.

watchOS 9+ organizes complications (accessories) into families (circular, inline, etc.); each watch face specifies the family supported per slot. Prefer WidgetKit for watchOS 9 and later; use legacy ClockKit templates (`CLKComplicationDataSource`) for earlier versions — legacy templates are nongraphic and don't take the wearer's selected color.

### Best practices

- Identify essential, dynamic content people want at a glance; a static complication that shows no meaningful data tends to lose its watch-face slot.
- Support all complication families when possible; if a family can't show useful data, supply an app-representative image (e.g., your app icon) that still launches the app.
- Consider multiple complications per family — people love configuring (and sharing) watch faces centered on your app (e.g., a triathlon app offering three circular complications, one per race segment, each deep-linking to its segment).
- Define a different deep link for each complication so each opens the most relevant area of your app.
- Keep privacy in mind — with Always-On Retina displays, watch-face data can be visible to others — and choose update times carefully: you supply a timeline with limited updates per day and limited stored entries (a meeting app might show data an hour before the meeting; a weather app at the time conditions occur).

### Visual design

- Pick ring or gauge styles by data: closed style for a percentage of a whole (battery); open style for arbitrary min/max ranges (speed); segmented style for rapid value changes (Noise).
- Tinted mode applies a solid color to text, gauges, and images and desaturates full-color images unless you provide tinted versions (`WidgetRenderingMode`; legacy templates: tinted mode applies only to graphic complications). Don't rely on color alone to convey information; supply alternative tinted-mode images when the desaturated version looks bad; expect some people to prefer tinted mode.
- Use line widths of two points or greater — thinner lines are hard to see at a glance, especially in motion.
- Provide a set of static placeholder images per complication (shown when there's no content and in the complication-selection carousel); placeholder sizes may differ from actual image sizes.

### Family layouts and sizes

**Circular** (regular size — Infograph, Infograph Modular; system applies a circular mask). Bezel text can fill nearly 180 degrees before truncating.

| Content | 40mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|
| Image | 42x42 | 44.5x44.5 | 47x47 | 50x50 |
| Closed gauge | 27x27 | 28.5x28.5 | 31x31 | 32x32 |
| Open gauge | 11x11 | 11.5x11.5 | 12x12 | 13x13 |
| Stack (not text) | 28x14 | 29.5x15 | 31x16 | 33.5x16.5 |

Default SwiftUI text: Rounded, Medium — 12 pt (40mm), 12.5 pt (41mm), 13 pt (44mm), 14.5 pt (45/49mm).

Extra-large circular layouts (X-Large watch face; circular mask on circular and gauge images; some text fields support multicolor):

| Content | 40mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|
| Image | 120x120 | 127x127 | 132x132 | 143x143 |
| Open gauge | 31x31 | 33x33 | 33x33 | 37x37 |
| Closed gauge | 77x77 | 81.5x81.5 | 87x87 | 91.5x91.5 |
| Stack | 80x40 | 85x42 | 87x44 | 95x48 |

Default SwiftUI text: Rounded, Medium — 34.5 pt (40mm), 36.5 pt (41mm), 36.5 pt (44mm), 41 pt (45/49mm).

Circular-family placeholder images (38mm: none):

| Layout | 40/42mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|
| Circular | 42x42 | 44.5x44.5 | 47x47 | 50x50 |
| Bezel | 42x42 | 44.5x44.5 | 47x47 | 50x50 |
| Extra Large | 120x120 | 127x127 | 132x132 | 143x143 |

**Corner** (Infograph corners; full-color images, text, gauges; some templates support multicolor text; circular mask):

| Content | 40mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|
| Circular | 32x32 | 34x34 | 36x36 | 38x38 |
| Gauge | 20x20 | 21x21 | 22x22 | 24x24 |
| Text | 20x20 | 21x21 | 22x22 | 24x24 |

Placeholder (38mm: none): 20x20 (40/42mm), 21x21 (41mm), 22x22 (44mm), 24x24 (45/49mm). Default SwiftUI text: Rounded, Semibold — 10 pt (40mm), 10.5 pt (41mm), 11 pt (44mm), 12 pt (45/49mm).

**Inline** — utilitarian small layouts occupy a rectangular corner area (Chronograph, Simple): content can be an image, interface icon, or circular graph; utilitarian large is primarily text with an optional leading interface icon, spanning the bottom of a face (Utility, Motion), and its flat content uses the same sizes as utilitarian small flat.

| Content | 38mm | 40/42mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|---|
| Flat (small and large) | 9–21x9 | 10–22x10 | 10.5–23.5x10.5 | N/A | 12–26x12 |
| Ring | 14x14 | 14x14 | 15x15 | 16x16 | 16.5x16.5 |
| Square | 20x20 | 22x22 | 23.5x23.5 | 25x25 | 26x26 |

**Rectangular** (large region; full-color images, text, gauge, optional title; supports multicolor text; large-image layouts include a 4-pt corner radius). Good for information-rich charts of changing values (e.g., Heart Rate's 24-hour graph). In watchOS 10+ the system may show your rectangular layout in the Smart Stack — optimize with informative background color/content, intents for relevancy, or a custom Smart Stack layout (`WidgetFamily.accessoryRectangular`).

| Content | 40mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|
| Large image with title | 150x47 | 159x50 | 171x54 | 178.5x56 |
| Large image without title | 162x69 | 171.5x73 | 184x78 | 193x82 |
| Standard body | 12x12 | 12.5x12.5 | 13.5x13.5 | 14.5x14.5 |
| Text gauge | 12x12 | 12.5x12.5 | 13.5x13.5 | 14.5x14.5 |

Default SwiftUI text: Rounded, Medium — 16.5 pt (40mm), 17.5 pt (41mm), 18 pt (44mm), 19.5 pt (45/49mm).

### Legacy templates (ClockKit, pre-watchOS 9)

Circular small (small image or a few characters, e.g., Color face), modular small (two stacked rows, e.g., bottom of Modular face), modular large (up to three rows, center of Modular face), extra large (X-Large faces). In stack measurements, width is the maximum size.

| Template | Content | 38mm | 40/42mm | 41mm | 44mm | 45/49mm |
|---|---|---|---|---|---|---|
| Circular small | Ring | 20x20 | 22x22 | 23.5x23.5 | 24x24 | 26x26 |
| Circular small | Simple / Placeholder | 16x16 / 16x16 | 18x18 / 18x18 | 19x19 / 19x19 | 20x20 / 20x20 | 21.5x21.5 / 21.5x21.5 |
| Circular small | Stack | 16x7 | 17x8 | 18x8.5 | 19x9 | 19x9.5 |
| Modular small | Ring | 18x18 | 19x19 | 20x20 | 21x21 | 22.5x22.5 |
| Modular small | Simple / Placeholder | 26x26 / 26x26 | 29x29 / 29x29 | 30.5x30.5 / 30.5x30.5 | 32x32 / 32x32 | 34.5x34.5 / 34.5x34.5 |
| Modular small | Stack | 26x14 | 29x15 | 30.5x16 | 32x17 | 34.5x18 |
| Modular large | Columns / Standard body / Table | 11–32x11 | 12–37x12 | 12.5–39x12.5 | 14–42x14 | 14.5–44x14.5 |
| Extra large | Ring | 63x63 | 66.5x66.5 | 70.5x70.5 | 73x73 | 79x79 |
| Extra large | Simple / Placeholder | 91x91 / 91x91 | 101.5x101.5 / 101.5x101.5 | 107.5x107.5 / 107.5x107.5 | 112x112 / 112x112 | 121x121 / 121x121 |
| Extra large | Stack | 78x42 | 87x45 | 92x47.5 | 96x51 | 103.5x53.5 |

### Platform considerations

- watchOS only. **Not supported in iOS, iPadOS, macOS, tvOS, or visionOS.**

### Resources

WidgetKit (Migrating ClockKit complications to WidgetKit), CLKComplicationDataSource, placeholder(in:), WidgetRenderingMode, WidgetFamily.accessoryRectangular. Related: Watch faces.

## Watch faces

A watch face is a view that people choose as their primary view in watchOS. People customize faces with their favorite complications, keep different faces for different activities, and — since watchOS 7 — share configured faces (from your app, website, or via Messages, Mail, or social media), which can introduce more people to your complications and app.

### Best practices

- Share watch faces that feature your complications; ideally support multiple complications for a curated shareable face. Some faces let you specify a system accent color, images, or styles. If people add your face without your app installed, the system prompts them to install it.
- Display a preview of each face you share (email the face to yourself from the iOS Watch app); the preview includes an illustrated bezel suitable for websites and apps, or composite a high-fidelity hardware bezel from Apple Design Resources.
- Offer shareable faces for all Apple Watch devices: some faces require Series 4 or later (California, Chronograph Pro, Gradient, Infograph, Infograph Modular, Meridian, Modular Compact, Solar Dial); Explorer requires Series 3 (cellular) or later. Offer a similar configuration for Series 3 and earlier, and clearly label the devices each face supports.
- Respond gracefully to incompatible choices: when someone applies an incompatible face on Series 3 or earlier, the system sends your app an error — immediately offer a compatible alternative configuration instead of showing an error, and set expectations that an alternative may be delivered.

### Platform considerations

- watchOS only. **Not supported in iOS, iPadOS, macOS, tvOS, or visionOS.**

### Resources

Sharing an Apple Watch face (ClockKit); Apple Design Resources — Product Bezels.

## Widgets

A widget provides quick access to essential information and focused interactions from your app or game in additional contexts — e.g., Home Screen/Lock Screen (iPhone, iPad), desktop and Notification Center (Mac), horizontal or vertical surfaces (Apple Vision Pro), and a fixed position in the Smart Stack (Apple Watch). Sizes range from small accessory widgets to system families including extra large (iPad, Mac, Apple Vision Pro); WidgetKit supplies default appearances per size and context, but consider custom designs per context.

System family widget contexts:

| Widget size | iPhone | iPad | Mac | Apple Vision Pro |
|---|---|---|---|---|
| System small | Home Screen, Today View, StandBy, CarPlay | Home Screen, Today View, Lock Screen | Desktop, Notification Center | Horizontal and vertical surfaces |
| System medium | Home Screen, Today View | Home Screen, Today View | Desktop, Notification Center | Horizontal and vertical surfaces |
| System large | Home Screen, Today View | Home Screen, Today View | Desktop, Notification Center | Horizontal and vertical surfaces |
| System extra large | Not supported | Home Screen, Today View | Desktop, Notification Center | Horizontal and vertical surfaces |
| System extra large portrait | Not supported | Not supported | Not supported | Horizontal and vertical surfaces |

Accessory widget contexts (limited information due to size):

| Widget size | iPhone | iPad | Apple Watch |
|---|---|---|---|
| Accessory circular | Lock Screen | Lock Screen | Watch complications and the Smart Stack |
| Accessory corner | Not supported | Not supported | Watch complications |
| Accessory inline | Lock Screen | Lock Screen | Watch complications |
| Accessory rectangular | Lock Screen | Lock Screen | Watch complications and the Smart Stack |

Appearances: full-color, tinted, or clear/translucent, depending on location, device, and customization. iPhone/iPad Home Screen widgets can be light, dark, clear (desaturated + translucency + Liquid Glass), or tinted (desaturated + tint color). visionOS widgets are 3D objects in a frame with a glass- or paper-like coating; optional system-palette tint. iPad Lock Screen and accessory rectangular widgets on iPhone/iPad Lock Screen are monochrome. iPhone StandBy scales widgets up with the background removed; low light renders a monochromatic red tint.

Rendering modes: **full-color** (system family widgets, all platforms; view colors unchanged); **accented** (system family widgets on all platforms plus accessory widgets on Apple Watch; background removed, tinted color effect or Liquid Glass background; views split into accent and primary groups, each with a solid color); **vibrant** (iPhone/iPad Lock Screen and StandBy low light; desaturates and colors content for the background, red tint in StandBy low light).

| Platform | Full-color | Accented | Vibrant |
|---|---|---|---|
| iPhone | Home Screen, Today view, StandBy and CarPlay (background removed) | Home Screen, Today view | Lock Screen; StandBy in low light |
| iPad | Home Screen, Today view | Home Screen, Today view | Lock Screen |
| Apple Watch | Smart Stack, complications | Smart Stack, complications | Not supported |
| Mac | Desktop, Notification Center | Not supported | Desktop |
| Apple Vision Pro | Horizontal/vertical surfaces | Horizontal/vertical surfaces | Not supported |

### Best practices

- Choose simple ideas tied to your app's main purpose, with timely content and relevant functionality (Weather widgets prioritize current conditions and high/low).
- Give people quick access to the content they want — meaningful content, useful actions, deep links; don't just replicate your app icon.
- Prefer dynamic information that changes during the day; static widgets lose prominent placement — and look for opportunities to surprise and delight (special calendar-widget treatments for birthdays or holidays).
- Offer multiple sizes only when each adds value; never stretch small-widget content to fill a larger size — one well-sized widget beats all sizes.
- Balance information density: sparse layouts seem unnecessary, dense ones are less glanceable; consider a larger size or graphics instead of text.
- Show only information directly related to the widget's purpose (Calendar widgets stay centered on events while revealing more as size grows).
- Use brand elements thoughtfully — colors, typefaces, stylized glyphs; a small top-right logo only when needed (e.g., multi-source content) — and choose between automatic content (Podcasts) and user configuration (Stocks) appropriately.
- Don't mirror your widget's appearance inside your app — a look-alike that doesn't behave like a widget confuses people; instead, let people know when authentication adds value ("Sign in to view reservations").

Updating content — widgets refresh periodically, never in real time; the system may adjust update limits:

- Match update frequency to how often data changes and when people need it; if people will check more often than you can update, show when data was last updated.
- Let the system refresh dates and times automatically to preserve update opportunities; show content quickly rather than hiding stale data behind placeholders.
- Use animated transitions (up to two seconds) to draw attention to updates.

Interactivity:

- Tapping a widget launches its app; buttons and toggles add in-app-free functionality (Reminders' completion toggles).
- Offer simple, relevant actions; reserve complexity for the app.
- Deep-link interactions to the matching detail (medium Stocks widget opens the symbol's page).
- Stay glanceable and uncluttered; mind tap-target size; inline accessory widgets offer only one tap target; avoid app-like layouts.

Margins and padding:

- The system resizes/scales widgets across devices (iOS resizes large-device designs down; iPadOS renders large then scales down); supply appropriately sized content.
- Use the standard 16-pt margin for most widgets; 11 pt works for tighter groupings (graphics, buttons, background shapes); margins are smaller on the Mac desktop and Lock Screen (including StandBy).
- Coordinate content corner radius with the widget's (`ContainerRelativeShape`).

Text:

- Prefer the system font, text styles, and SF Symbols; if using a custom font, use it sparingly (custom for large text, SF Pro for small) and keep it readable at a glance.
- Avoid font sizes below 11 pt; never rasterize text (scaling and VoiceOver depend on text elements).
- iOS, iPadOS, and visionOS widgets support Dynamic Type sizes from Large to AX5.

Color:

- Use color to enhance without competing with content; specify asset-catalog colors for the editing-mode UI.
- Convey meaning without relying on color — widgets can appear monochrome or tinted, and watchOS may invert colors per watch face; use text and iconography too.
- Use full-color images judiciously: they're desaturated by default in tinted/clear appearances; keeping them full-color draws attention and may feel out of place — reserve for media content (album art), smaller than the widget.

Rendering-mode design:

- Full-color: support light and dark appearances (light background in light, dark in dark; semantic system colors; asset-catalog variants).
- Accented: group views into accent and primary groups (`widgetAccentable(_:)`); iPhone/iPad/Mac tint both white; Apple Watch tints primary white and accented in the watch-face color.
- Vibrant: ensure contrast — pixel opacity drives the material effect, brightness drives vibrancy (brighter gray = more contrast); render content at full opacity with white/light gray for prominent content and darker grays for secondary; use opaque grayscale values rather than white opacities.

Previews and placeholders:

- Design a realistic gallery preview (real data, or realistic simulated data if generation is slow) and placeholder content that combines static components with semi-opaque shapes (rectangles for text lines, circles/squares for glyphs and images).
- Write a succinct description beginning with an action verb ("See the current weather…"); avoid "This widget shows…"; sentence-style capitalization; one description per widget with sizes grouped together.
- Consider coloring the gallery Add button to reinforce your brand.

### Platform considerations

- macOS: no additional considerations. **Not supported in tvOS.**
- iOS, iPadOS: Lock Screen widgets function like watch complications — follow complication design principles, provide useful information (not just app launching), and consider designing them in tandem. Three shapes: inline text above the clock; circular and rectangular below it. Support the Always-On display with sufficient gray-level contrast. Offer Live Activities for real-time updates — widgets can't show real-time information, but widgets and Live Activities share frameworks, so develop them in tandem and reuse code.
- StandBy and CarPlay: StandBy shows two small widgets side by side, scaled up; CarPlay and StandBy both use the small system widget with the background removed, scaled to the grid. Glanceable information and large text matter most in CarPlay. In StandBy, limit rich images/color, scale up and rearrange text, and use no background colors (blends with the black background); low light renders a monochromatic red tint.
- visionOS: widgets are 3D objects placed on horizontal or vertical surfaces; they persist across device restarts, keep real-world scale, and their size, mounting style, and treatment affect perception. Full-color by default; accented when personalized with system tint palettes; people can customize frame width for elevated mounting. There's no systemwide light/dark appearance (apps like the Music poster widget can offer their own generated from album art).
  - Adapt design to the spatial context — widgets live in people's rooms and offices (Music poster glanceable across the room; a small productivity widget for a desk); test across all system color palettes and lighting conditions.
  - Design for two thresholds: simplified (viewed at a distance — fewer details, larger type, no interactive elements) and default (nearby — more details, smaller type); keep shared elements for continuity.
  - Pick family sizes that fit real placements (small for a desk; extra large for wall artwork); content must stay legible as people scale widgets from 75 to 125 percent — use print-design hierarchy and high-resolution assets.
  - Mounting styles: elevated (default; horizontal surfaces tilt back with a soft shadow; vertical surfaces sit flush like a picture frame) suits content that stands out (reminders, media, glanceable data); recessed (vertical surfaces only; cutout depth effect) suits immersive/ambient content (weather, editorial). Opt out per widget; recessed-only widgets can't sit on horizontal surfaces. Declare support with `supportedMountingStyles(_:)` per WidgetConfiguration (use separate configurations for mixed support). Test elevated designs with every system frame width — layouts can't adapt per width.
  - Treatment styles: paper (grounded, print-like, responds to ambient light — e.g., Music poster as framed artwork) or glass (layered depth; foreground stays bright and legible regardless of lighting — good for information-rich widgets like News).
- watchOS: provide a colorful background that conveys meaning (default is black; Stocks uses red for falling, green for rising). Encourage Smart Stack display/elevation with relevancy information (location- or action-based, e.g., a workout; RelevanceKit).

### Specifications

iOS widget dimensions (pt):

| Screen (portrait) | Small | Medium | Large | Circular | Rectangular | Inline |
|---|---|---|---|---|---|---|
| 430x932 | 170x170 | 364x170 | 364x382 | 76x76 | 172x76 | 257x26 |
| 428x926 | 170x170 | 364x170 | 364x382 | 76x76 | 172x76 | 257x26 |
| 414x896 | 169x169 | 360x169 | 360x379 | 76x76 | 160x72 | 248x26 |
| 414x736 | 159x159 | 348x157 | 348x357 | 76x76 | 170x76 | 248x26 |
| 393x852 | 158x158 | 338x158 | 338x354 | 72x72 | 160x72 | 234x26 |
| 390x844 | 158x158 | 338x158 | 338x354 | 72x72 | 160x72 | 234x26 |
| 375x812 | 155x155 | 329x155 | 329x345 | 72x72 | 157x72 | 225x26 |
| 375x667 | 148x148 | 321x148 | 321x324 | 68x68 | 153x68 | 225x26 |
| 360x780 | 155x155 | 329x155 | 329x345 | 72x72 | 157x72 | 225x26 |
| 320x568 | 141x141 | 292x141 | 292x311 | N/A | N/A | N/A |

iPadOS widget dimensions (pt; * = Display Zoom "More Space"):

| Screen (portrait) | Target | Small | Medium | Large | Extra large |
|---|---|---|---|---|---|
| 768x1024 | Canvas | 141x141 | 305.5x141 | 305.5x305.5 | 634.5x305.5 |
| 768x1024 | Device | 120x120 | 260x120 | 260x260 | 540x260 |
| 744x1133 | Canvas | 141x141 | 305.5x141 | 305.5x305.5 | 634.5x305.5 |
| 744x1133 | Device | 120x120 | 260x120 | 260x260 | 540x260 |
| 810x1080 | Canvas | 146x146 | 320.5x146 | 320.5x320.5 | 669x320.5 |
| 810x1080 | Device | 124x124 | 272x124 | 272x272 | 568x272 |
| 820x1180 | Canvas | 155x155 | 342x155 | 342x342 | 715.5x342 |
| 820x1180 | Device | 136x136 | 300x136 | 300x300 | 628x300 |
| 834x1112 | Canvas | 150x150 | 327.5x150 | 327.5x327.5 | 682x327.5 |
| 834x1112 | Device | 132x132 | 288x132 | 288x288 | 600x288 |
| 834x1194 | Canvas | 155x155 | 342x155 | 342x342 | 715.5x342 |
| 834x1194 | Device | 136x136 | 300x136 | 300x300 | 628x300 |
| 954x1373 * | Canvas | 162x162 | 350x162 | 350x350 | 726x350 |
| 954x1373 * | Device | 162x162 | 350x162 | 350x350 | 726x350 |
| 970x1389 * | Canvas | 162x162 | 350x162 | 350x350 | 726x350 |
| 970x1389 * | Device | 162x162 | 350x162 | 350x350 | 726x350 |
| 1024x1366 | Canvas | 170x170 | 378.5x170 | 378.5x378.5 | 795x378.5 |
| 1024x1366 | Device | 160x160 | 356x160 | 356x356 | 748x356 |
| 1192x1590 * | Canvas | 188x188 | 412x188 | 412x412 | 860x412 |
| 1192x1590 * | Device | 188x188 | 412x188 | 412x412 | 860x412 |

visionOS dimensions:

| Widget | Size (pt) | Size (mm, scaled to 100%) |
|---|---|---|
| Small | 158x158 | 268x268 |
| Medium | 338x158 | 574x268 |
| Large | 338x354 | 574x600 |
| Extra large | 450x338 | 763x574 |
| Extra large portrait | 338x450 | 574x763 |

watchOS dimensions (widget in the Smart Stack):

| Apple Watch size | Size (pt) |
|---|---|
| 40mm | 152x69.5 |
| 41mm | 165x72.5 |
| 44mm | 173x76.5 |
| 45mm | 184x80.5 |
| 49mm | 191x81.5 |

### Resources

WidgetKit, "Developing a WidgetKit strategy", RelevanceKit, widgetAccentable(_:), supportedMountingStyles(_:). Related: Layout; videos "WidgetKit foundations", "What's new in widgets", "Design widgets for visionOS".
