> Source: https://developer.apple.com/design/human-interface-guidelines/keyboards
> Source: https://developer.apple.com/design/human-interface-guidelines/pointing-devices
> Source: https://developer.apple.com/design/human-interface-guidelines/remotes

## Keyboards

A physical keyboard can be an essential input device for entering text, playing games, controlling apps, and more. People can connect one to any device except Apple Watch; Mac users use one all the time and iPad users often do. A keyboard shortcut combines a primary key with modifier keys (Control, Option, Shift, Command); a game's shortcut (key binding) is often a single key.

### Best practices

- Support Full Keyboard Access when possible (iOS, iPadOS, macOS, visionOS): it lets people navigate and activate windows, menus, controls, and system features using only the keyboard. Test by enabling it in Settings > Accessibility (`isFullKeyboardAccessEnabled`).
- In iPadOS, avoid supporting keyboard navigation for controls (buttons, segmented controls, switches) — let Full Keyboard Access handle them; support navigation only in text fields, text views, sidebars, collection views, and custom views.
- Respect standard keyboard shortcuts; for a frequent unique action, create a custom shortcut instead of repurposing a standard one. In games, people expect standard shortcuts (e.g., Command-Q to quit) and modifiable key bindings.
- Don't repurpose standard shortcuts for custom actions; only redefine one if its action makes no sense in your app (e.g., no text editing → repurpose Command-I for Get Info).
- Define custom shortcuts only for the most frequently used app-specific commands; too many new shortcuts make an app seem hard to learn.
- Use modifier keys in expected ways: Command-drag moves items as a group; Shift-drag-resize constrains to aspect ratio; holding an arrow key moves the selection by the smallest app-defined unit.

### Standard keyboard shortcuts (people expect each to perform the listed action)

