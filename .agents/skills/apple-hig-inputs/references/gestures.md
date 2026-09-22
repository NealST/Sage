> Source: https://developer.apple.com/design/human-interface-guidelines/gestures
> Source: https://developer.apple.com/design/human-interface-guidelines/focus-and-selection

## Gestures

A gesture is a physical motion that a person uses to directly affect an object in an app or game on their device. People make gestures on a touchscreen, in the air, or on input devices (trackpad, mouse, remote, or game controller with a touch surface); every platform supports basic gestures like tap, swipe, and drag, and people expect them to work everywhere.

### Best practices

- Give people more than one way to interact with your app — never assume a specific gesture can be used; support voice, keyboard, and Switch Control as well.
- Respond to gestures consistently with people's expectations: tap activates or selects; avoid using a familiar gesture for an app-unique action, and avoid creating a unique gesture for a standard action (activating a button, scrolling).
- Handle gestures as responsively as possible; provide immediate feedback that helps people predict a gesture's results and communicates the movement required to complete it.
- Indicate when a gesture isn't available (e.g., a locked object, an unavailable button state that isn't visually distinct) — otherwise people may think the app has frozen or they're performing the gesture wrong.
- Add custom gestures only when necessary: for specialized, frequently performed tasks not covered by existing gestures (games, drawing apps). A custom gesture must be discoverable, straightforward to perform, distinct from other gestures, and never the only way to perform an important action.
- Make custom gestures easy to learn: offer teaching moments, test in real-use scenarios; if you can't describe it in simple language and graphics, people will find it hard to learn and perform.
- Use shortcut gestures to supplement standard gestures, not replace them (e.g., a Back button plus an optional side-swipe shortcut).
- Avoid conflicting with gestures that access system UI (watchOS edge swipes, visionOS hand-roll for system overlays); in games or immersive experiences you can defer the system gesture in specific circumstances.

### Platform considerations

**iOS, iPadOS** — In addition to standard gestures:

| Gesture | Common action |
|---|---|
| Three-finger swipe | Initiate undo (left swipe); initiate redo (right swipe) |
| Three-finger pinch | Copy selected text (pinch in); paste copied text (pinch out) |
| Four-finger swipe (iPadOS only) | Switch between apps |
| Shake | Initiate undo; initiate redo |

- Consider allowing simultaneous recognition of multiple gestures when it enhances the experience (e.g., a game with joystick and firing buttons operated at once).

**macOS** — People primarily use a keyboard and mouse; standard gestures work on Magic Trackpad, Magic Mouse, or a game controller with a touch surface.

**tvOS** — People use standard gestures with a compatible remote, Siri Remote, or game controller with touch surface (see Remotes).

**visionOS** — Supports indirect and direct gesture categories:
- Indirect: look at an object to target it, then manipulate from a distance (e.g., look at a button to focus, tap finger and thumb together to select). Comfortable at any distance; quick focus changes with minimal movement.
- Direct: physically touch an interactive object (e.g., typing on the virtual keyboard). Best within reach; keeping arms raised is tiring, so reserve for infrequent use. Direct versions of all standard gestures are supported.

| Direct gesture | Common use |
|---|---|
| Touch | Directly select or activate an object |
| Touch and hold | Open a contextual menu |
| Touch and drag | Move an object to a new location |
| Double touch | Preview an object or file; select a word in an editing context |
| Swipe | Reveal actions and controls; dismiss views; scroll |
| Two hands, pinch and drag together or apart | Zoom in or out |
| Two hands, pinch and drag in a circular motion | Rotate an object |

- Support standard gestures everywhere you can (tap is the first gesture people make to select/activate).
- Offer both indirect and direct interactions when possible: prefer indirect for UI and common components like buttons; reserve direct and custom gestures for close-up interaction or specific motions.
- Avoid requiring specific body movements or positions for input; support alternative inputs.
- Custom gestures require running in a Full Space and permission to access hand information (ARKit). Prioritize comfort — test ergonomics; raised-arm or repeated similar motions stress muscles and joints. Carefully consider complex multi-finger or two-hand gestures (people may not always have both hands available); avoid custom gestures that require a specific hand (cognitive load, hand-dominance, limb differences).
- System overlays (visionOS 2+): looking at the palm plus gestures accesses Home and Control Center systemwide; looking up remains as an accessibility setting.
  - Reserve the area around a person's hand for system overlays; don't anchor content to hands or wrists; place hand-anchored game content outside the immediate hand area to avoid colliding with the Home indicator.
  - Consider deferring the system overlay in an immersive Full Space app or game (require a tap to reveal the Home indicator — `persistentSystemOverlays(_:)`); visionOS 1 apps defer by default.
  - Use caution with custom gestures involving a rolling motion of hand, wrist, and forearm — reserved for revealing system overlays; test for conflicts.

