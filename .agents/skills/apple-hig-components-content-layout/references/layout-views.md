> Source: https://developer.apple.com/design/human-interface-guidelines/boxes
> Source: https://developer.apple.com/design/human-interface-guidelines/disclosure-controls
> Source: https://developer.apple.com/design/human-interface-guidelines/split-views
> Source: https://developer.apple.com/design/human-interface-guidelines/tab-views

# Boxes, disclosure controls, split views, tab views

## Boxes
A box creates a visually distinct group of logically related information and components.

By default, a box uses a visible border or background color to separate its contents from the rest of the interface; a box can also include a title.

### Best practices
- Prefer keeping a box relatively small in comparison with its containing view: as a box's size gets close to the size of the containing window or screen, it becomes less effective at communicating the separation of grouped content and can crowd other content.
- Consider using padding and alignment to communicate additional grouping within a box instead of nested boxes — a box's border is a distinct visual element, and nested boxes defining subgroups can make the interface feel busy and constrained.
- Provide a succinct introductory title if it helps clarify the box's contents: the box's appearance already tells people its contents are related, but a title can add detail about the relationship and helps VoiceOver users predict the content they'll encounter within the box.
- If you use a title, write a brief phrase that describes the contents, using sentence-style capitalization; avoid ending punctuation unless the box appears in a settings pane, where you append a colon to the title.

### Platform considerations
- visionOS: no additional considerations. Not supported in tvOS or watchOS.
- iOS, iPadOS: By default, iOS and iPadOS use the secondary and tertiary background colors in boxes.
- macOS: By default, macOS displays a box's title above it.

### Resources
- GroupBox — SwiftUI; NSBox — AppKit

## Disclosure controls
Disclosure controls reveal and hide information and functionality related to specific controls or views.

### Best practices
- Use a disclosure control to hide details until they're relevant: place the controls people are most likely to use at the top of the disclosure hierarchy so they're always visible, with more advanced functionality hidden by default — this helps people quickly find essential information without being overwhelmed by detailed options.
- Provide a descriptive label when using a disclosure triangle: labels must indicate what is disclosed or hidden, like "Advanced Options."
- Place a disclosure button near the content it shows and hides, establishing a clear relationship between the control and the expanded choices that appear when people click or tap it.
- Use no more than one disclosure button in a single view: multiple disclosure buttons add complexity and can be confusing.

### Disclosure triangles
- A disclosure triangle shows and hides information and functionality associated with a view or a list of items (Keynote uses one for advanced export options; Finder uses them to progressively reveal hierarchy in list view).
- The triangle points inward from the leading edge when its content is hidden and down when its content is visible; clicking or tapping it switches between the two states, and the view expands or collapses accordingly to accommodate the content.

