> Source: https://developer.apple.com/design/human-interface-guidelines/windows
> Source: https://developer.apple.com/design/human-interface-guidelines/panels
> Source: https://developer.apple.com/design/human-interface-guidelines/popovers

# Windows, panels, popovers

## Windows
A window presents UI views and components in your app or game.

In iPadOS, macOS, and visionOS, windows define the visual boundaries of app content, separate it from other areas of the system, and enable multitasking workflows. Apps use two window types: a **primary window** (main navigation and content, with associated actions) and an **auxiliary window** (a specific task or area; no navigation to other app areas; typically a close button for after the task completes).

### Best practices
- Make windows adapt fluidly to different sizes to support multitasking and multiwindow workflows.
- Choose the right moment to open a new window: opening content in a separate window helps people multitask or preserve context (Mail opens a Compose window so the new message and existing email stay visible), but excessive new windows create clutter and confusion. Avoid opening new windows as default behavior unless it makes sense for your app.
- Consider providing an option to view content in a new window (for example, a command in a context menu or the File menu).
- Avoid creating custom window UI — no custom frames or controls, and don't replicate the system-provided appearance; imperfect matches make your app feel broken.
- Use the term "window" in user-facing content; different terms — including "scene", which refers to implementation — confuse people.

### Platform considerations
- **Not supported in iOS, tvOS, or watchOS.**
- **iPadOS**: Windows present in one of two ways, per people's choice in Multitasking & Gestures settings — full screen (fill the screen; switch via the app switcher) or windowed (freely resizable, multiple windows onscreen, repositionable; the system remembers size and placement even after the app closes).
  - Make sure window controls don't overlap toolbar items: window controls appear at the leading edge of the toolbar when windowed, so move leading-edge buttons inward when controls appear instead of placing them directly at the edge.
  - Consider letting people use a gesture to open content in a new window (for example, pinching to expand a Notes item into a new window).
  - To let people view a single file, you can present it without creating your own window — but your app must still support multiple windows.
- **macOS**: People typically run several apps at once, viewing windows from multiple apps on one desktop and moving, resizing, minimizing, and revealing them frequently.
  - Anatomy: a frame (above the body area; can include window controls and a toolbar; people drag it to move the window) and a body area; windows often resize by dragging their edges. A rare bottom bar can appear below body content.
  - Window states:

| State | Meaning |
|---|---|
| Main | The frontmost window people are viewing; only one main window per app |
| Key | The active window accepting input; only one key window onscreen at a time — usually the front app's main window, but a panel floating above it can be key; people click a window to make it key |
| Inactive | A window that's not in the foreground |

  - The system differentiates states visually: the key window uses color in its title-bar close/minimize/zoom options, while inactive windows (and main windows that aren't key) use gray; inactive windows also don't use vibrancy, appearing subdued. Some windows — typically panels like Colors or Fonts — become key only when people click the title bar or a component requiring keyboard input.
  - Make sure custom windows use the system-defined appearances; with system components, backgrounds and buttons update automatically on state changes — with custom implementations, you must do this work yourself.
  - Avoid critical information or actions in a bottom bar, because people often relocate windows in a way that hides the bottom edge. If you include one, show only a small amount of information related to the window's contents or selected item (like Finder's status bar); for more information, use an inspector on the trailing side of a split view.
