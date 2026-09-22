> Source: https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
> Source: https://developer.apple.com/design/human-interface-guidelines/labels
> Source: https://developer.apple.com/design/human-interface-guidelines/lockups

# Lists and tables, labels, lockups

## Lists and tables
Lists and tables present data in one or more columns of rows.

A table or list can represent data organized in groups or hierarchies and can support interactions like selecting, adding, deleting, and reordering. Apps and games on all platforms use tables to present content and options; many apps use lists to express an overall information hierarchy and help people navigate it (iOS Settings uses a hierarchy of lists; Mail in iPadOS and macOS uses a table within a split view). Productivity apps often use a multicolumn table or spreadsheet with separate, sortable columns representing data attributes.

### Best practices
- Prefer displaying text in a list or table: the row-based format is especially well suited to making text easy to scan and read, even though a table can include any type of content. If items vary widely in size or you need to display a large number of images, use a collection instead.
- Let people edit a table when it makes sense: people appreciate being able to reorder a list even if they can't add or remove items; in iOS and iPadOS, people must enter an edit mode before they can select table items.
- Provide appropriate feedback when people select a list item, varying with behavior: a table that helps people navigate through a hierarchy persistently highlights the selected row to clarify the path; a table that lists options highlights a row only briefly before adding an image — such as a checkmark — indicating the item is selected.

### Content
- Keep item text succinct so row content is comfortable to read: short text minimizes truncation and wrapping. If each item contains a large amount of text, avoid over-large rows with alternatives — e.g., list item titles only and reveal content in a detail view.
- Preserve readability of text that might get clipped or truncated — important when a table can be narrow (e.g., people can vary its width); sometimes an ellipsis in the middle of text makes an item easier to distinguish because it preserves both the beginning and the end.
- Use descriptive column headings in a multicolumn table: nouns or short noun phrases with title-style capitalization and no ending punctuation. If a single-column table view has no column heading, use a label or a header to help people understand the context.

### Style
- Choose a table or list style that coordinates with your data and platform: in iOS and iPadOS the grouped style uses headers, footers, and additional space to separate groups of data; the elliptical style in watchOS makes items appear to roll off a rounded surface while scrolling; macOS defines a bordered style using alternating row backgrounds that helps with large tables (see ListStyle).
- Choose a row style that fits the information to display — e.g., a small image at the leading end of a row followed by a brief explanatory label. Some platforms provide built-in row styles for arranging content, such as the UIListContentConfiguration API for a list's rows, headers, and footers in iOS, iPadOS, and tvOS.

### Platform considerations
- iOS, iPadOS, visionOS: Use an info button (called a detail disclosure button in a list row) only to reveal more information about a row's content — it doesn't support navigation through a hierarchical table or list; to let people drill into a row's subviews, use a disclosure indicator accessory control. Avoid adding an index to a table that displays controls — like disclosure indicators — in the trailing ends of its rows: both the index and such elements appear on the trailing side, making it difficult to use one without activating the other.
- macOS: Let people click a column heading to sort a table view when it provides value; if people click the heading of an already-sorted column, re-sort in the opposite direction. Let people resize columns to concentrate on different areas or reveal clipped data. Consider alternating row colors in a multicolumn table to help people track row values across columns, especially in wide tables. Use an outline view instead of a table view to present hierarchical data — an outline view looks like a table view but includes disclosure triangles for exposing nested levels.
- tvOS: Confirm images near a table still look good as each row highlights and slightly increases in size when focused; a focused row's corners can also become rounded, affecting the appearance of images on either side — account for this effect and don't add your own masks to round the corners.
- watchOS: Limit the number of rows when possible — short lists are easier to scan, but sometimes people expect a long list (podcast subscriptions), so make long lists manageable by listing the most relevant items and providing a way to view more. To support vertical page-based navigation (swiping vertically among the detail items of different list rows without returning to the list), constrain the length of detail views — it works only when detail views are short; if detail views scroll, people can't use it.