| Shortcut | Action |
|---|---|
| Command-Space | Show or hide the Spotlight search field |
| Shift-Command-Space | Varies |
| Option-Command-Space | Show the Spotlight search results window |
| Control-Command-Space | Show the Special Characters window |
| Shift-Tab | Navigate through controls in reverse direction |
| Command-Tab | Move forward to the next most recently used app |
| Shift-Command-Tab | Move backward through open apps (by recent use) |
| Control-Tab | Move focus to the next control group in a dialog, or the next table |
| Control-Shift-Tab | Move focus to the previous control group |
| Esc | Cancel the current action or process |
| Option-Command-Esc | Open the Force Quit dialog |
| Control-Command-Eject | Quit all apps (after saving) and restart the computer |
| Control-Option-Command-Eject | Quit all apps (after saving) and shut the computer down |
| Control-F1 | Toggle full keyboard access on or off |
| Control-F2 | Move focus to the menu bar |
| Control-F3 | Move focus to the Dock |
| Control-F4 | Move focus to the active (or next) window |
| Control-Shift-F4 | Move focus to the previously active window |
| Control-F5 | Move focus to the toolbar |
| Command-F5 | Turn VoiceOver on or off |
| Control-F6 | Move focus to the first (or next) panel |
| Control-Shift-F6 | Move focus to the previous panel |
| Control-F7 | Temporarily override the current keyboard access mode in windows and dialogs |
| F8 / F9 / F10 | Varies |
| F11 | Show desktop |
| F12 | Hide or display Dashboard |
| Command-` (grave accent) | Activate the next open window in the frontmost app |
| Shift-Command-` | Activate the previous open window in the frontmost app |
| Option-Command-` | Move focus to the window drawer |
| Command-Hyphen | Decrease the size of the selection |
| Option-Command-Hyphen | Zoom out when screen zooming is on |
| Command-[ | Left-align a selection |
| Command-] | Right-align a selection |
| Command-\| | Center-align a selection |
| Command-: | Display the Spelling window |
| Command-; | Find misspelled words in the document |
| Command-, | Open the app's settings window |
| Control-Option-Command-, | Decrease screen contrast |
| Command-. | Cancel an operation |
| Control-Option-Command-. | Increase screen contrast |
| Command-? | Open the app's Help menu |
| Option-Command-/ | Turn font smoothing on or off |
| Shift-Command-= | Increase the size of the selection |
| Option-Command-= | Zoom in when screen zooming is on |
| Shift-Command-3 | Capture the screen to a file |
| Control-Shift-Command-3 | Capture the screen to the Clipboard |
| Shift-Command-4 | Capture a selection to a file |
| Control-Shift-Command-4 | Capture a selection to the Clipboard |
| Option-Command-8 | Turn screen zooming on or off |
| Control-Option-Command-8 | Invert the screen colors |
| Command-A | Select every item in a document or window, or all characters in a text field |
| Shift-Command-A | Deselect all selections or characters |
| Command-B | Boldface the selected text or toggle boldfacing |
| Command-C | Copy the selection to the Clipboard |
| Shift-Command-C | Display the Colors window |
| Option-Command-C | Copy the style of the selected text |
| Control-Command-C | Copy the formatting settings of the selection to the Clipboard |
| Option-Command-D | Show or hide the Dock |
| Control-Command-D | Display the selected word's definition in the Dictionary app |
| Command-E | Use the selection for a find operation |
| Command-F | Open a Find window |
| Option-Command-F | Jump to the search field control |
| Control-Command-F | Enter full screen |
| Command-G | Find the next occurrence of the selection |
| Shift-Command-G | Find the previous occurrence of the selection |
| Command-H | Hide the windows of the currently running app |
| Option-Command-H | Hide the windows of all other running apps |
| Command-I | Italicize the selected text (toggle); also used to display an Info window |
| Option-Command-I | Display an inspector window |
| Command-J | Scroll to a selection |
| Command-M | Minimize the active window to the Dock |
| Option-Command-M | Minimize all windows of the active app to the Dock |
| Command-N | Open a new document |
| Command-O | Display a dialog for choosing a document to open |
| Command-P | Display the Print dialog |
| Shift-Command-P | Display the Page Setup dialog |
| Command-Q | Quit the app |
| Shift-Command-Q | Log out the current person |
| Option-Shift-Command-Q | Log out without confirmation |
| Command-S | Save a new document or save a version |
| Shift-Command-S | Duplicate the active document or initiate a Save As |
| Command-T | Display the Fonts window |
| Option-Command-T | Show or hide a toolbar |
| Command-U | Underline the selected text (toggle) |
| Command-V | Paste the Clipboard contents at the insertion point |
| Shift-Command-V | Paste as (e.g., Paste as Quotation) |
| Option-Command-V | Apply the style of one object to the selection |
| Option-Shift-Command-V | Paste and apply the surrounding text's style |
| Control-Command-V | Apply formatting settings to the selection |
| Command-W | Close the active window |
| Shift-Command-W | Close a file and its associated windows |
| Option-Command-W | Close all windows in the app |
| Command-X | Remove the selection and store it on the Clipboard |
| Command-Z | Undo the previous operation |
| Shift-Command-Z | Redo (when Undo and Redo are separate commands) |
| Command-Right/Left arrow | Change keyboard layout to Roman/system script |
| Shift-Command-arrow | Extend selection to the next semantic unit (line ends for left/right; document start/end for up/down) |
| Shift-arrow | Extend selection one character (left/right) or one line (up/down) |
| Option-Shift-arrow | Extend selection word by word (left/right) or paragraph by paragraph (up/down) |
| Control-arrow | Move focus to another value or cell in a view, such as a table |

Localized/input-source shortcuts: Control-Space toggles between the current and last input source; Control-Option-Space switches to the next input source; [Modifier]-Command-Space varies.

### Custom keyboard shortcuts

| Modifier | Recommended usage |
|---|---|
| Command (⌘) | Prefer as the main modifier in a custom shortcut |
| Shift (⇧) | Prefer as a secondary modifier complementing a related shortcut |
| Option (⌥) | Use sparingly, for less-common commands or power features |
| Control (⌃) | Avoid; the system uses Control in many systemwide features (moving focus, screenshots) |

- Some languages need modifier keys to generate characters (French Option-5 = "{"); Command is usually safe, but avoid additional modifiers with characters unavailable on all keyboards — if you must use another modifier, prefer alphabetic characters.
- List multiple modifiers in this order: Control, Option, Shift, Command.
- Avoid adding Shift to a shortcut using the upper character of a two-character key (Help is Command-Question mark, not Shift-Command-Slash).
- Let the system localize and mirror shortcuts (automatic per connected keyboard and right-to-left layouts).
- Don't create a new shortcut by adding a modifier to an existing shortcut for an unrelated command (Shift-Command-Z must stay undo/redo-related).

### Platform considerations

No additional considerations for iOS, iPadOS, macOS, or tvOS. Not supported in watchOS.

**visionOS** — App shortcuts appear in the shortcut interface shown when people hold Command on a connected keyboard; it lists all relevant system-defined menu categories (File, Edit, View) in one view, showing only available commands that have shortcuts.
- Write descriptive shortcut titles: the flat list has no submenu titles for context (`discoverabilityTitle`).
- Recognize that connecting a physical keyboard displays a virtual keyboard overlay providing typing completion and other controls.

### Resources

- KeyboardShortcut — SwiftUI; Input events — SwiftUI; Handling key presses made on a physical keyboard — UIKit; Mouse, Keyboard, and Trackpad — AppKit

## Pointing devices

People can use a pointing device like a trackpad or mouse to navigate the interface and initiate actions. On Mac, people typically combine a pointing device with a keyboard; on iPad and Apple Vision Pro it's an additional way to interact that doesn't replace touch, eyes, or gestures.

### Best practices

- Be consistent when responding to mouse and trackpad gestures — people expect gestures like "Swipe between pages" to work the same in every app.
- Avoid redefining systemwide trackpad gestures; people expect gestures for the Dock and Mission Control, and Mac users can customize them.
- Provide a consistent experience whether people use gestures, eyes, a pointing device, or a keyboard; people move fluidly between input types and don't want to relearn interactions per mode or app.
- Let people use the pointer to reveal and hide controls that automatically minimize or fade out (e.g., minimized Safari toolbar; playback controls in full-screen video).
- Provide a consistent result when people press and hold a modifier key while interacting (e.g., Option-drag to duplicate works identically with touch or pointer).

### Platform considerations

No additional considerations for iOS. Not supported in tvOS or watchOS.

**iPadOS** — The pointer adapts to the current context with rich visual feedback; it gives an additional way to interact, not a replacement for touch.
- Allow multiple selection in custom views when necessary: people click and drag the pointer over items to select them (expanding rectangle); standard nonlist collection views support this by default — implement it yourself in custom views (`UIBandSelectionInteraction`).
- Distinguish pointer and finger input only if it provides value (e.g., a scrubber where the pointer clicks a precise seek destination).
- Pointer shape and content effects: the default pointer is a circle that can take a system-defined or custom shape over elements (I-beam over text). Three content effects:
  - Highlight — pointer becomes a translucent rounded rectangle behind a control with gentle parallax; default for bar buttons, tab bars, segmented controls, edit menus.
  - Lift — parallax plus elevation illusion (element scales up with shadow and specular highlight); default for app icons and Control Center buttons.
  - Hover — generic; apply custom scale, tint, or shadow as the pointer moves over an element; doesn't transform the default pointer shape.
- Pointer accessories (secondary indicators combining with any pointer, e.g., resize arrows — `UIPointerAccessory`): use clear, simple images; use accessory transitions to signal state or behavior changes (plus → circle.slash for an action becoming unavailable).
- Pointer magnetism: elements attract the pointer — when moving close, the pointer starts transforming at the hit region (which extends beyond visible boundaries); when flicking, the system analyzes trajectory and pulls toward the element's center. Applied by default to lift and highlight elements and to text-entry areas (helps avoid skipping lines while selecting text), but not to hover (would feel jarring).
- Standard pointers and effects:
  - Support the system-provided content effects: highlight for a small element with a transparent background; lift for a small element with an opaque background; hover for large elements (customize scale, tint, shadow).
  - Prefer system-provided pointer appearances for standard buttons and text-entry areas.
  - Add padding to create comfortable hit regions: about 12 pt around elements with a bezel; about 24 pt around the visible edges of elements without a bezel.
  - Create contiguous hit regions for custom bar buttons — gaps cause distracting pointer reversion between buttons.
  - Specify the corner radius of a nonstandard element receiving the lift effect (e.g., a circle) so the pointer animates seamlessly (`UIPointerShape.roundedRect(_:radius:)`).
- Customizing pointers:
  - Prefer system-provided effects for custom elements that behave like standard elements (nonstandard toolbar buttons seem broken).
  - Use pointer effects consistently throughout your app (same experience in every drawing area).
  - Avoid gratuitous pointer and content effects — purely decorative changes distract and irritate.
  - Keep custom pointer shapes simple: the shape should signal the available action without drawing attention.
  - Consider custom annotations that provide useful information (X/Y values over a graph; Keynote shows width/height of a resizable image).
  - Avoid displaying instructional text with a pointer — prioritize a clear, simple interface instead.
  - For custom hover effects, consider the interplay of shadow, scale, and spacing: reserve scaling for elements that can grow without crowding neighbors (not table rows); in tight spaces use tint only; shadow without scale doesn't work (an unscaled element doesn't appear closer).

**macOS** — Standard mouse and trackpad interactions, many customizable:

| Click or gesture | Expected behavior | Mouse | Trackpad |
|---|---|---|---|
| Primary click | Select or activate an item (file, button) | ● | ● |
| Secondary click | Reveal contextual menus | ● | ● |
| Scrolling | Move content up, down, left, or right within a view | ● | ● |
| Smart zoom | Zoom in or out on content (webpage, PDF) | ● | ● |
| Swipe between pages | Navigate forward/backward between displayed pages | ● | ● |
| Swipe between full-screen apps | Navigate between full-screen apps and spaces | ● | ● |
| Mission Control (double-tap with two fingers / swipe up with three or four fingers) | Activate Mission Control | ● | ● |
| Lookup and data detectors (force click with one finger / tap with three fingers) | Display a lookup window above selected content | — | ● |
| Tap to click | Perform the primary click via a tap | — | ● |
| Force click | Quick Look or lookup window above content; variable pressure for pressure-sensitive controls | — | ● |
| Zoom in or out (pinch with two fingers) | Zoom in or out | — | ● |
| Rotate (two fingers in a circular motion) | Rotate content such as an image | — | ● |
| Notification Center (swipe from the trackpad edge) | Display Notification Center | — | ● |
| App Exposé (swipe down with three or four fingers) | Display the current app's windows in Exposé | — | ● |
| Launchpad (pinch with thumb and three fingers) | Display the Launchpad | — | ● |
| Show Desktop (spread with thumb and three fingers) | Slide all windows away to reveal the desktop | — | ● |

Standard pointers (AppKit API in parentheses): Arrow — standard selection/interaction (`arrow`); Closed hand — dragging to reposition content (`closedHand`); Contextual menu — contextual menu available, generally with Control pressed (`contextualMenu`); Crosshair — precise rectangular selection (`crosshair`); Disappearing item — dragged item will disappear when dropped, original unaffected (`disappearingItem`); Drag copy — duplicates a dragged item when dropped (Option during drag, `dragCopy`); Drag link — creates an alias when dropped (Option+Command during drag, `dragLink`); Horizontal I beam — horizontal text selection/insertion (`iBeam`); Open hand — dragging to reposition possible (`openHand`); Operation not allowed — item can't drop here (`operationNotAllowed`); Pointing hand — content is a URL link (`pointingHand`); Resize up/down/left/right and combined — resize or move a window, view, or element (`resizeUp`, `resizeDown`, `resizeLeft`, `resizeRight`, `resizeUpDown`, `resizeLeftRight`); Vertical I beam — vertical-layout text selection (`iBeamCursorForVerticalLayout`).

**visionOS** — People can attach an external pointing device or keyboard while continuing to use eyes and hands.
- If people look at an element and then move the pointer, the system brings focus to the element under the pointer — no app support needed.
- The area people are looking at determines the pointer's context; it transitions seamlessly as people shift their eyes between windows.
- With a gesture-capable device, the pointer hides while people gesture and reappears where they're looking when they move it.

### Resources

- Input events — SwiftUI; Pointer interactions — UIKit; Mouse, Keyboard, and Trackpad — AppKit

## Remotes

The Siri Remote is the primary input method for Apple TV, helping people feel connected to onscreen content from across the room. It combines specific buttons with a clickpad and touch surface supporting familiar gestures like swipe and press.

### Best practices

- Prefer standard gestures for standard actions; redefining standard remote behaviors causes confusion (custom gestures are fine within gameplay).
- Be consistent with the tvOS focus experience: combine gestures with focus in familiar ways, such as always moving focus in the same direction as the gesture.
- Provide clear feedback for gestures (e.g., lightly resting a thumb on the remote shows where to swipe down to reveal an info area).
- Define new gestures only when they make sense in your app; outside gameplay, people expect standard gestures and won't appreciate discovering new ones.
- Differentiate press and tap, and avoid responding to inadvertent taps: press is intentional (choosing a button, confirming a selection, initiating a gameplay action); tap is fine for navigation or extra info, but people tap inadvertently when resting a thumb, picking up, or handing over the remote — avoid responding to taps during live video playback.
- Consider using tap position (up, down, left, right on the touch surface) to aid navigation or gameplay — only if intuitive and discoverable.
- In almost all cases, pressing Back opens the parent of the current screen (at top level, the Apple TV Home Screen; within an app, the app-hierarchy parent, not necessarily the previous screen). Exception: during active gameplay, respond to Back by opening an in-game pause menu (Back while the pause menu is open closes it and resumes); press and hold Back goes to the Home Screen from anywhere.
- Respond correctly to Play/Pause during media playback: play, pause, or resume.

### Gestures and buttons

- Swipe: scroll effortlessly through many items — movement starts fast then slows based on swipe strength; swiping up or down on the remote's edge speeds through items very quickly.
- Press: activate a control or select an item; people press before swiping to activate scrubbing mode.

| Button or area | Expected behavior in an app | Expected behavior in a game |
|---|---|---|
| Touch surface (swipe) | Navigates; changes focus | Directional pad behavior |
| Touch surface (press) | Activates a control or item; navigates deeper | Primary button behavior |
| Back | Returns to previous screen; exits to Apple TV Home Screen | Pauses/resumes gameplay; returns to previous screen, main game menu, or Home Screen |
| Play/Pause | Starts, pauses, or resumes media playback | Secondary button behavior; skips intro video |

**Compatible remotes** — Some Apple TV–compatible remotes include buttons for browsing live TV or channel-based content (e.g., an EPG):
- Pressing a "guide" or "browse" button should open your EPG; while viewing it, "page up"/"page down" should navigate the guide — avoid other responses while people browse. Tapping the upper or lower touch surface also browses the EPG.
- If your app doesn't provide an EPG, the system routes these presses to the device's default guide app.
- While content plays, respond to "page up"/"page down" by changing the channel — people expect different behavior when browsing an EPG vs. viewing content.

### Platform considerations

Not supported in iOS, iPadOS, macOS, visionOS, or watchOS.
