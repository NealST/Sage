> Source: https://developer.apple.com/design/human-interface-guidelines/collections
> Source: https://developer.apple.com/design/human-interface-guidelines/column-views
> Source: https://developer.apple.com/design/human-interface-guidelines/outline-views

# Collections, column views, outline views

## Collections
A collection manages an ordered set of content and presents it in a customizable and highly visual layout.

Collections are generally ideal for showing image-based content.

### Best practices
- Use the standard row or grid layout whenever possible: the default horizontal row or grid are simple, effective appearances people expect — avoid creating a custom layout that might confuse people or draw undue attention to itself.
- Consider using a table instead of a collection for text: textual information is generally simpler and more efficient to view and digest in a scrollable list.
- Make it easy to choose an item: if it's too hard to reach an item, people get frustrated and lose interest before reaching the content they want — use adequate padding around images to keep focus or hover effects easy to see and prevent content from overlapping.
- Add custom interactions when necessary: by default people can tap to select, touch and hold to edit, and swipe to scroll; you can add more gestures for performing custom actions if your app requires it.
- Consider using animations to provide feedback when people insert, delete, or reorder items: collections support standard animations for these actions, and you can also use custom animations.

### Platform considerations
- macOS, tvOS, visionOS: no additional considerations. Not supported in watchOS.
- iOS, iPadOS: Use caution when making dynamic layout changes — be sure any changes make sense and are easy to track; when possible, avoid changing the layout while people are viewing and interacting with it, unless the change is in response to an explicit action.

### Resources
- UICollectionView — UIKit; NSCollectionView — AppKit

## Column views
A column view — also called a browser — lets people view and navigate a data hierarchy using a series of vertical columns.

Each column represents one level of the hierarchy and contains horizontal rows of data items; a parent item containing nested children is marked with a triangle icon, and selecting a parent displays its children in the next column. People continue navigating until reaching an item with no children, and can navigate back up the hierarchy to explore other branches. For managing hierarchical content in an iPadOS or visionOS app, consider using a split view instead.

### Best practices
- Consider a column view when you have a deep data hierarchy in which people navigate back and forth frequently between levels, and you don't need the sorting capabilities a list or table provides (Finder offers a column view, among others, for navigating directory structures).
- Show the root level of the data hierarchy in the first column: people know they can quickly scroll back to the first column to begin navigating from the top again.
- Consider showing information about the selected item when there are no nested items to display (Finder shows a preview plus creation date, modification date, file type, and size).
- Let people resize columns — especially important when data item names are too long to fit the default column width.

### Platform considerations
- macOS only. Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.

### Resources
- NSBrowser — AppKit

## Outline views
An outline view presents hierarchical data in a scrolling list of cells that are organized into columns and rows.

An outline view includes at least one column containing primary hierarchical data (parent containers and their children); you can add columns displaying supplementary attributes, such as sizes and modification dates. Parent containers have disclosure triangles that expand to reveal their children (Finder windows offer an outline view for navigating the file system).

### Best practices
- Use outline views to display text-based content; they often appear in the leading side of a split view, with related content on the opposite side.
- Use a table instead of an outline view to present data that's not hierarchical.
- Expose the data hierarchy in the first column only; other columns can display attributes that apply to the hierarchical data in the primary column.
- Use descriptive column headings to provide context: nouns or short noun phrases with title-style capitalization and no punctuation — in particular, no trailing colon. Always provide column headings in a multi-column outline view; in a single-column view without a heading, use a label or other means to ensure enough context.
- Consider letting people click column headings to sort: clicking performs an ascending or descending sort based on that column, and you can implement additional sorting on secondary columns behind the scenes. Clicking the primary column heading sorts at each hierarchy level (in Finder, all top-level folders are sorted, then items within each folder); clicking the heading of an already-sorted column re-sorts the folders and their contents in the opposite direction.
- Let people resize columns: data often varies in width, and resizing lets people reveal data that's wider than the column.
- Make it easy to expand or collapse nested containers: clicking a disclosure triangle expands only that container (a Finder folder), while Option-clicking it expands all of its subfolders.
- Retain people's expansion choices: if people expanded various levels to reach a specific item, store the state and display it again next time so they don't need to navigate back to the same place.
- Consider using alternating row colors in multi-column outline views — they help people track row values across columns, especially in wide outline views.
- Let people edit data if it makes sense in your app: in an editable cell, people expect to single-click to edit its contents, and a cell can respond differently to a double click (single-click a file's name to edit it; double-click it to open the file). You can also let people reorder, add, and remove rows if useful.
- Consider using a centered ellipsis to truncate cell text instead of clipping it: a middle ellipsis preserves the beginning and end of the text, making the content more distinct and recognizable.
- Consider offering a search field to help people find values quickly in a lengthy outline view — windows with an outline view as the primary feature often include one in the toolbar.

### Platform considerations
- macOS only. Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.

### Resources
- OutlineGroup — SwiftUI; NSOutlineView — AppKit
