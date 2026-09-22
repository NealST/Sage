> Source: https://developer.apple.com/design/human-interface-guidelines/path-controls
> Source: https://developer.apple.com/design/human-interface-guidelines/search-fields
> Source: https://developer.apple.com/design/human-interface-guidelines/sidebars
> Source: https://developer.apple.com/design/human-interface-guidelines/tab-bars
> Source: https://developer.apple.com/design/human-interface-guidelines/token-fields

# Path controls, search fields, sidebars, tab bars, token fields

## Path controls
A path control shows the file system path of a selected file or folder.

Example: choosing View > Show Path Bar in the Finder displays a path bar at the bottom of the window showing the selected item's path, or the window folder's path if nothing is selected.

Two styles:
- **Standard** — a linear list containing the root disk, parent folders, and the selected item, each with an icon and name. If the list is too long, names between the first and last items are hidden. In an editable control, people can drag an item onto it to select the item and display its path.
- **Pop up** — similar to a pop-up button, showing the icon and name of the selected item; clicking opens a menu containing the root disk, parent folders, and selected item. An editable control adds a Choose command for selecting an item, and also accepts drag-and-drop.

### Best practices
- Use a path control in the window body, not the window frame — it isn't intended for toolbars or status bars (the Finder's path control sits at the bottom of the window body, not the status bar).

### Platform considerations
- macOS only. Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.

### Resources
- NSPathControl — AppKit

## Search fields
A search field lets people search a collection of content for specific terms they enter.

A search field is an editable text field displaying a Search icon, a Clear button, and placeholder text. It can use a scope bar and tokens to filter and refine the search's scope; access patterns differ per platform.

### Best practices
- Use placeholder text to help people know what they can search for — reinforcing scope or the type of searchable content.
- Start search immediately when a person types, if possible — continuously refined results feel more responsive.
- Consider showing suggested search terms: recent searches before search begins, or predictive suggestions as someone types.
- Simplify search results: show the most relevant first to minimize scrolling, and consider categorizing results.
- Consider letting people filter results, e.g., a scope bar in the search results content area.

### Scope bars and tokens
- A **scope bar** filters and adjusts the scope of a search; use it to move among clearly defined search categories (Mail: entire mailbox → current mailbox). Default to a broader scope and let people refine it — broader scope provides context for the full result set.
- A **token** is a visual representation of a search term that people can select and edit, acting as a filter for additional terms. Use tokens to filter by common search terms or items (a specific contact in Mail; photo attributes in Messages). Consider pairing tokens with search suggestions so people learn which tokens are available. (macOS component: Token fields.)