### Disclosure buttons
- A disclosure button shows and hides functionality associated with a specific control (the macOS Save sheet shows one next to the Save As text field; clicking it expands the dialog with advanced navigation options for selecting the document's output location).
- The button points down when its content is hidden and up when its content is visible; clicking or tapping it switches between the two states, and the view expands or collapses accordingly.

### Platform considerations
- macOS: no additional considerations. Not supported in tvOS or watchOS.
- iOS, iPadOS, visionOS: Disclosure controls are available with the SwiftUI DisclosureGroup view.

### Resources
- DisclosureGroup — SwiftUI; NSButton.BezelStyle.disclosure, NSButton.BezelStyle.pushDisclosure — AppKit

## Split views
A split view manages the presentation of multiple adjacent panes of content, each of which can contain a variety of components, including tables, collections, images, and custom views.

Typically you use a split view to show multiple levels of your app's hierarchy at once and support navigation between them: selecting an item in the primary pane displays its contents in the secondary pane, and a tertiary pane can display additional content for secondary-pane items. It's common to use a split view for a navigation sidebar — the leading pane lists top-level items or collections while secondary and optional tertiary panes present child collections and item details. Rarely, a split view can provide groups of functionality supplementing the primary view (Keynote in macOS surrounds the slide canvas with the slide navigator, presenter notes, and inspector panes).

### Best practices
- To support navigation, persistently highlight the current selection in each pane that leads to the detail view: the selected appearance clarifies the relationship between panes' content and helps people stay oriented.
- Consider letting people drag and drop content between panes: because a split view provides access to multiple levels of hierarchy, people can conveniently move content from one part of your app to another by dragging items to different panes.

### Platform considerations
- iOS: Prefer using a split view in a regular — not a compact — environment. A split view needs horizontal space to display multiple panes; in a compact environment such as iPhone in portrait orientation, displaying multiple panes without wrapping or truncating content is difficult, making content less legible and harder to interact with.
- iPadOS: A split view can include either two vertical panes (like Mail) or three (like Keynote). Account for narrow, compact, and intermediate window widths: iPad windows are fluidly resizable, so consider the split view layout at multiple widths and ensure people can always navigate between panes in a logical way.
- macOS: You can arrange panes vertically, horizontally, or both; dividers between panes can support dragging to resize. Set reasonable defaults for minimum and maximum pane sizes so the divider stays visible — if a pane gets too small, the divider can seem to disappear and become difficult to use. Consider letting people hide a pane when it makes sense (e.g., hide other panes to reduce distractions or leave more room for editing, as with Keynote's navigator and presenter notes). Provide multiple ways to reveal hidden panes — e.g., a toolbar button or a menu command, including a keyboard shortcut. Prefer the thin divider style, which measures one point in width, giving maximum space for content while remaining easy to use; avoid thicker divider styles unless you have a specific need, such as strong linear elements on both sides of a divider making a thin one hard to distinguish.
- tvOS: A split view can work well to help people filter content — choosing a filter category in the primary pane displays the results in the secondary pane. Choose a layout that keeps the panes looking balanced: by default a split view devotes a third of the screen width to the primary pane and two-thirds to the secondary pane, or you can specify a half-and-half layout. Display a single title above the split view to help people understand the content as a whole — people already know how to use a split view to navigate and filter, so they don't need titles describing each pane. Choose the title's alignment based on secondary-pane content: center it in the window when the secondary pane contains a content collection; place it above the primary view when the secondary pane contains a single main view of important content, giving the content more room.
- visionOS: To display supplementary information, prefer a split view instead of a new window: a split view gives people convenient access to more information without leaving the current context, whereas a new window may confuse people who are trying to navigate or reposition content — opening more windows also requires carefully managing relationships between views. If you need to request a small amount of information or present a simple task someone must complete before returning to their main task, use a sheet.
- watchOS: The split view displays either the list view or a detail view as a full-screen view. Automatically display the most relevant detail view when your app launches — e.g., information relevant to people's location, the time, or their recent actions. If your app displays multiple detail pages, place the detail views in a vertical tab view so people can use the Digital Crown to scroll between the tabs; watchOS also displays a page indicator next to the Digital Crown showing the number of tabs and the currently selected tab.

### Resources
- NavigationSplitView — SwiftUI; UISplitViewController — UIKit; NSSplitViewController, VSplitView, HSplitView, NSSplitView.DividerStyle — AppKit

## Tab views
A tab view presents multiple mutually exclusive panes of content in the same area, which people can switch between using a tabbed control.

### Best practices
- Use a tab view to present closely related areas of content: its strong visual indication of enclosure leads people to expect each tab's content to be in some way similar or related to the other tabs' content.
- Make sure the controls within a pane affect content only in the same pane: panes are mutually exclusive, so ensure they're fully self-contained.
- Provide a label for each tab that describes the contents of its pane, helping people predict the contents before clicking or tapping the tab: generally use nouns or short noun phrases (a verb or short verb phrase may make sense in some contexts), with title-style capitalization.
- Avoid using a pop-up button to switch between tabs: a tabbed control requires a single click or tap to make a selection and presents all choices onscreen at once, whereas a pop-up button requires two clicks and hides its choices until opened. A pop-up button can be a reasonable alternative only when there are too many panes of content to reasonably display with tabs.
- Avoid providing more than six tabs in a tab view: more than six tabs can be overwhelming and create layout issues. If you need to present six or more, implement the interface another way — e.g., present each tab as a view option in a pop-up button menu.

### Anatomy
- The tabbed control appears on the top edge of the content area; you can choose to hide it, which is appropriate for an app that switches between panes programmatically.
- When the tabbed control is hidden, the content area can be borderless (solid or transparent), bezeled, or bordered with a line.
- In general, inset a tab view by leaving a margin of window-body area on all sides: this layout looks clean and leaves room for additional controls that aren't directly related to the tab view's contents. Extending a tab view to meet the window edges is unusual.

### Platform considerations
- Not supported in iOS, iPadOS, tvOS, or visionOS (a macOS component).
- iOS, iPadOS: For similar functionality, consider using a segmented control instead.
- watchOS: watchOS displays tab views using page controls.

### Resources
- TabView — SwiftUI; NSTabView — AppKit
