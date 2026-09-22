> Source: https://developer.apple.com/design/human-interface-guidelines/menus
> Source: https://developer.apple.com/design/human-interface-guidelines/context-menus
> Source: https://developer.apple.com/design/human-interface-guidelines/edit-menus
> Source: https://developer.apple.com/design/human-interface-guidelines/dock-menus
> Source: https://developer.apple.com/design/human-interface-guidelines/the-menu-bar

# Menus, context menus, edit menus, dock menus, the menu bar

## Menus
A menu reveals its options when people interact with it, making it a space-efficient way to present commands in your app or game.

Every menu item represents a command, option, or state that affects the current selection or context. The labeling and organization guidance here applies to all types of menus.

### Best practices

**Labels**
- Write a label that clearly and succinctly describes each item; use a verb or verb phrase for actions (View, Close, Select). An item may include a symbol if it clarifies meaning; an app menu item can display its keyboard command (games rarely do).
- Use title-style capitalization for consistency with platform experiences.
- Remove articles like "a," "an," and "the" from labels — they lengthen labels without adding clarity.
- Show when a menu item is unavailable: dim it and make it unresponsive. If all items are unavailable, keep the menu itself available so people can open it and learn the commands.
- Append an ellipsis (…) to a label when the action requires more information or additional choices before completing, typically in another view.

**Icons**
- Represent common actions consistently using standard system icons (Share, Print, Search).
- Use menu item icons sparingly and with purpose — to highlight common actions, key features, file system locations, connected devices, visual concepts (rotating, flipping), and user-generated content. Don't display an icon if you can't find one that clearly represents the item.
- Apply a uniform visual treatment across items in the same group — icons for all items or none.

**Organization**
- List important or frequently used items first — people scan from the top.
- Group logically related items (Copy/Cut/Paste) and separate groups with a separator.
- Keep logically related commands in the same group even if importance differs (Paste and Match Style belongs with Copy, Cut, and Paste).
- Be mindful of menu length — long menus make people miss commands. Divide into separate menus or use a submenu. Exception: user-defined or dynamically generated content (History, Bookmarks) can be long; scrolling is acceptable.

**Submenus**
- Use submenus sparingly — each adds complexity and hides items. Consider one when a term appears in more than two items in a group (a single "Sort by" item with Date, Score, and Time in the submenu).
- Limit depth and length: restrict to a single level; if a submenu contains more than about five items, consider a new menu.
- Keep a submenu available even when its nested items are unavailable.
- Prefer a submenu to indenting menu items — indentation is inconsistent with the system and doesn't express relationships.

**Toggled items**
- Consider a changeable label describing the current state (Show Map ↔ Hide Map).
- Include a verb if a changeable label isn't clear enough (Turn HDR On instead of HDR On).
- If necessary, display both items so people can view both states (Take Account Online / Take Account Offline, with only the relevant one available).
- Consider a checkmark to show an attribute currently in effect — easy to scan for.
- Consider a menu item that removes multiple toggled attributes at once (such as Plain for all text formatting).

**In-game menus**
- Let players navigate in-game menus using the platform's default interaction method (touch in iOS/iPadOS, direct and indirect gestures in visionOS).
- Keep menus easy to open and read on all platforms; when scaling content to another screen makes menus too small, modify tap-target sizes and consider alternative ways to communicate the menu's content.

### Platform considerations
- No additional considerations for macOS, tvOS, or watchOS.
- **iOS, iPadOS** — menus can use three layouts (`preferredElementSize`):

| Layout | Description |
|---|---|
| Small | Row of four items at the top (symbol or icon only, no label) above a list of remaining items |
| Medium | Row of three items at the top (symbol above a short label) above a list of remaining items |
| Large (default) | All items in a list |

  - Choose small or medium to streamline choices: medium suits three important frequent actions (Notes: Scan, Lock, Pin); small only for closely related actions that appear as a group (Bold, Italic, Underline, Strikethrough), using recognizable symbols.
- **visionOS**: Supports the small and large layouts; present a menu from 3D content with a SwiftUI view. An open menu can appear outside window boundaries (as in macOS). Apply a breakthrough effect so the menu stays visible over occluding content.
  - Display a menu near the content it controls — people might miss the item's effect if the content is far away.
  - Prefer the subtle breakthrough effect (blends with surroundings, maintains legibility). Use prominent only when the menu must dominate the scene — it can disrupt the experience and cause discomfort; use none to fully occlude the menu behind 3D content (e.g., puzzle barriers), though this can make it hard to see and access.

