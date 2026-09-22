> Source: https://developer.apple.com/design/human-interface-guidelines/action-button
> Source: https://developer.apple.com/design/human-interface-guidelines/camera-control
> Source: https://developer.apple.com/design/human-interface-guidelines/digital-crown
> Source: https://developer.apple.com/design/human-interface-guidelines/eyes
> Source: https://developer.apple.com/design/human-interface-guidelines/game-controls

## Action button

The Action button gives people quick access to their favorite features on supported iPhone and Apple Watch models. People assign it an App Shortcut or system function (e.g., flashlight) at setup and can adjust it in Settings; on Apple Watch Ultra it supports activity-related actions like workouts and dives. Pressing the button runs an App Shortcut the same way Siri or Spotlight would — treat it as another way to quickly reach a regularly used function.

### Best practices

- Support the Action button with a set of your app's essential functions (e.g., a cooking app's "Start Egg Timer"). Don't offer a shortcut that merely opens your app — the system provides that, and app icons, widgets, and complications are other quick ways in.
- For each action, write a short label: title-style capitalization, begins with a verb, present tense, no articles or prepositions, maximum three words ("Start Race", not "Started Race" or "Start the Race"). People see these labels in Settings.
- Prefer letting the system show people how to use the Action button with your app; avoid repeating the guidance the system already provides in Settings.

### Platform considerations

Not supported in iPadOS, macOS, tvOS, or visionOS.

- iOS: Let people use your actions without leaving their current context — use lightweight multitasking like Live Activities and custom snippets (e.g., "Set Timer" prompts for a duration and launches a Live Activity instead of opening the Clock app).
- watchOS: A first press can drop a waypoint, start a dive, or begin a specific workout; subsequent presses can perform secondary actions (mark a segment, advance to the next modality of a multi-part workout).
  - Offer a secondary function that supports or advances the primary action: people press without looking, so the next press must flow logically; keep it simple, intuitive, easy to learn and remember. Carefully consider offering more than one secondary function — it increases cognitive load.
  - Prefer subsequent presses for additional functionality, not for stopping or concluding a task; put stop controls in your interface instead.
  - Pressing the Action button and side button together pauses the current function (exception: diving apps, where pausing mid-dive can be dangerous).

## Camera Control

The Camera Control provides direct access to your app's camera experience. On iPhone 16 and iPhone 16 Pro, it quickly opens your app's camera to capture moments; a light press displays an overlay extending from the device bezel, a light double-press shows available controls, and sliding a finger on the Camera Control adjusts the selected value.

### Anatomy

- Slider: a range of values (e.g., contrast amount).
- Picker: discrete options (e.g., grid on/off).
- Beyond custom controls, the system provides optional standard controls for zoom factor and exposure bias.

### Best practices

- Use SF Symbols to represent control functionality — custom symbols aren't supported; symbols denote behavior, not current state (see the Camera & Photos section of the SF Symbols app).
- Keep control names short: labels scale with Dynamic Type, and longer names may obfuscate the viewfinder.
- Include units or symbols with slider values for context (EV, %, or a custom string — `localizedValueFormat`).
- Define prominent values for sliders — the values people choose most often or evenly spaced ones (like major zoom increments); the system lands on them more easily (`prominentValues`).
- Make space for the overlay in the viewfinder: the overlay and labels occupy the screen area adjacent to the Camera Control in both orientations; place your UI outside those areas, maximize the viewfinder, and let the overlay appear and disappear over it.
- Minimize distractions in the viewfinder: avoid duplicating controls (sliders, toggles) in both your UI and the overlay.
- Enable or disable controls depending on camera mode (e.g., disable video controls when taking photos). The overlay supports multiple controls, but you can't add or remove them at runtime.
- Order commonly used controls toward the middle for quick access and lesser-used controls to the sides; the system remembers the last control used in your app.
- Allow people to launch your experience from anywhere: create a locked camera capture extension so people can configure the Camera Control to launch your camera experience from a locked device, the Home Screen, or within other apps.

### Platform considerations

Not supported in iPadOS, macOS, watchOS, tvOS, or visionOS (iPhone 16 models only).

### Resources

- Enhancing your app experience with the Camera Control — AVFoundation; AVCaptureControl; LockedCameraCapture

## Digital Crown

The Digital Crown is an important hardware input for Apple Vision Pro and Apple Watch. On both devices people use it to interact with the system; on Apple Watch, people also use it to interact with apps.

