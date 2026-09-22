> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-ios
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-games
> Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo

## iOS
People depend on iPhone to stay connected, play games, view media, accomplish tasks, and track personal data anywhere and on the go.

Characteristics: medium-size high-resolution display; held in one or both hands, viewing distance about 1–2 feet; Multi-Touch gestures, virtual keyboards, voice control; sessions range from minutes to an hour+, multiple apps open at once. System features: Widgets, Home Screen quick actions, Spotlight, Shortcuts, Activity views.

### Best practices
- Concentrate on primary tasks and content: limit onscreen controls, make secondary details and actions discoverable with minimal interaction.
- Adapt seamlessly to appearance changes — orientation, Dark Mode, Dynamic Type — letting people choose the configurations that work best for them.
- Accommodate the way people hold the device: place controls in the middle or bottom of the display; let people swipe to navigate back or initiate actions in a list row.
- With permission, integrate platform capabilities (payments, biometric authentication, location) to enhance the experience without asking people to enter data.

### Resources
iOS Pathway; videos "Meet Liquid Glass", "Get to know the new design system"

## iPadOS
People value the power, mobility, and flexibility of iPad for media, games, detailed productivity tasks, and creation.

Characteristics: large high-resolution display; held, set down, or on a stand, viewing distance up to ~3 feet; Multi-Touch, attached keyboard/pointing device, Apple Pencil, voice — often combined; quick actions to hours of immersion, multiple apps onscreen at once. System features: Multitasking, Widgets, Drag and drop.

### Best practices
- Use the large display to elevate content people care about; minimize modal interfaces and full-screen transitions; position controls where they're easy to reach but not in the way.
- Let viewing distance and input mode determine the size and density of onscreen content.
- Support Multi-Touch, physical keyboard/trackpad, and Apple Pencil, including interactions that combine input modes.
- Adapt seamlessly to orientation, multitasking modes, Dark Mode, and Dynamic Type, and transition effortlessly to running in macOS.

### Resources
iPadOS Pathway; videos "Elevate the design of your iPad app", "Meet Liquid Glass"

## macOS
People rely on the power, spaciousness, and flexibility of a Mac for in-depth productivity, media, and games, often using several apps at once.

Characteristics: large high-resolution display, extendable with additional displays including iPad; used while stationary at 1–3 feet; any combination of physical keyboards, pointing devices, game controls, and Siri; sessions from minutes to hours of deep concentration with smooth active/inactive transitions. System features: the menu bar, File management, Going full screen, Dock menus.

### Best practices
- Leverage large displays to present more content in fewer nested levels with less modality, at a comfortable information density.
- Let people resize, hide, show, and move windows to fit their work style; support full-screen mode for distraction-free contexts.
- Use the menu bar to give easy access to all commands in your app.
- Help people take advantage of high-precision input modes for pixel-perfect selections and edits.
- Handle keyboard shortcuts to accelerate actions and support keyboard-only work styles.
- Support personalization: customizable toolbars, window views, colors, and fonts.

### Resources
macOS Pathway; videos "Meet Liquid Glass", "Build an AppKit app with the new design system"

## tvOS
People enjoy vibrant content, immersive experiences, and streamlined interactions on Apple TV in media, games, fitness, education, and home utility apps.

Characteristics: very large high-resolution display; viewed from 8+ feet away; input via remote, game controller, voice, and apps on other devices; deep single-experience immersion, often hours, with picture-in-picture. System features: TV app integration, SharePlay, Top Shelf, TV provider accounts.

### Best practices
- Support powerful, delightful interactions through the fluid, familiar Siri Remote gestures.
- Embrace the tvOS focus system: let it gently highlight and expand onscreen items so people always know what to do and where they are.
- Deliver beautiful edge-to-edge artwork, subtle fluid animations, and engaging audio — clear and legible from across the room.
- Enhance multiuser support: make sign-in easy and infrequent, handle shared sign-in, and switch profiles automatically when the current viewer changes.

### Resources
tvOS Pathway; video "Build SwiftUI apps for tvOS"

## visionOS
When people wear Apple Vision Pro, they enter an infinite 3D space where they can engage with your app or game while staying connected to their surroundings.

Characteristics: limitless canvas with windows, volumes, and 3D objects; fluid transitions between immersion levels — Shared Space (multiple apps side-by-side) by default, Full Space (only your app); passthrough via external cameras controlled with the Digital Crown; Spatial Audio modeled on the surroundings; eyes + indirect/direct hand gestures; content placed relative to the wearer's head; supports VoiceOver, Switch Control, Dwell Control, Guided Access, Head Pointer.

