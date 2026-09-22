> Source: https://developer.apple.com/design/human-interface-guidelines/activity-views
> Source: https://developer.apple.com/design/human-interface-guidelines/home-screen-quick-actions
> Source: https://developer.apple.com/design/human-interface-guidelines/ornaments
> Source: https://developer.apple.com/design/human-interface-guidelines/toolbars

# Activity views, Home Screen quick actions, ornaments, toolbars

## Activity views
An activity view — often called a share sheet — presents a range of tasks that people can perform in the current context.

Activity views present sharing activities (like messaging) and actions (like Copy and Print) plus quick access to frequently used apps. People typically reveal a share sheet by choosing an Action button while viewing a page or document, or after selecting an item; it appears as a sheet or a popover depending on device and orientation. You can provide app-specific activities (Photos: Copy Photo, Add to Album, Adjust Location) — by default the system lists them before multi-app/system actions like Add to Files or AirPlay, and people can edit the list. You can also build share and action app extensions for use in other apps; macOS provides no activity view but does support these extensions.

### Best practices
- Avoid creating duplicate versions of common actions already in the activity view (a duplicate Print is confusing); give similar app-specific functionality a custom title like "Print Transaction."
- Consider using a symbol to represent a custom activity (SF Symbols); if you create a custom interface icon, center it in an area measuring about 70x70 pixels.
- Write a succinct, descriptive title for each custom action — a single verb or brief verb phrase; long titles wrap and may truncate. Don't include your company or product name in action titles (the share sheet shows a share activity's title — typically a company name — below its icon automatically).
- Make activities appropriate for the current context: you can't reorder system-provided tasks, but you can exclude inapplicable ones (exclude Print if printing doesn't make sense) and choose which custom tasks to show.
- Use the Share button to display an activity view — people expect system activities there; don't provide an alternative way to do the same thing.

### Share and action extensions
- Share extensions share information from the current context with apps, social media accounts, and services; action extensions initiate content-specific tasks (bookmark, copy link, edit an inline image, show text in another language) without leaving the context.
- Presentation: iOS/iPadOS — in the share sheet when people choose an Action button; macOS — share extensions via the toolbar Share button or Share in a context menu; action extensions by hovering the pointer over embedded content (like an image in a Mail compose window), a toolbar button, or a Finder quick action.
- For a share extension, prefer the system-provided composition view; for an action extension, include your app name and elements of your app's interface so people see the relationship.
- Streamline and limit interaction — extensions that finish in a few steps (a share extension posting an image with one tap) are appreciated.
- Avoid placing a modal view above your extension (the system already displays it modally; alerts are OK).
- A share extension automatically uses your app icon; for an action extension, prefer a symbol or interface icon that clearly identifies the task.
- Use your main app to denote progress of a lengthy operation — the extension dismisses when the task completes, so continue long tasks in the background with a status check in the main app. Don't notify people just because a task completes (notifications are for problems).

### Platform considerations
- Not supported in macOS, tvOS, or watchOS (macOS supports share/action extensions only, as above). No additional considerations for iOS, iPadOS, or visionOS.

### Resources
- UIActivityViewController, UIActivity — UIKit; App Extension Support — Foundation

## Home Screen quick actions
Home Screen quick actions give people a way to perform app-specific actions from the Home Screen.