- Apple Vision Pro: people use the Digital Crown to adjust volume, adjust the amount of immersion (in a portal, Environment, or Full Space app or game), recenter content in front of them, open Accessibility settings, and exit an app to the Home View. Turning it generates information you can use to enhance interactions, like scrolling or operating standard or custom controls.
- Apple Watch (watchOS 10+): the primary input for navigation — turn it to view widgets in the Smart Stack on the watch face, move vertically through the app collection on the Home Screen, switch between vertically paginated tabs, and scroll list views and variable-height pages. Turning it also supports inspecting data and operating standard or custom controls. Apps don't respond to presses on the Digital Crown — watchOS reserves them for system functionality like revealing the Home Screen.
- Haptics: most Apple Watch models provide haptic feedback; by default the system provides linear detents as people turn the crown a specific distance, and some system controls (like table views) provide detents as new items scroll onto the screen.

### Best practices

- Anchor your app's navigation to the Digital Crown: since watchOS 10, turning it is the main way people navigate within and between apps; keep list, tab, and scroll views vertically oriented, and back up Digital Crown interactions with corresponding touch screen interactions.
- Consider using it to inspect data where navigation isn't necessary (e.g., World Clock: turning the crown advances the time of day at a selected location).
- Provide visual feedback in response to Digital Crown interactions — pickers change the displayed value as people turn it; if you track turns directly, update your interface programmatically, or people will assume turning it has no effect.
- Update your interface to match the speed at which people turn the crown — people expect precise control; avoid updating content at a rate that makes selecting values difficult.
- Use the default haptic feedback when it makes sense: turn off detents if they don't fit your app (e.g., they don't match your animation); for tables you can switch from row-based to linear detents — with rows of significantly different heights, linear detents feel more consistent.

### Platform considerations

Not supported in iOS, iPadOS, macOS, or tvOS (Apple Vision Pro and Apple Watch only).

### Resources

- WKCrownDelegate — WatchKit

## Eyes

In visionOS, people look at a virtual object to identify it as a target they can interact with. When people look at an interactive element, visionOS highlights it (the hover effect), showing they can use an indirect gesture like tap to interact. The system can also display an expanded view after people look at a component (a tab bar resizes to reveal text labels — individual tabs still highlight first; a button can reveal a tooltip). To preserve privacy, visionOS doesn't provide direct information about where people are looking before they tap; system-provided components tell you when people tap them. Focus effects (for keyboard/game controller navigation) are unrelated to the hover effect (see Focus and selection).

### Best practices

- Always give people multiple ways to interact with your app; support the accessibility features people use to personalize interaction.
- Design for visual comfort: keep needed objects within the field of view; avoid requiring multiple quick eye adjustments across a large area or through multiple levels of depth. (In a Full Space, your app can request head-pose access to place 3D content appropriately.)
- Place content at a comfortable viewing distance — at least one meter for content people read or engage with over time; place content very close only for brief viewing.
- Prefer standard UI components: they respond consistently when people look at them; custom components with different visual cues are hard to learn and remember.
- Making items easy to see:
  - Minimize visual distractions; visual movement is especially distracting — people involuntarily look at motion in their peripheral vision (content revealed near a button can steal the look from the button).
  - Provide enough space around items: eyes make small quick adjustments even while fixating, so use a margin of at least 16 pt around each item's bounds or keep item centers at least 60 pt apart.
  - Avoid a repeating pattern or texture that fills the field of view — eyes can lock onto different pattern elements, making them appear at different depths; use the pattern in a smaller area instead.
- Encouraging interaction:
  - Use subtle visual cues to draw attention to the most likely item: place it near the center of the field of view, or use gentle motion, increased contrast, or variations in color or scale — noticeable without being flashy or harsh.
  - Give interactive items a rounded shape: eyes are drawn to corners, making corner-heavy shapes hard to keep targeting; more rounded is easier.
  - For multi-element interactive components (e.g., an image plus label), define a custom region encompassing both elements so visionOS highlights the entire region when people look at either.