### Resources
- List, Tables — SwiftUI; UITableView — UIKit; NSTableView — AppKit; UIListContentConfiguration — UIKit

## Labels
A label is a static piece of text that people can read and often copy, but not edit.

Labels display text throughout the interface, helping people understand the current context and what they can do next: within a button, a label generally conveys what the button does (Edit, Cancel, Send); within many lists, a label describes each item, often accompanied by a symbol or image; within a view, a label might introduce a control or describe a common action or task. SwiftUI defines two components for displaying uneditable text: Label and Text.

### Best practices
- Use a label to display a small amount of text people don't need to edit; use a text field for editable small text, and a text view for a large amount of text that's optionally editable.
- Prefer system fonts: a label can display plain or styled text and supports Dynamic Type (where available) by default; if you adjust label style or use custom fonts, make sure the text remains legible.
- Use system-provided label colors to communicate relative importance — the system defines four label colors varying in appearance to give text different levels of visual importance:

| System color | Example usage | iOS, iPadOS, tvOS, visionOS | macOS |
|---|---|---|---|
| Label | Primary information | `label` | `labelColor` |
| Secondary label | A subheading or supplemental text | `secondaryLabel` | `secondaryLabelColor` |
| Tertiary label | Text that describes an unavailable item or behavior | `tertiaryLabel` | `tertiaryLabelColor` |
| Quaternary label | Watermark text | `quaternaryLabel` | `quaternaryLabelColor` |

- Make useful label text selectable: if a label contains useful information — like an error message, a location, or an IP address — consider letting people select and copy it for pasting elsewhere.

### Platform considerations
- iOS, iPadOS, tvOS, visionOS: no additional considerations.
- macOS: To display uneditable text in a label, use the `isEditable` property of NSTextField.
- watchOS: Use the system-provided date and time text components, which display the current date, current time, or both and can be configured with a variety of formats, calendars, and time zones; use countdown timer text components to display a precise countdown or count-up timer in various formats. When you use these system-provided components, watchOS automatically adjusts the label's presentation to fit the available space and updates the content without further input from your app. Consider using date and timer components in complications.

### Resources
- Label, Text — SwiftUI; UILabel — UIKit; NSTextField — AppKit

## Lockups
Lockups combine multiple separate views into a single, interactive unit.

Each lockup consists of a content view, a header, and a footer; headers appear above the main content and footers below it, and all three views expand and contract together as the lockup gets focus. You can combine four lockup types according to your app's needs: cards, caption buttons, monograms, and posters.

### Best practices
- Allow adequate space between lockups: a focused lockup expands in size, so leave enough room between lockups to avoid overlapping or displacing other lockups.
- Use consistent lockup sizes within a row or group: a group of buttons or a row of content images is more visually appealing when the widths and heights of all elements match.

### Lockup types
- Cards: combine a header, footer, and content view to present ratings and reviews for media items (TVCardView).
- Caption buttons: can include a title and a subtitle beneath the button, and can contain either an image or text. When people focus on them, caption buttons must tilt with the motion they swipe — tilting up and down when aligned vertically, left and right when aligned horizontally, and both vertically and horizontally when displayed in a grid (TVCaptionButtonView).
- Monograms: identify people — usually the cast and crew for a media item — with a circular picture of the person and their name; if an image isn't available, the person's initials appear in its place. Prefer images over initials: an image of a person creates a more intimate connection than text (TVMonogramContentView).
- Posters: consist of an image plus an optional title and subtitle, which are hidden until the poster comes into focus. Posters can be any size, but the size needs to be appropriate for the content (TVPosterView).

### Platform considerations
- tvOS only. Not supported in iOS, iPadOS, macOS, visionOS, or watchOS.

### Resources
- TVLockupView, TVLockupHeaderFooterView, TVCardView, TVCaptionButtonView, TVMonogramContentView, TVPosterView — TVUIKit