Important: consider user safety — the device shouldn't be used while operating a vehicle or heavy machinery, in unsafe environments (balconies, streets, stairs), and is designed for people 13+ only.

### Best practices
- Embrace space, Spatial Audio, immersion, passthrough, and eye-and-hand input in ways that feel at home on the device.
- Find the minimum level of immersion that suits each key moment — don't assume every moment needs to be fully immersive.
- Use windows for contained, UI-centric experiences with familiar controls; people can relocate windows and dynamic scaling keeps content legible at any distance.
- Prioritize comfort: display content within the field of view relative to the head; avoid overwhelming, jarring, or too-fast motion without a stationary frame of reference; support indirect gestures with hands resting in lap or at sides; for direct gestures keep interactive content close and brief; avoid encouraging much movement in fully immersive experiences.
- Use SharePlay so people can view the spatial Personas of other participants in shared activities.

### Resources
visionOS Pathway; "Creating your first visionOS app"; videos "Design interactive experiences for visionOS", "Design great visionOS apps", "Principles of spatial design"

## watchOS
When people glance at Apple Watch, they access essential information and perform simple, timely tasks whether stationary or in motion.

Characteristics: small wrist-worn, easy-to-read high-resolution display, Always On; ~1 foot viewing distance; Digital Crown for vertical navigation, tap/swipe/drag gestures, Action button, shortcuts, device sensors (GPS, blood oxygen, heart, altimeter, accelerometer, gyroscope); interactions under a minute — complications, notifications, and Siri are used more than the app itself. System features: Complications, Notifications, Always On, Watch faces.

### Best practices
- Support quick, glanceable, single-screen interactions that deliver critical information succinctly with one or two simple gestures.
- Minimize navigation hierarchy depth; use the Digital Crown for vertical navigation or switching screens.
- Personalize: anticipate needs using on-device data to provide actionable, moment-relevant content.
- Use complications to surface relevant, dynamic data on the watch face; tap to dive straight into the app.
- Use notifications to deliver timely, high-value information and actions without opening the app.
- Use background color to convey supporting information and materials to illustrate hierarchy and place.
- Design the app to function independently, complementing notifications and complications with additional detail.

### Resources
watchOS Pathway; video "What's new in watchOS 26"

## Games
When people play your game on an Apple device, they dive into the world you designed while relying on the platform features they love.

### Best practices
**Jump into gameplay**
- Let people play as soon as installation completes: keep initial download to 30 minutes or less and download additional content in the background.
- Provide great default settings (device-appropriate resolution, automatic accessory/controller recognition, accessibility settings) so play starts without configuration.
- Teach through play: integrate configuration and onboarding into a playable tutorial; offer written tutorials as reference, not prerequisites.
- Defer permission requests until the scenario that needs the data (e.g., hand tracking permission between the cutscene and first use); let people spend quality time before asking for ratings or reviews.

**Look stunning on every display**
- Keep text legible: ensure good contrast and at least the recommended minimum text size per platform.
- Keep buttons easy to use: meet recommended minimum sizes per platform.
- Prefer resolution-independent textures; in visionOS prefer vector-based art that scales well at any distance/angle.
- Integrate device features (rounded corners, camera housing) into layout using platform-provided safe areas.
- Make in-game menus adapt to different aspect ratios (16:10, 19.5:9, 4:3) with dynamic, relative-constraint layouts; avoid fixed layouts; support both orientations on iPhone/iPad if supported.
- Design for the full-screen experience (full-screen mode on macOS/iOS/iPadOS; Full Space in visionOS).

**Enable intuitive interactions**
- Support each platform's default interaction method; pay attention to control sizing and menu behavior, especially moving from pointer-based to touch-based.
- Support physical game controllers everywhere except watchOS, but always offer alternatives for players who can't use one.
- On iPhone and iPad, offer touch-based controls that embrace the touchscreen (direct interaction and virtual controls).

**Welcome everyone**
- Prioritize perceivability: never rely on color alone or cutscenes without descriptive subtitles.
- Let players personalize: type size, control mapping, motion intensity, sound balance — use built-in Apple accessibility technologies (system frameworks or Unity plug-ins).
- Give players tools to represent themselves (avatars, names) across the spectrum of self-identity.
- Avoid stereotypes in stories and characters; review for bias; keep real-life cultural references respectful.

**Adopt Apple technologies**
- Integrate Game Center (achievements, leaderboards, challenges, multiplayer) — available on all platforms.
- Support GameSave so players continue on any device via iCloud.
- Adopt Core Haptics for custom haptics (iOS, iPadOS, tvOS, visionOS, many game controllers).
- Use multichannel audio for Spatial Audio immersion.
- Integrate AR, machine learning, HealthKit, location, camera, and microphone where they enable unique mechanics.