- Custom hover effects (can replace or augment standard effects on system/custom UI and RealityKit entities):
  - Understand the mechanism: you define two appearances (with and without the effect), and the system applies the effect out of process — you don't know when it applies or the element's state, so it can't run code that requires knowing when people are looking (a photo's hover effect can show a Favorites symbol but can't perform the favoriting action).
  - Prefer custom hover effects for emphasizing special moments; too many (or using them where standard effects suffice) dilutes impact, distracts, and can cause visual discomfort.
  - Choose the right delay: no delay (default — subtle effects that invite interaction, like a slider knob); short delay (look and quickly interact, like tab-bar expansion); long delay (additional information like a tooltip, which most people won't need every time).
  - Keep one or more primary views unchanged across both states — constant views provide visual stability; if everything moves or changes, people get disoriented.
  - Thoroughly test custom hover effects while wearing Apple Vision Pro.

### Platform considerations

Not supported in iOS, iPadOS, macOS, tvOS, or watchOS (visionOS only).

### Resources

- Adopting best practices for privacy and user preferences — visionOS

## Game controls

Precise, intuitive game controls enhance gameplay and can increase a player's immersion in the game. A game can support physical game controllers or the platform's default interactions (touch, remote, mouse and keyboard). Support the defaults too: not every player has a controller, and players appreciate using the interaction method they know best.

### Touch controls (iOS/iPadOS; use the Touch Controller framework for virtual controls)

- Decide whether virtual controls over game content make sense: they benefit games with many actions or movement control, but direct interaction with in-game objects can be more immersive — reduce virtual controls by binding actions to in-game gestures (tap objects to select instead of a virtual selection button).
- Place virtual buttons where they're easy to access: respect device boundaries and safe areas; don't overlap the Home indicator or Dynamic Island; put frequently used buttons near the player's thumb, avoiding the circular regions where players expect movement and camera input; put secondary controls like menus at the top of the screen.
- Make controls large enough:

| Control importance | Minimum size |
|---|---|
| Frequently used controls | 44x44 pt |
| Less important controls (e.g., menus) | 28x28 pt |

- Always include visible and tactile press states: without a visual and physical press state a control feels unresponsive; use a press effect (like a glow) visible even under a covering finger, combined with sound and haptics.
- Use symbols that communicate the actions they perform (a weapon graphic for attack); avoid abstract shapes or controller-based naming (A, X, R1) as artwork — harder to understand and remember.
- Show and hide virtual controls to reflect gameplay: hide controls when an action is unavailable or irrelevant (e.g., hide movement controls until the player touches the screen; make a thumbstick more visible with a highlight while it moves).
- Combine functionality into a single control: redesign mechanics requiring simultaneous or sequenced button presses; use double tap and touch-and-hold for action variations (touch and hold for a powered-up attack); merge related actions (walk/sprint) into one control.
- Map movement and camera controls to predictable behavior: movement on the left, camera on the right; maximize the input area; show a virtual thumbstick wherever the player's thumb lands rather than a fixed position; for camera, prefer direct-touch panning over a virtual thumbstick.

### Physical controllers

- Support the platform's default interaction method as a fallback — every iPhone/iPad has touch, every Mac a keyboard and trackpad/mouse, every Apple TV a remote, every Apple Vision Pro responds to eyes and hands.
- Tell people about controller requirements: tvOS and visionOS apps can require a physical controller (App Store shows a "Game Controller Required" badge). People can open your game at any time without one — check for presence and gracefully prompt them to connect (`GCRequiresControllerUserInteraction`).
- Automatically detect whether a controller is paired and get its profile instead of requiring manual setup (Game Controller framework).
- Customize onscreen content to match the connected controller: the framework assigns standard names to elements by placement, but colors and symbols differ by controller — use the connected controller's labeling scheme (`GCControllerElement`).
- Map controller buttons to expected UI behavior outside gameplay (consistent across Apple platforms):

| Button | Expected behavior for UI |
|---|---|
| A | Activates a control |
| B | Cancels an action or returns to previous screen |
| X | — |
| Y | — |
| Left shoulder | Navigates left to a different screen or section |
| Right shoulder | Navigates right to a different screen or section |
| Left trigger | — |
| Right trigger | — |
| Left/right thumbstick | Moves selection |
| Directional pad | Moves selection |
| Home/logo | Reserved for system controls |
| Menu | Opens game settings or pauses gameplay |

- Support multiple connected controllers: use labels and glyphs matching the controller the player is actively using; in multiplayer, use the appropriate labels for each player's controller; list buttons together when referring to multiple controllers.
- Prefer symbols, not text, to refer to controller elements — SF Symbols are available for most elements, helping players unfamiliar with controllers.

### Keyboards

- Prioritize single-key commands: easier and faster, especially while also using a mouse or trackpad (first letter of a menu item — I for Inventory, M for Map; map the main action to the Space bar).
- Test key-binding comfort with an Apple keyboard: if a binding uses Control (^) on a non-Apple keyboard, consider remapping to Command (⌘), which sits next to the Space bar and is easy to reach alongside W, A, S, D.
- Take key proximity into account: use keys near WASD for other high-value commands; map closely related actions to physically close keys (number keys for inventory categories).
- Let players customize key bindings: people expect reasonable defaults but many need customization for comfort and play style.

### Platform considerations

No additional considerations for iOS, iPadOS, macOS, or tvOS. Not supported in watchOS.

- visionOS: Match spatial game controller behavior (e.g., PlayStation VR2 Sense controller) to hand input — support looking at an object and pressing the left or right trigger to interact indirectly, or reaching out and pressing the trigger to interact directly.

### Resources

- Touch Controller; Game Controller; GCRequiresControllerUserInteraction; GCControllerElement