### Resources
- Menu — SwiftUI; Menus and shortcuts — UIKit; Menus — AppKit; preferredElementSize — UIKit

## Context menus
A context menu provides access to functionality that's directly related to an item, without cluttering the interface.

People reveal it by selecting content and performing an action: touch or pinch and hold (visionOS, iOS, iPadOS), Control-click with a pointing device (macOS, iPadOS), or secondary click on a Magic Trackpad (macOS, iPadOS).

### Best practices
- Prioritize relevancy: a context menu is for commands people are most likely to need now — not advanced or rarely used items (Mail's Inbox context menu has reply and move, not message editing, mailbox management, or filtering).
- Aim for a small number of items — long menus are hard to scan and scroll.
- Support context menus consistently throughout your app; providing them in some places but not others makes people think something is broken.
- Always make context menu items available in the main interface, too (message-view toolbar in iOS/iPadOS; menu bar menus in macOS).
- If you use submenus, keep them to one level and give them intuitive titles that predict contents.
- Hide unavailable menu items, don't dim them — unlike regular menus, a context menu shows only actions relevant to the current selection. macOS exception: Cut, Copy, and Paste may appear unavailable when they don't apply.
- Place the most frequently used items where people encounter them first (nearest where the finger or pointer revealed the menu); reverse the order if the menu opens above rather than below the content.
- Show keyboard shortcuts in the app's main menus, not in context menus — redundant.
- Follow separator best practices: no more than about three groups in a context menu.
- In iOS, iPadOS, and visionOS, warn people about destructive items: list them last and mark them destructive so the system can show them in red.

### Content
- A context menu seldom displays a title; include one only if it clarifies the effect (Mail's Mark menu titles the number of selected messages). Every item needs a short label that clearly describes what it does.
- Represent menu item actions with familiar icons — use the same icons as the system for Copy, Share, Delete.

### Platform considerations
- No additional considerations for tvOS. Not supported in watchOS.
- **iOS, iPadOS**: Provide either a context menu or an edit menu for an item, not both — providing both confuses people and makes intent hard to detect. In iPadOS, consider a context menu for creating new objects (Files creates a folder via long press in empty space or secondary click). A context menu can display a preview of the current content near the commands; people can tap the preview to open it or drag it elsewhere. Prefer a graphical preview that clarifies the target (condensed version of actual content), and make the preview look good as it animates — adjust the clipping path to match the preview image shape (rounded corners) so contours don't appear to change.

  Resources: UIContextMenuInteractionDelegate (preview animation).
- **macOS**: A context menu is sometimes called a contextual menu.
- **visionOS**: Consider a context menu instead of a panel or inspector window for frequently used functionality, keeping the space uncluttered. Avoid letting the menu's height exceed the window height — a too-tall menu could obscure system components above and below the window edges. Match item count to how people use the app: specialist apps may warrant large menus; simple apps benefit from short, quick-to-scan menus.

### Resources
- contextMenu(menuItems:) — SwiftUI; UIContextMenuInteraction — UIKit; popUpContextMenu(_:with:for:) — AppKit

## Edit menus
An edit menu lets people make changes to selected content in the current view, in addition to offering related commands like Copy, Select, Translate, and Look Up.

Edit-menu commands apply to many types of selectable content — text, images, files, objects like contact cards, charts, or map locations. In iOS, iPadOS, and visionOS, the system automatically detects the data type of a selection and can add a related action (selecting an address adds Get directions).

Platform behavior: iOS shows a compact horizontal list on touch and hold or double-tap, expandable to a context menu via a trailing chevron. iPadOS shows the compact horizontal list for touch, but opens directly in a context menu for keyboard or pointing device. macOS exposes editing commands in a context menu and the menu bar's Edit menu. visionOS opens a horizontal bar via pinch and hold, or a context menu. No edit menu in tvOS or watchOS.

### Best practices
- Prefer the system-provided edit menu — people know its contents and behavior; a custom menu with the same commands is redundant and confusing (see UIResponderStandardEditActions for standard commands).
- Let people reveal the edit menu with the system-defined interactions they already know (touch and hold, pinch and hold, secondary click) — people don't appreciate learning custom interactions for standard tasks.
- Offer commands relevant to the current context, removing or dimming those that don't apply (no Copy or Cut with nothing selected; no Paste with nothing to paste).
- List custom commands near the relevant system-provided ones (custom formatting after system commands in the format section); avoid overwhelming people with too many custom commands.
- When it makes sense, let people select and copy noneditable text (image captions, social media statuses); let people copy content text, but not control labels.
- Support undo and redo when possible — edit menus don't require confirmation, so undo/redo is the recovery path.
- Avoid implementing other controls that duplicate edit menu functions — redundant controls crowd the interface.
- Differentiate deletion types when necessary: Delete behaves like the Delete key; Cut copies to the pasteboard before deleting.
- Create short labels for custom commands — verbs or short verb phrases.

### Platform considerations
- Not supported in tvOS or watchOS. No additional considerations for visionOS.
- **iOS, iPadOS**: Ensure the menu works well in both styles — compact horizontal for Multi-Touch, vertical for keyboard or pointing device. Adjust the menu's placement if necessary: default is above or below the insertion point or selection with a visual indicator pointing to the target; you can change position but not the menu's shape or pointer.
- **macOS**: See the Edit menu (below) for item order.

### Resources
- UIEditMenuInteraction — UIKit; NSMenu — AppKit; UIResponderStandardEditActions — UIKit

## Dock menus
On a Mac, people can secondary click an app's or game's icon in the Dock to reveal a Dock menu, which presents both system-provided and custom items.

System-provided items can vary depending on whether the app is open (Safari's Dock menu includes viewing a current window or creating a new one). iOS and iPadOS don't support Dock menus — the similar menu there is Home Screen quick actions (long press an app icon).

### Best practices
- Label Dock menu items succinctly and organize them logically (see Menus).
- Make custom Dock menu items available elsewhere, too (menu bar menus, in-interface) — not everyone uses a Dock menu.
- Prefer high-value custom items: list currently or recently open windows for quick jumping, plus actions most useful when the app isn't frontmost or has no open windows (Mail: get new mail, compose new message).

### Platform considerations
- macOS only. Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.

### Resources
- applicationDockMenu(_:) — AppKit

## The menu bar
On a Mac or an iPad, the menu bar at the top of the screen displays the top-level menus in your app or game.

iPad menus match Mac in order and item sets, and keyboard shortcuts use the same patterns — adopting the expected structure helps people understand the menu bar on iPad immediately.

### Anatomy
When present, menus appear in this order:
1. YourAppName (short version of your app's name) — 2. File — 3. Edit — 4. Format — 5. View — 6. App-specific menus — 7. Window — 8. Help

macOS also includes the Apple menu (leading side) and menu bar extras (trailing side).

### Best practices
- Support the default system-defined menus and their ordering — people expect familiar order, and the system implements many standard items for you.
- Always show the same set of menu items; disable unavailable actions instead of hiding them, so people can learn what the app supports.
- Represent menu item actions with familiar icons — use system icons for Copy, Share, Delete.
- Support the keyboard shortcuts defined for the standard menu items you include (Copy, Cut, Paste, Save, Print); define custom shortcuts only when necessary.
- Prefer short, one-word menu titles (display sizes and menu bar extras affect spacing); for multiword titles use title-style capitalization.

**App menu** — items that apply to the app as a whole; the menu bar shows your app name in bold.

| Menu item | Action | Guidance |
|---|---|---|
| About YourAppName | Displays the About window (copyright, version) | Prefer a short name of 16 characters or fewer; no version number; display first with a separator after it |
| Settings… | Opens your settings window, or the app's page in iPadOS Settings | App-level settings only; document-specific settings go in the File menu |
| Optional app-specific items | Custom app-level configuration actions | List after Settings, within the same group |
| Services (macOS only) | Submenu of system and other-app services for the current context | — |
| Hide YourAppName (macOS only) | Hides the app and its windows, activates the most recently used app | Use the same short app name as the About item |
| Hide Others (macOS only) | Hides all other open apps and their windows | — |
| Show All (macOS only) | Shows all other open apps behind your app's windows | — |
| Quit YourAppName | Quits the app; Option changes it to Quit and Keep Windows | Use the same short app name as the About item |

**File menu** — commands for managing files or documents; rename or eliminate it if your app handles no files.

| Menu item | Action / guidance |
|---|---|
| New Item | Creates a new document, file, or window; name the item type (Calendar uses Event and Calendar) |
| Open | Opens the selected item or presents a selection interface; append an ellipsis if a separate interface is required |
| Open Recent | Submenu of recently opened documents plus Clear Menu; list recognizable names (not file paths), most recently opened first |
| Close | Closes the current window or document; Option → Close All; in a tab-based window, Close Tab replaces Close (consider adding Close Window) |
| Close Tab | Closes the current tab; Option → Close Other Tabs |
| Close File | Closes the current file and all its associated windows; support if your app opens multiple views of the same file |
| Save | Saves the current document; autosave periodically so people don't need File > Save; for a new document prompt for name and location; prefer a pop-up menu for choosing a format in the Save sheet |
| Save All | Saves all open documents |
| Duplicate | Duplicates the document, leaving both open; Option → Save As; prefer Duplicate over Save As, Export, Copy To, Save To (they don't clarify the file relationship) |
| Rename… | Lets people change the document's name |
| Move To… | Prompts for a new location |
| Export As… | Prompts for name, output location, and format; the exported file doesn't open; reserve for formats your app doesn't typically handle |
| Revert To | With autosaving on: submenu of recent versions and the version browser; a restored version replaces the current document |
| Page Setup… | Print parameters panel (paper size, orientation); include only for document-specific parameters — global or frequently changed ones (printer name, copies) belong in the Print panel |
| Print… | Opens the standard Print panel (print, fax, save as PDF) |

**Edit menu** — commands for changing content and interacting with the Clipboard; useful even in non-document apps. Determine whether Find items belong here or in the File menu (searching for files/objects → File).

| Menu item | Action / guidance |
|---|---|
| Undo / Redo | Reverses the previous operation / the previous Undo; clarify the target (Undo Typing, Redo Paste and Match Style) |
| Cut | Removes the selected data to the Clipboard |
| Copy | Duplicates the selected data to the Clipboard |
| Paste | Inserts Clipboard contents at the insertion point; contents remain unchanged, so people can paste repeatedly |
| Paste and Match Style | Pastes, matching surrounding text style |
| Delete | Removes the selection without using the Clipboard; prefer Delete over Erase or Clear (consistent with the Delete key) |
| Select All | Highlights all selectable content |
| Find | Submenu: Find, Find and Replace, Find Next, Find Previous, Use Selection for Find, Jump to Selection |
| Spelling and Grammar | Submenu: Show Spelling and Grammar, Check Document Now, Check Spelling While Typing, Check Grammar With Spelling, Correct Spelling Automatically |
| Substitutions | Submenu: Show Substitutions, Smart Copy/Paste, Smart Quotes, Smart Dashes, Smart Links, Data Detectors, Text Replacement |
| Transformations | Submenu: Make Uppercase, Make Lowercase, Capitalize |
| Speech | Submenu: Start Speaking, Stop Speaking |
| Start Dictation | Opens the dictation window; the system adds this item at the bottom of the Edit menu |
| Emoji & Symbols | Displays the Character Viewer; the system adds this item at the bottom of the Edit menu |

**Format menu** — text formatting attributes; exclude if your app doesn't support formatted text editing.
- Font submenu: Show Fonts, Bold, Italic, Underline, Bigger, Smaller, Show Colors, Copy Style, Paste Style.
- Text submenu: Align Left, Align Center, Justify, Align Right, Writing Direction, Show Ruler, Copy Ruler, Paste Ruler.

**View menu** — customize the appearance of all an app's windows. Provide it even if your app supports only a subset of functions (e.g., only Enter/Exit Full Screen). Each show/hide title must reflect the current state (Show Toolbar when hidden, Hide Toolbar when visible). Navigation and window management belong in the Window menu, not here.

| Menu item | Action |
|---|---|
| Show/Hide Tab Bar | Toggles the tab bar above the body area in a tab-based window |
| Show All Tabs/Exit Tab Overview | Enters/exits a tab overview (similar to Mission Control) |
| Show/Hide Toolbar | Toggles the toolbar's visibility in a window that includes one |
| Customize Toolbar | Opens the toolbar customization view |
| Show/Hide Sidebar | Toggles the sidebar's visibility in a window that includes one |
| Enter/Exit Full Screen | Opens the window at full-screen size in a new space |

**App-specific menus** — appear between View and Window (Safari: History, Bookmarks).
- Provide them for custom commands: people look in the menu bar for app-specific commands, especially when first using an app. Listing commands there aids discoverability, enables keyboard shortcuts, and supports Full Keyboard Access; excluding even infrequent or advanced commands makes them hard to find.
- Reflect your app's hierarchy (Mail: Mailbox → Message → Format).
- List from most to least general or commonly used.

**Window menu** — navigate, organize, and manage windows. Provide it even with a single window, including Minimize and Zoom for Full Keyboard Access. Appearance customization belongs in the View menu; closing belongs in File > Close. Consider items for showing/hiding panels (font and text color panels don't need access here — Format lists them).

| Menu item | Action / guidance |
|---|---|
| Minimize | Minimizes the active window to the Dock; Option → Minimize All |
| Zoom | Toggles between a predefined size and the user-set size; Option → Zoom All; don't use Zoom for full-screen mode (View menu) |
| Show Previous Tab / Show Next Tab | Tab navigation in a tab-based window |
| Move Tab to New Window | Opens the current tab in a new window |
| Merge All Windows | Combines all open windows into a single tabbed window |
| Enter/Exit Full Screen | Include only if your app has no View menu; keep separate Minimize and Zoom items |
| Bring All to Front | Brings all the app's windows to the front, preserving location, size, layering (same as clicking the Dock icon); Option → Arrange in Front (tiled) |
| Open window names | Brings the selected window to the front; list alphabetically; avoid listing panels or modal views |

**Help menu** — trailing end of the menu bar; Help Book format adds a search field at the top.

| Menu item | Action / guidance |
|---|---|
| Send YourAppName Feedback to Apple | Opens the Feedback Assistant |
| YourAppName Help | Opens Help Book content in the built-in Help Viewer |
| Additional items | Separate from primary documentation with a separator; keep the total small; consider linking extras (registration, release notes) from within the docs instead |

**Dynamic menu items** — a menu item that changes behavior when chosen with a modifier key (Control, Option, Shift, Command), e.g., Minimize → Minimize All with Option.
- Don't make a dynamic item the only way to accomplish a task — hidden by default; best as shortcuts for actions achievable another way.
- Use dynamic items primarily in menu bar menus — adding them to contextual or Dock menus makes them even harder to discover.
- Require only a single modifier key — multiple keys are physically awkward and reduce discoverability (`isAlternate`).
- macOS automatically sets menu width to hold the widest item, including dynamic items.

### Platform considerations
- Not supported in iOS, tvOS, visionOS, or watchOS.
- **iPadOS**: People reveal the menu bar by moving the pointer to the top edge or swiping down; when visible it occupies the same vertical space as the status bar.

| Aspect | iPadOS | macOS |
|---|---|---|
| Menu bar visibility | Hidden until revealed | Visible by default |
| Horizontal alignment | Centered | Leading side |
| Menu bar extras | Not available | System default and custom |
| Window controls | In the menu bar when the app is full screen | Never in the menu bar |
| Apple menu | Not available | Always available |
| App menu | About, Services, and app visibility items not available | Always available |

  - Because the menu bar is often hidden in full-screen apps, ensure every function is reachable through your UI — especially tasks assigned to dynamic menu items (hardware keyboard only). Avoid using the menu bar as a catch-all location.
  - Reserve YourAppName > Settings for opening the app's page in iPadOS Settings; link an internal preferences area with a separate item beneath Settings in the same group, along with other app-wide configuration options.
  - For apps with tab-style navigation, consider adding each tab as an item in the View menu (each tab is a different view); consider key bindings per tab.
  - Consider grouping items into submenus to conserve vertical space — iPad rows use more space than Mac, and some iPads have smaller screens.
- **macOS**: The Apple menu is always first on the leading side (system-defined; you can't modify or remove it); menu bar extras appear at the trailing end. When space is constrained the system prioritizes menus and essential extras, decreasing spacing between titles and truncating if necessary. Full screen typically hides the menu bar until the pointer moves to the top.
  - *Menu bar extras* expose app-specific functionality via an icon while your app runs, even when not frontmost, on the opposite side from app menus. The system hides extras to make room for app menus, and hides some if there are too many.
  - Consider a symbol for your extra (SF Symbols as-is or customized); icons use black and clear colors so the system can recolor for dark/light menus and selection. The menu bar's height is 24 pt.
  - Display a menu — not a popover — when people click your menu bar extra (unless the functionality is too complex for a menu).
  - Let people decide whether to put your extra in the menu bar (typically a setting; offering the option during setup aids discoverability).
  - Avoid relying on the presence of menu bar extras — the system hides/shows them and you can't predict their position; consider exposing the functionality in other ways too, such as a Dock menu (always available while running).

### Resources
- CommandMenu — SwiftUI; Adding menus and shortcuts to the menu bar and user interface — UIKit; NSStatusBar, MenuBarExtra — AppKit/SwiftUI; NSHelpManager — AppKit