**watchOS** — Double tap (watchOS 11+): scroll through lists and scroll views, advance between vertical tab views, and perform a designated primary action (a toggle or button in your app, widget, or Live Activity in the Smart Stack — double tap highlights the control, then performs the action). In notifications, double tap acts on the first nondestructive action.
- Avoid setting a primary action in views with lists, scroll views, or vertical tabs — it conflicts with default double-tap navigation.
- Choose the button people use most commonly as the primary action (e.g., play/pause in a media controls view). See `handGestureShortcut(_:isEnabled:)` and `primaryAction`.

### Specifications — standard gestures

| Gesture | Supported in | Common action |
|---|---|---|
| Tap | iOS, iPadOS, macOS, tvOS, visionOS, watchOS | Activate a control; select an item |
| Swipe | iOS, iPadOS, macOS, tvOS, visionOS, watchOS | Reveal actions and controls; dismiss views; scroll |
| Drag | iOS, iPadOS, macOS, tvOS, visionOS, watchOS | Move a UI element |
| Touch (or pinch) and hold | iOS, iPadOS, tvOS, visionOS, watchOS | Reveal additional controls or functionality |
| Double tap | iOS, iPadOS, macOS, tvOS, visionOS, watchOS | Zoom in; zoom out if already zoomed; perform a primary action on Apple Watch Series 9 and Apple Watch Ultra 2 |
| Zoom | iOS, iPadOS, macOS, tvOS, visionOS | Zoom a view; magnify content |
| Rotate | iOS, iPadOS, macOS, tvOS, visionOS | Rotate a selected item |

### Resources

- Gestures — SwiftUI; UITouch — UIKit

## Focus and selection

Focus helps people visually confirm the object that their interaction targets. Using inputs like a remote, game controller, or keyboard, people bring focus to the components they want to interact with; focusing an item often also selects it, except when automatic selection would cause a distracting context shift (in tvOS, selection requires a separate gesture). Platforms communicate focus differently: iPadOS and macOS draw a ring or highlight; tvOS generally uses parallax to give the focused item depth and liveliness.

### Best practices

- Rely on system-provided focus effects — they're precisely tuned, consistent, and predictable; create custom focus effects only if absolutely necessary.
- Avoid changing focus without people's interaction; people must spend time finding the newly focused item. Exception: with discrete directional input (keyboard, remote, game controller), if the focused item disappears, move focus to a nearby remaining item; otherwise hide the focus indicator when the focused object disappears.
- Be consistent with the platform: in iPadOS and macOS, full keyboard access reaches every control, so support focus only for content elements (list items, text fields, search fields); in tvOS, directional gestures must reach every onscreen element, so make every element focusable.
- Indicate focus using platform-consistent appearances: focused list items use white text and an accent-color background highlight; unfocused items use standard text and a gray highlight.
- Use a focus ring for a text or search field, and a highlight in a list or collection; a focus ring is acceptable for an item that fills a cell (like a photo), but highlighting the entire row is usually easier to view.

### Platform considerations

Not supported in iOS or watchOS.

**iPadOS** — iPadOS 15+ defines a focus system supporting keyboard navigation of text fields, text views, sidebars, collection views, and custom views. Same underlying system as tvOS, but:
- Tab moves focus among focus groups (specific areas like a sidebar, grid, or list); arrow keys navigate directionally within a focus group.
- Focus indicators: the halo effect (focus ring) — a customizable outline applied to custom views and fully opaque cell content; customize shape (rounded corners, Bézier paths) and position if occluded or clipped (`UIFocusHaloEffect`). The highlighted appearance (text in the app's accent color) isn't a focus effect; it occurs automatically when selecting a collection view cell with content configurations (`UICollectionViewCell`).
- Ensure focus moves through custom views sensibly: Tab visits focus groups in reading order (leading to trailing, top to bottom); identify stack containers as a single focus group to control order (`focusGroupIdentifier`).
- Adjust item priority within a focus group: the primary item automatically receives focus when the group does (`UIFocusGroupPriority`).

**tvOS**
- In a full-screen experience, let people use gestures to interact with the content, not to move focus.
- Avoid displaying a pointer: people expect to navigate by changing focus; free-form pointer movement only makes sense during gameplay (and must be highly visible and integrated).
- Design for up to five visually distinct focus states: unfocused (less prominent), focused (elevation to foreground, illumination, animation), choosing (instant feedback, e.g., brief color inversion), selected/deselected (e.g., a heart button filled vs. empty), and unavailable (appears inactive). Supply assets for the larger, focused size and ensure the larger item doesn't crowd surrounding UI.

**visionOS** — Supports the same focus system as iPadOS and tvOS via a connected keyboard or game controller. Note: when people look at a virtual object, the system uses the hover effect (not a focus effect) — hover is unrelated to the focus system (see Eyes).

### Resources

- Focus Attributes — TVML; Focus-based navigation — UIKit; About focus interactions for Apple TV — UIKit