### Specifications

| Platform | Default text size | Minimum text size |
|---|---|---|
| iOS, iPadOS | 17 pt | 11 pt |
| macOS | 13 pt | 10 pt |
| tvOS | 29 pt | 23 pt |
| visionOS | 17 pt | 12 pt |
| watchOS | 16 pt | 12 pt |

| Platform | Default button size | Minimum button size |
|---|---|---|
| iOS, iPadOS | 44x44 pt | 28x28 pt |
| macOS | 28x28 pt | 20x20 pt |
| tvOS | 66x66 pt | 56x56 pt |
| visionOS | 60x60 pt | 28x28 pt |
| watchOS | 44x44 pt | 28x28 pt |

| Platform | Default interaction methods | Additional interaction methods |
|---|---|---|
| iOS | Touch | Game controller |
| iPadOS | Touch | Game controller, keyboard, mouse, trackpad, Apple Pencil |
| macOS | Keyboard, mouse, trackpad | Game controller |
| tvOS | Remote | Game controller, keyboard, mouse, trackpad |
| visionOS | Touch | Game controller, keyboard, mouse, trackpad, spatial game controller |
| watchOS | Touch | – |

### Resources
GameKit, Core Haptics, Game Center, iCloud, Games Pathway

## iPhone Duo
An app designed for iPhone Duo adapts seamlessly to both displays, providing a continuous experience as the device opens and closes.

Anatomy: inner + outer display, each with its own front camera; center hinge; outer camera in the corner aligned with side controls; inner camera behind the display, visible only when active. Standard system components + resize support adapt automatically. You're still designing for iPhone — Designing for iOS patterns still apply.

### Best practices
- Build your app to resize: use size classes, layout margins, and safe area insets; avoid fixed widths and display-specific dependencies.
- Create a consistent experience across displays: keep functionality and element state the same; show an additional hierarchy level on the larger inner display when it makes sense (e.g., Mail shows list + email side by side).
- Maintain the same functionality across device poses: controls may overflow and content may move, but the same controls and content must remain accessible.
- Follow the system's vertical layout for toolbars, tab bars, and navigation controls (side placement preserves vertical space; standard components get this automatically). Inner display in portrait keeps standard horizontal bars.
- Make games playable in every pose: fill the screen, keep text/control sizes consistent, prefer aspect-ratio changes over letterboxing/pillarboxing; if padding is unavoidable, add artwork to it.

### Reserved regions (areas content avoids or components adapt to)
- Outer front-facing camera: always present; expands into the Dynamic Island for Live Activities.
- Inner front-facing camera: present only when active; UI moves aside when it activates.
- Folding region: when partially open, divides the inner display into usable regions, excluding the fold center.
- Adapt when folding: prefer auto-adapting containers (split views adjusting pane widths); prefer even column counts in grids; use ReservedRegion APIs for elements the system doesn't move automatically; avoid extreme layout changes — favor small adjustments over rearrangement.

### Arrangement views and controls
- Arrangement views (split: divides area between primary/secondary views; overlay: stacks them, moving to each side when partially folded) map from HStack/VStack and ZStack layouts. Keep navigation containers outside arrangement views.
- Account for asymmetry: controls along one edge make content space asymmetrical; use safe areas so controls (including the opposite app's in Split View multitasking) don't cover content.
- Keep controls' relative positions similar across poses.
- Toolbar item order on the vertical axis: primary navigation (Back/Close) at top, then prominent actions (Done); keep remaining items in original groupings.
- Prioritize frequently used items: items overflow bottom-to-top by default; assign visibility priorities; preserve status items with badges; don't override default bar placement in general.
- Consider full display width for immersive, non-scrolling interfaces that don't conflict with the Dynamic Island or status bar.
- Group related toolbar items with ToolbarItemGroup instead of manual spacing; locate controls near the content they affect.
- Provide both title and symbol for non-text-only toolbar items (system picks representation; titles appear in overflow menus); keep text-based buttons to a minimum.
- When space is limited: in navigation-focused views, compress the toolbar (overflow menu) keeping the tab bar; in task-oriented views, minimize the tab bar keeping toolbar actions.
- Use the system overflow menu; reserve the ellipsis symbol for overflow.

### Resources
ReservedRegion (SwiftUI), UIView.ReservedRegion (UIKit), ArrangementView (SwiftUI), UIArrangementViewController (UIKit), NavigationSplitView, UISplitViewController, ToolbarItemVisibilityPriority, UIBarButtonItemVisibilityPriority, ToolbarVerticalCompressionBehavior, UIVerticalBarCompressionBehavior, ToolbarOverflowMenu, additionalOverflowItems, Device Hub (Xcode)