### Platform considerations
- No additional considerations for visionOS.
- **iOS** — three main entry-point positions: as a tab in a tab bar, in a toolbar at the bottom or top, or directly inline with content. The best choice depends on layout, content, and navigation.
  - *Search as a tab* — two styles: a **standard tab** (uniform with the tab bar; tapping navigates to a search landing page with the field at the top) suits providing suggestions, promoting discovery, and encouraging exploration (Apple TV's genres and categories); a **button appearance** (separate button; tapping focuses the field and shows the keyboard) helps people quickly find what they need — a transient experience that returns to the previous tab on exit.
  - *Search in a toolbar* — in a bottom toolbar as an expanded field or a toolbar button that animates into a field above the keyboard; in a top toolbar (navigation bar) as a button that animates into a field above the keyboard or at the top when there's no space at the bottom. Place at the bottom if there's room — bottom search stays easy to reach whenever search is a priority (Settings: only item; Mail and Notes: alongside other controls). Place at the top when bottom content takes precedence (Wallet's stack of event passes) or there's no bottom toolbar.
  - *Search as an inline field* — place when its position alongside the searched content strengthens the relationship: filtering or searching within a single view, with multiple search fields, or where location defines scope (Music library filter). At the top, position the field above the list it searches and consider pinning it to the top toolbar when scrolling.
- **iPadOS, macOS** — placement and behavior are similar; keep the search experience consistent across both platforms.
  - Put a search field at the trailing side of the toolbar for many common uses — especially apps with split views searching across multiple columns (Mail, Notes, Voice Memos); it lets people navigate results while keeping their selection visible. Also consider toolbar search when results appear in the detail view (Freeform).
  - Include search at the top of the sidebar when filtering content or navigation there (Settings filters the sidebar and surfaces deep sections; useful when the sidebar needs clear separation from an adjacent rich detail view).
  - Include search as an item in the sidebar or tab bar when you want a dedicated discovery area — for search paired with rich suggestions, categories, or content needing space (Music, TV); it stays available while people navigate sections.
  - In a dedicated search area, consider immediately focusing the field on navigation — except on iPad with only a virtual keyboard, where an unfocused field prevents the keyboard from unexpectedly covering the view.
  - Account for window resizing: the field fluidly resizes with the window; in compact iPad views ensure search sits where it's most contextually useful (Notes and Mail place search above the content-list column).
- **tvOS**: A search screen is a specialized keyboard screen showing results beneath the keyboard in a fully customizable view (`UISearchController`). Provide suggestions — popular, context-specific, and recent searches — people typically don't want to type much.
- **watchOS**: Tapping the search field displays a text-input control covering the entire screen; the app returns to the search field only after Cancel or Search.

### Resources
- Adding a search interface to your app, searchable(text:placement:prompt:) — SwiftUI; UISearchBar, UISearchTextField — UIKit; NSSearchField — AppKit

## Sidebars
A sidebar appears on the leading side of a view and lets people navigate between areas of your app or top-level collections of content, like folders and playlists.

A sidebar requires a large amount of vertical and horizontal space; when space is limited or you want more room for content, a more compact control like a tab bar may work better. Many apps don't need to choose — a tab bar style can provide both.

### Best practices
- Extend visually rich content beneath the sidebar (sidebars can float above content in the Liquid Glass layer): let content scroll horizontally beneath it or apply a background extension effect, which mirrors adjacent content to suggest it stretches under the sidebar (`backgroundExtensionEffect()`).
- When possible, let people customize the sidebar's contents — which areas appear and in what order.
- Group hierarchy with disclosure controls if your app has a lot of content, keeping vertical space manageable.
- Consider familiar symbols (SF Symbols) for sidebar items; for a custom icon, create a custom symbol rather than using a bitmap image.
- Consider letting people hide the sidebar, using the interactions people already know (iPadOS edge swipe; macOS show/hide button or View menu commands). In visionOS a window typically expands to accommodate a sidebar, so hiding is rarely needed. Don't hide it by default — it must remain discoverable.
- Show no more than two levels of hierarchy in a sidebar; for deeper hierarchies use a split view with a content list between sidebar and detail view.
- For two levels, use succinct, descriptive labels to title each group; omit unnecessary words.
- Make sidebar icon colors serve a clear purpose: by default they use your app's accent color, and in macOS they must follow the system accent color people choose. Use fixed colors sparingly to clarify meaning or draw attention (Mail's VIP icon is yellow).

### Platform considerations
- No additional considerations for tvOS. Not supported in watchOS.
- **iOS, iPadOS**: With the `sidebarAdaptable` tab view style, you choose whether a sidebar or a tab bar appears when your app opens; both variations include a switch button, adapt per platform, and respond to rotation and window resizing. To display a sidebar only, use `NavigationSplitView` (or `UISplitViewController`). Consider a tab bar first — it provides more space for content — and use the tab bar's convertible sidebar-style appearance for less frequently used content. Non-SwiftUI sidebars: `UICollectionLayoutListConfiguration.Appearance.sidebar`.
- **macOS**: Row height, text, and glyph size depend on the sidebar's overall size — small, medium, or large — set programmatically or changed by people via sidebar icon size in General settings. Consider automatically hiding and revealing the sidebar as its container window resizes (small Mail viewer window collapses its sidebar). Avoid putting critical information or actions at the bottom of a sidebar — people often relocate windows in a way that hides the bottom edge.
- **visionOS**: For a deep hierarchy, consider a sidebar within a tab in a tab bar for secondary navigation; prevent sidebar selections from changing the currently open tab.

### Resources
- sidebarAdaptable, NavigationSplitView, sidebar, backgroundExtensionEffect — SwiftUI; UICollectionLayoutListConfiguration — UIKit; NSSplitViewController — AppKit

## Tab bars
A tab bar lets people navigate between top-level sections of your app.

Tab bars help people understand the types of information or functionality an app provides, and let them switch sections quickly while preserving each section's navigation state.

### Best practices
- Use a tab bar to support navigation, not to provide actions — for controls acting on the current view, use a toolbar.
- Keep the tab bar visible when people navigate between sections — hiding it makes people forget where they are. Exception: a modal view may cover it.
- Use the appropriate number of tabs, weighing complexity against frequent access; it's generally easier to navigate among fewer tabs. For complex information structures, consider a sidebar or a tab bar that adapts to a sidebar.
- Avoid overflow tabs: with limited horizontal space the trailing tab becomes a More tab in iOS and iPadOS, and hidden tabs are harder to reach and notice — limit scenarios where this happens.
- Don't disable or hide tab bar buttons even when their content is unavailable — an inconsistently available tab bar makes the interface feel unstable; if a section is empty, explain why.
- Include tab labels (beneath or beside the icon) to aid navigation; use single words whenever possible.
- Consider SF Symbols for familiar, scalable tab bar icons — they adapt to regular and compact contexts (icons above labels in compact views, side by side in regular views). Prefer filled symbols or icons for platform consistency. For custom icons, see Apple Design Resources for tab bar icon dimensions.
- Use a badge (a red oval containing white text with a number or exclamation point) to indicate critical new or updated information; reserve badges for critical information so they don't lose impact.
- Avoid applying a similar color to tab labels and content layer backgrounds; over bright content prefer a monochromatic tab bar or an accent color with sufficient differentiation.

### Platform considerations
- No additional considerations for macOS. Not supported in watchOS.
- **iOS**: The tab bar floats above content at the bottom of the screen; items rest on a Liquid Glass background that lets content peek through. With an attached accessory (like Music's MiniPlayer), you can minimize the tab bar and move the accessory inline when people scroll down; they exit by tapping a tab or scrolling to the top (`TabBarMinimizeBehavior`, `UITabBarController.MinimizeBehavior`). A tab bar can include a dedicated search tab at the trailing end.
- **iPadOS**: The system displays the tab bar near the top of the screen, either fixed or with a button that converts it to a sidebar (`tabBarOnly`, `sidebarAdaptable`). To present a sidebar without conversion, use a navigation split view. Prefer a tab bar for navigation to the most-used sections; offer conversion to a sidebar for wider navigation. Let people customize the tab bar (add frequently used items like a favorite playlist, remove less-used ones) — if people select their own tabs, aim for a default list of five or fewer to preserve continuity between compact and regular sizes (`TabViewCustomization`, `UITab.Placement`).
- **tvOS**: Highly customizable — background tint, color, or image; font for tab items (including a different font for the selected item); tints for selected and unselected items; button icons like settings and search. By default the bar is translucent with only the selected tab opaque; a focused selected tab gets a drop shadow.

  | Metric | Value |
  |---|---|
  | Tab bar height | 68 pt (can't change) |
  | Top edge distance from top of screen | 46 pt (can't change) |

  - Overflow behavior: the rightmost item is truncated with a fade beginning at the right side; with enough items to cause scrolling, a truncating fade also starts from the left.
  - Scrolling: by default people can scroll the tab bar offscreen when the current tab has a single main view (TV app's Watch Now, Movies, TV Show, Sports, Kids); with a split view (Library, Settings screens) the bar stays pinned while panes scroll. Pressing Menu on the remote always returns focus to the tab bar.
  - Live-viewing apps: organize tabs in this order — live content; cloud DVR or other recorded content; other content.
- **visionOS**: The tab bar is always vertical, floating in a position fixed relative to the window's leading side. It expands when people look at it; to open a tab, people look at it and tap. While expanded it can temporarily obscure content behind it.
  - Supply a symbol and a text label for each tab: the symbol is always visible, labels are revealed when people look at the bar; keep labels short so they're readable at a glance.
  - If your app's hierarchy is deep, consider a sidebar within a tab for secondary navigation; prevent sidebar selections from changing the open tab.

### Resources
- TabView, TabViewBottomAccessoryPlacement, Enhancing your app's content with tab navigation — SwiftUI; UITabBar, Elevating your iPad app with a tab bar and sidebar — UIKit

## Token fields
A token field is a type of text field that can convert text into tokens that are easy to select and manipulate.

Example: Mail's compose-window address fields convert each recipient's name into a token; people can select tokens and drag to reorder them or move them to a different field. A token field can present a suggestions list as people type (Mail suggests recipients; selecting one inserts it as a token), and an individual token can include a contextual menu with information or editing options (edit recipient name, mark as VIP, view contact card). Tokens can also represent search terms (see Search fields).

### Best practices
- Add value with a context menu — people often benefit from additional options or information about a token.
- Consider providing additional ways to convert text into tokens; by default typing a comma converts the text — you can add shortcuts such as pressing Return.
- Consider customizing the delay before showing suggested tokens: suggestions appear immediately by default, but too-quick suggestions can distract while typing — adjust to a comfortable level.

### Platform considerations
- macOS only. Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.

### Resources
- NSTokenField — AppKit