People touch and hold an app icon to reveal the menu (on 3D Touch devices, press with increased pressure); the menu also lists system items for removing the app and editing the Home Screen. Each quick action includes a title, an interface icon on the left or right (depending on the app's Home Screen position), and an optional subtitle; title and subtitle are always left-aligned in left-to-right languages. Apps can dynamically update quick actions (Messages shows most recent conversations).

### Best practices
- Create quick actions for compelling, high-value tasks (Maps: search near current location, get directions home without opening the app). People expect at least one useful quick action; you can provide a total of four.
- Avoid unpredictable changes — dynamic updates based on location, recent activity, time of day, or settings are fine, but actions must change in ways people can predict.
- Provide a succinct title that instantly communicates the result ("Directions Home," "Create New Contact," "New Message"); add a subtitle for context (Mail uses it for unread counts). Don't include your app name or extraneous information; keep text short to avoid truncation; account for localization.
- Provide a familiar interface icon for each quick action — prefer SF Symbols; for a custom icon use the Quick Action Icon Template in Apple Design Resources for iOS and iPadOS.
- Don't use an emoji in place of a symbol or interface icon — quick action symbols are monochromatic and change appearance in Dark Mode to maintain contrast.

### Platform considerations
- No additional considerations for iOS or iPadOS. Not supported in macOS, tvOS, visionOS, or watchOS.

### Resources
- Add Home Screen quick actions — UIKit

## Ornaments
In visionOS, an ornament presents controls and information related to a window, without crowding or obscuring the window's contents.

An ornament floats in a plane parallel to its window, slightly in front along the z-axis; it moves with the window and its contents don't scroll with the window's contents. Ornaments can appear on any window edge and contain buttons, segmented controls, and other views. The system uses ornaments for toolbars, tab bars, and video playback controls; you can use one to create a custom component.

### Best practices
- Use an ornament for frequently needed controls or information in a consistent location that doesn't clutter the window (Music: Now Playing controls in a predictable spot).
- Keep an ornament visible in general — hiding can make sense when people dive into content (watching a video, viewing a photo), but people appreciate consistent access.
- With multiple ornaments, prioritize the window's overall visual balance; constrain the total number to avoid visual weight and perceived complexity; relocate removed ornament elements into the main window.
- Keep an ornament's width the same as or narrower than its window — a wider ornament can interfere with a tab bar or other vertical content on the window's side.
- Consider borderless buttons in an ornament — the glass background usually provides enough contrast, and the system automatically applies the hover effect to borderless buttons.
- Use system-provided toolbars and tab bars unless you need custom components — in visionOS they automatically appear as ornaments.

### Platform considerations
- visionOS only. Not supported in iOS, iPadOS, macOS, tvOS, or watchOS.

### Resources
- ornament(visibility:attachmentAnchor:contentAlignment:ornament:) — SwiftUI

## Toolbars
A toolbar provides convenient access to frequently used commands, controls, navigation, and search.

A toolbar consists of one or more sets of controls arranged horizontally along the top or bottom edge of a view, grouped into logical sections. It includes three content types: the current view's title; navigation controls (back/forward, search fields); and actions, or bar items (buttons, menus). In contrast, a tab bar is specifically for navigating between areas of an app.

### Best practices
- Choose items deliberately to avoid overcrowding — people must be able to distinguish and activate each item. Define which items move to the overflow menu as the toolbar narrows.
- In macOS and iPadOS the system automatically adds an overflow menu when items no longer fit — don't add one manually, and avoid layouts that overflow by default.
- Add a More menu for additional actions only if you really need it; prioritize less important actions for it.
- In iPadOS and macOS, consider letting people customize the toolbar — especially useful in apps with many items, advanced functionality not everyone needs, or long usage sessions (e.g., a range of editing actions).
- Reduce toolbar backgrounds and tinted controls — they can interfere with system background effects; use the content layer to inform color and appearance, and a ScrollEdgeEffectStyle to distinguish toolbar from content area.
- Avoid applying a similar color to toolbar item labels and content layer backgrounds; prefer the default monochromatic appearance over bright, colorful content.
- Prefer standard components (default concentric corner radii with bar corners); custom components must also use a concentric corner radius.
- Consider temporarily hiding toolbars for a distraction-free experience — do so contextually and offer reliable ways to restore hidden elements.

### Titles
- Provide a useful title for each window; you can leave the title area empty when a title is redundant (single Notes window).
- Don't title windows with your app name — it says nothing about the content hierarchy.
- Write a concise title — a word or short phrase, under 15 characters long, leaving room for other controls.

### Navigation
- A toolbar with navigation controls appears at the top of a window; in iOS, a navigation-specific toolbar is sometimes called a navigation bar.
- Use the standard Back and Close buttons with standard symbols — no "Back" or "Close" text labels; custom versions must look and behave the same, match the interface, and be implemented consistently.

### Actions
- Provide actions supporting the main tasks people perform; prioritize the most likely commands (usually the most frequent, or those mapped to the highest-level objects).
- Make each control's meaning clear — don't make people guess; prefer simple, recognizable symbols over text, except for actions like edit that aren't well represented by symbols.
- Prefer system-provided symbols without borders — familiar, automatically colored and vibrant, consistent interactions; the section provides the container and the system defines hover and selection states.
- Use the .prominent style for key actions like Done or Submit — separated and tinted for a clear focal point. Only one primary action, placed on the trailing side.

### Item groupings
Items can sit in three locations: leading edge, center area, trailing edge.
- Leading edge: return-to-previous controls and sidebar show/hide, followed by the view title, then an optional document menu (Duplicate, Rename, Move, Export). Leading-edge items aren't customizable.
- Center area: common, useful controls (and the view title if not on the leading edge); in macOS/iPadOS people can add, remove, and rearrange items if you enable customization, and items automatically collapse into the system-managed overflow menu when the window shrinks.
- Trailing edge: important items that must remain available, inspector-opening buttons, an optional search field, the More menu (which supports customization), and the primary action like Done — visible at all window sizes.
- Pin items to leading, center, or trailing, and insert space between buttons where appropriate.
- Group items logically by function and frequency of use (Keynote: presentation-level, playback, object-insertion sections).
- Group navigation controls and critical actions (Done, Close, Save) in dedicated, familiar, visually distinct sections.
- Keep groupings and placement consistent across platforms to build familiarity and trust.
- Minimize the number of groups — too many feel cluttered; aim for a maximum of three.
- Keep actions with text labels separate from symbol actions — mixing them creates the illusion of one combined action, and multiple text labels can run together. Insert fixed space between buttons (`UIBarButtonItem.SystemItem.fixedSpace`).

### Platform considerations
- No additional considerations for tvOS.
- **iOS**: Prioritize only the most important items in the main toolbar area — space is very limited; put additional items in a More menu. Use a large title to help people stay oriented: it transitions to a standard title on scroll and back to large at the top (`prefersLargeTitles`).
- **iPadOS**: Consider combining a toolbar with a tab bar — they can coexist in the same horizontal space at the top, useful for navigating a few main areas while keeping full window width for content.
- **macOS**: The toolbar resides in the window frame at the top, below or integrated with the title bar; window titles can display inline with controls, and toolbar items have no bezel. Make every toolbar item available as a menu bar command — people can customize or hide the toolbar. The reverse isn't required: not every menu command warrants a toolbar item.
- **visionOS**: The system-provided toolbar appears along the bottom edge of a window, above the window-management controls, in a parallel plane slightly in front along the z-axis.
  - A variable blur in the bar background keeps items legible as content scrolls behind, while the glass material stays uniform and undivided.
  - Supply a symbol or a text label per item; when people look at a symbol item, visionOS reveals its text label.
  - Prefer the system-provided toolbar — consistent, optimized for eye and hand input, and automatically positioned relative to its window.
  - Avoid a vertical toolbar — tab bars are vertical in visionOS and a vertical toolbar would confuse people.
  - Prevent windows from resizing below the toolbar's width — with no menu bar, the toolbar must reliably expose essential controls at any size.
  - If your app enters a modal state, consider contextually relevant toolbar controls (different from the main window's), and reinstate the standard toolbar on exit.
  - Avoid pull-down menus in a toolbar — hard to discover, they clutter the interface and might obscure the window controls below the bottom edge.
- **watchOS**: A toolbar button offers important functionality in a view displaying related content. Place buttons in the top corners or along the bottom; buttons above scrolling content always remain visible as content scrolls under them. Alternatively, place a button in the scrolling view — hidden until people scroll up (discovery is automatic since people frequently scroll to the top). Use a scrolling toolbar button for an important action that isn't a primary app function (Mail: New Message at the top of the Inbox).

### Resources
- Toolbars — SwiftUI; UIToolbar — UIKit; NSToolbar — AppKit; topBarLeading/topBarTrailing/bottomBar and primaryAction — SwiftUI placement; UIBarButtonItem.SystemItem.fixedSpace — UIKit
