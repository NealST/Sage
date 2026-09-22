> Source: https://developer.apple.com/design/human-interface-guidelines/motion
> Source: https://developer.apple.com/design/human-interface-guidelines/images
> Source: https://developer.apple.com/design/human-interface-guidelines/immersive-experiences

## Motion
Beautiful, fluid motions bring the interface to life, conveying status, providing feedback and instruction, and enriching the visual experience of your app or game.

Many system components include motion automatically and adjust for accessibility settings and input methods (e.g., Liquid Glass movement is more pronounced for direct touch, more subdued for trackpad).

### Best practices
- Add motion purposefully — supporting the experience without overshadowing it; gratuitous or excessive animation distracts and can cause discomfort.
- Make motion optional: never use it as the only way to communicate important information; supplement visual feedback with haptics and audio.
- Strive for realistic feedback motion that follows people's gestures and expectations (a view revealed by sliding down is dismissed the same way); brevity and precision make feedback feel lightweight and unobtrusive.
- In apps, generally avoid motion on frequent UI interactions (the system already animates standard elements; custom elements shouldn't add attention cost).
- Let people cancel motion: don't force waiting for an animation to complete, especially repeated ones.
- Consider animated SF Symbols (SF Symbols 5+).
- Games: maintain 30 to 60 fps for a smooth experience; use each device's graphics capabilities for great default settings; let people customize the visual experience (e.g., power modes on external power).

### Platform considerations
- visionOS: motion combines with depth for essential feedback, so avoid distraction, confusion, and discomfort.
  - Avoid motion at the edges of the field of view (peripheral motion is distracting and can cause discomfort); if needed, keep the object's brightness similar to surrounding content.
  - For large virtual objects occluding passthrough, increase translucency or lower contrast so movement doesn't feel like the surroundings are moving; even when the person moves the object (e.g., a window), consider keeping its size small.
  - Consider fades when relocating an object (fade out, move, fade in) when the movement itself communicates nothing.
  - Avoid letting people rotate a virtual world (upsets stability even when controlled and subtle); use instantaneous directional changes during a quick fade-out instead.
  - Give people a stationary frame of reference — motion contained in a non-moving area is easier to handle than the entire surroundings moving.
  - Avoid sustained oscillation, especially around 0.2 Hz (people are very sensitive to it); keep amplitude low and content translucent if oscillation is needed.
- watchOS: use SwiftUI for motion; WatchKit layout/appearance animations (WKInterfaceImage for image sequences) automatically include built-in easing at start and end that can't be turned off or customized.

### Resources
SymbolEffect, Animating views and transitions (SwiftUI), WKInterfaceImage

## Images
To make sure your artwork looks great on all devices you support, learn how the system displays content and how to deliver art at the appropriate scale factors.

### Best practices
- A point is an abstract unit: on 2D platforms it maps to a variable number of pixels; in visionOS a point is an angular value that scales with distance from the viewer.
- Provide high-resolution assets for all bitmap images, on every device: append @1x, @2x, or @3x to filenames in the asset catalog.
- Design at the lowest resolution and scale up; position vector control points at whole values so they stay pixel-aligned at 2x/3x.
- Include a color profile with each image; always test on a range of actual devices.

### Specifications

| Platform | Scale factors |
|---|---|
| iPadOS, watchOS | @2x |
| iOS | @2x and @3x |
| visionOS | @2x or higher |
| macOS, tvOS | @1x and @2x |

| Image type | Format |
|---|---|
| Bitmap or raster work | De-interlaced PNG files |
| PNG graphics not requiring full 24-bit color | 8-bit color palette |
| Photos | JPEG (optimized) or HEIC |
| Stereo or spatial photos | Stereo HEIC |
| Flat icons, interface icons, flat artwork needing high-res scaling | PDF or SVG |

### Platform considerations
- tvOS: layered images (two to five layers + transparency) power the parallax focus effect — required for the app icon, strongly encouraged for other focusable images (e.g., Top Shelf). Use standard interface elements (e.g., FocusState) for automatic parallax. Identify logical foreground (prominent elements, text), middle (secondary content, shadows), and background (opaque backdrop — an opaque background is mandatory) layers. Keep text in the foreground; keep layering simple and subtle; leave a safe zone around foreground layers (cropping happens on focus); retrieve runtime layered images (.lcr, generated with layerutil) from a content server rather than embedding them; always preview (Xcode, Parallax Previewer, Parallax Exporter plug-in, and on an actual TV).
- visionOS: people view images at a large range of sizes and the system dynamically scales resolution. Create a layered app icon (two to three layers); prefer vector-based 2D art; for rasterized images balance quality and performance — @2x is fine at common distances, higher resolutions cost file size and runtime performance (especially over @6x; apply high-quality image filtering). Spatial photos use stereo HEIC (visionOS adds treatments minimizing stereo-viewing discomfort); use the feathered glass background effect for text over spatial photos; adjust disparity metadata carefully (comfort varies by viewing position); display spatial photos/scenes in standalone views (sheets or windows, not inline — or provide generous spacing); spatial scenes take seconds to generate — use explicit actions, avoid many at once; prefer minimal UI when displaying immersively; prefer larger spatial scenes centered in the field of view.
- watchOS: avoid transparency to keep image files small (bake in solid backgrounds) — except template images (complications, menu icons, interface icons) where the system needs transparency to apply color. Use autoscaling PDFs designed for 40mm/42mm at 2x:

| Screen size | Image scale |
|---|---|
| 38mm | 90% |
| 40mm | 100% |
| 41mm | 106% |
| 42mm | 100% |
| 44mm | 110% |
| 45mm | 119% |
| 49mm | 119% |

### Resources
Parallax Previewer, layerutil, ImagePresentationComponent, GlassBackgroundEffect, filters (visionOS), Images (SwiftUI), UIImageView, NSImageView

## Immersive experiences
In visionOS, you can design apps and games that extend beyond windows and volumes, immersing people in your content.

Apps launch in the Shared Space (alongside other experiences, like a Mac) or a Full Space (your app alone, hiding others); they can transition fluidly at any time. Passthrough provides real-time camera video of the surroundings; the Digital Crown recenters content (press and hold) or briefly hides all content (double-click). The system auto-dims content when people get close to physical objects, and progressive/full experiences define a boundary about 1.5 meters from the initial head position — content fades near the boundary and is replaced by the app's icon beyond it, restoring on return or recentering.

### Immersion styles
- Dimmed passthrough: subtly dim or tint passthrough (black by default, custom tint color supported) to bring attention to your content in the Shared Space without hiding other apps.
- Mixed (Full Space): blend content with passthrough; no boundary — nearby content becomes semi-opaque when people approach physical objects; request ARKit data for nearby objects and room layout.
- Progressive (Full Space): custom environment partially replacing passthrough; people adjust immersion with the Digital Crown within the default 120- to 360-degree range (or a custom range); supports portrait or landscape orientation; ~1.5 m boundary applies.
- Full (Full Space): 360-degree custom environment completely replacing passthrough; ~1.5 m boundary applies.

### Best practices
- Offer multiple ways to use your app or game and support the accessibility features people use.
- Prefer launching in the Shared Space or the mixed immersion style — give people control over when to increase immersion.
- Reserve immersion for meaningful moments and content; not every task benefits, and not every immersive task needs full immersion.
- Help people engage with key moments at any immersion level: use subtle cues (dimming, tinting, motion, scale, Spatial Audio) and strengthen only with good reason.
- Prefer subtle passthrough tint colors; avoid bright or dramatic tints.

### Promoting comfort
- Place 3D content within people's field of view; display motion in comfortable ways.
- Choose an immersion style that supports the movements people might make: minor movements are fine, but avoid progressive/full styles (or transition back to mixed) if people might move beyond the 1.5 m boundary.
- Avoid encouraging movement during progressive/full immersion — design ways to interact without moving (bring objects closer instead of moving closer to them).
- In mixed style, avoid obscuring passthrough too much; if virtual objects would block the view substantially, use full or progressive styles instead.
- Adopt ARKit to blend custom content with surroundings (requires permission for sensitive data).

### Transitioning between styles
- Design smooth, predictable transitions people can visually track; avoid sudden, jarring changes.
- Let people choose when to enter or exit a more immersive experience (e.g., Keynote's prominent Exit button); don't require system controls to reduce immersion.
- Indicate the purpose of an exit control (return to less-immersive context vs. quit); if exiting quits, offer pause/save controls first.

### Displaying virtual hands
- Prefer virtual hands matching familiar characteristics (positions and gestures of the viewer's hands).
- Use caution with virtual hands larger than the viewer's (block content, clumsy interactions, out of proportion).
- If hand-tracking is interrupted, fade out virtual hands and reveal the viewer's own hands; fade back in when data returns — never let them freeze.

### Creating an environment
- Minimize distracting content: for a primary task like video, avoid lots of movement or high-contrast detail; direct attention via texture quality gradients and dimming.
- Help people distinguish interactive objects via proximity (far = untouchable, close = interactive).
- Keep animation subtle (drifting clouds); avoid movement near the edges of the field of view.
- Create an expansive environment — small, restrictive spaces feel claustrophobic.
- Use Spatial Audio for atmosphere; avoid repetitive looping; lower or stop the soundscape when people play other audio.
- Avoid flat 360-degree images (no sense of scale); prefer object meshes with lighting and subtle shader animation; always provide a ground plane mesh so people feel grounded; minimize asset redundancy.

### Platform considerations
- Not supported in iOS, iPadOS, macOS, tvOS, or watchOS (visionOS only).

### Resources
ImmersionStyle, ImmersiveSpace (SwiftUI), SurroundingsEffect, ARKit, SceneReconstructionProvider, CoordinateSpaceProtocol