- **visionOS**: Two main window styles — a default **window** and a volumetric **volume** — both display 2D and 3D content; people can view multiple windows and volumes at once in the Shared Space and a Full Space. (A plain style is also available: like default, but the upright plane doesn't use the glass background.) The system defines the initial position of the first window or volume; people can move them to new locations.

  **Windows**
  - A window is an upright plane with an unmodifiable glass background, a close button, a window bar, and resize controls; it can also include a Share button, tab bar, toolbar, and one or more ornaments. Dynamic scale is used by default so size appears consistent regardless of proximity.
  - Prefer a window for a familiar interface and familiar tasks, reserving immersive experiences for meaningful content and activities; for bounded 3D content like a game board, consider a volume.
  - Retain the window's glass background — removing it makes UI elements and text less legible and no longer related to each other; an opaque background obscures surroundings and feels constricting and heavy.
  - Choose an initial window size that minimizes empty areas:

| Property | Value |
|---|---|
| Default window size | 1280x720 pt |
| Initial placement | About 2 m in front of the wearer |
| Apparent width | About 3 m |

  - Aim for an initial shape that suits the content (Keynote is wide because slides are wide; Safari is tall because webpages are long; a tower-building game opens taller than a driving game).
  - Choose a minimum and maximum size for each window so your layout holds at all sizes — otherwise people can shrink a window until UI elements overlap or grow it until your app becomes unusable.
  - Minimize the depth of 3D content in a window: the system clips content that extends too far from the window's surface; use a volume for greater depth.

  **Volumes**
  - A volume displays 2D or 3D content people can view from any angle; it includes window-management controls, but its close button and window bar shift position to face the viewer as they move.
  - Prefer a volume for rich 3D content; use a window for a familiar, UI-centric interface.
  - Place 2D content so it looks good from multiple angles — perspective changes as people move around a volume; use an attachment to pin 2D content to specific areas of 3D content.
  - In general, use dynamic scaling so content stays legible and easy to interact with at any distance; use fixed scaling (the default) when content represents a real-world object, like a product in a retail app.
  - Take advantage of the default baseplate appearance (visionOS 2 and later): the system displays a gentle glow around the volume's border when people look at it, helping them discern edges and find the resize control. Skip the glow if your content is full bleed or you display a custom baseplate.
  - Consider offering high-value content in an ornament (visionOS 2 and later) to reduce clutter and elevate important views or controls; use an attachment anchor (like topBack or bottomFront) so the ornament keeps its position relative to the viewer. Don't place an ornament on the same edge as a toolbar or tab bar, and prefer creating only one additional ornament.
  - Choose an alignment supporting the interaction: a baseplate parallel to the floor works for content people don't interact with much; tilting to match where the person is looking keeps content comfortably usable, even when reclining.

### Resources
- Windows, WindowGroup — SwiftUI; UIWindow — UIKit; NSWindow — AppKit

## Panels
In a macOS app, a panel typically floats above other open windows providing supplementary controls, options, or information related to the active window or current selection.

A panel has a less prominent appearance than the main window and can use a dark, translucent style for a heads-up display (HUD) experience. On other platforms, consider a modal view to present supplementary content relevant to the current task or selection.

### Best practices
- Use a panel to give people quick access to important controls or information related to the content they're working with (for example, controls affecting the selected item in the active document or window).
- Consider a panel for inspector functionality — it displays details of the current selection and updates automatically when the item changes. Use a regular window for an Info window (fixed contents even when the selection changes); depending on layout, a split view pane can also present an inspector.
- Prefer simple adjustment controls in a panel: sliders and steppers give direct control; avoid controls requiring typing text or selecting items to act upon, which take multiple steps.
- Write a brief title describing the panel's purpose — a noun or noun phrase with title-style capitalization ("Fonts", "Colors", "Inspector"); the title bar lets people position the panel where they want.
- Show and hide panels appropriately: when your app becomes active, bring all its open panels to the front; when it's inactive, hide them all.
- Avoid including panels in the Window menu's documents list — show/hide commands are fine, but panels aren't documents or standard app windows.
- In general, avoid making a panel's minimize button available — panels display only when needed and disappear when the app is inactive.
- Refer to panels by title: in menus, use the title without the word "panel" ("Show Fonts", "Show Colors"); in help documentation, use the title, appending "window" only when it adds clarity ("Fonts window", "Colors window").

**HUD-style panels**
- Prefer standard panels — a HUD with no logical reason for its presence distracts or confuses, and may not match the current appearance setting. Use a HUD only in a media-oriented app (movies, photos, slides), when a standard panel would obscure essential content, or when you don't need controls (most system-provided controls don't match a HUD's appearance, except the disclosure triangle).
- Maintain one panel style when your app switches modes (if you use a HUD in full-screen mode, keep the HUD style when leaving full screen).
- Use color sparingly in HUDs — small amounts of high-contrast color highlight important information; too much color in the dark appearance is distracting.
- Keep HUDs small and unobtrusively useful: don't let a HUD obscure the content it adjusts or compete with it for attention.

### Platform considerations
- **Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.**

### Resources
- NSPanel — AppKit; hudWindow — AppKit

## Popovers
A popover is a transient view that appears above other content when people click or tap a control or interactive area.

### Best practices
- Use a popover to expose a small amount of information or functionality — it disappears after people interact with it, so limit it to a few related tasks (a calendar event popover for changing date, time, or calendar).
- Consider popovers when you want more room for content — sidebars and panels take up a lot of space, so temporary content in a popover streamlines your interface.
- Position popovers appropriately: the arrow should point as directly as possible to the element that revealed it, and the popover shouldn't cover that element or essential content.
- Use a Close button (including Cancel or Done) for confirmation and guidance only, like clarity about exiting with or without saving. Otherwise, a popover closes when people click or tap outside its bounds or select an item; with multiple selections, keep it open until people explicitly dismiss it.
- Always save work when automatically closing a nonmodal popover — people can unintentionally dismiss it by tapping outside its bounds; discard work only when people click or tap an explicit Cancel button.
- Show one popover at a time; never show a cascade or hierarchy of popovers (one emerging from another) — close the open one before showing a new one.
- Don't show another view over a popover, except for an alert.
- When possible, let people close one popover and open another with a single click or tap — especially desirable when several bar buttons each open a popover.
- Avoid making a popover too big: make it only big enough to display its contents and point to its origin; the system can adjust size to fit the interface.
- Provide a smooth, animated transition when changing a popover's size (condensed and expanded views of the same information), so it doesn't look like a new popover replaced the old one.
- Avoid the word "popover" in help documentation — refer to the task or selection ("Select the Show button," not "Select the Show button at the bottom of the popover").
- Avoid using a popover to show a warning — people can miss a popover or accidentally close it; use an alert instead.

### Platform considerations
- No additional considerations for visionOS. **Not supported in tvOS or watchOS.**
- **iOS, iPadOS**: Avoid displaying popovers in compact views. Make your app adjust its layout based on the size class of the content area; reserve popovers for wide views and present information in a full-screen modal view (like a sheet) in compact views.
- **macOS**: A popover can be detachable — dragging it converts it into a separate panel that remains visible while people interact with other content. Consider letting people detach popovers, and make minimal appearance changes to a detached popover to help them maintain context.

### Resources
- popover(isPresented:attachmentAnchor:arrowEdge:content:) — SwiftUI; UIPopoverPresentationController — UIKit; NSPopover — AppKit
