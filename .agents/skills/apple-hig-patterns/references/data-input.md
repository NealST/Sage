> Source: https://developer.apple.com/design/human-interface-guidelines/entering-data
> Source: https://developer.apple.com/design/human-interface-guidelines/drag-and-drop
> Source: https://developer.apple.com/design/human-interface-guidelines/undo-and-redo
> Source: https://developer.apple.com/design/human-interface-guidelines/file-management
> Source: https://developer.apple.com/design/human-interface-guidelines/printing

## Entering data

When you need information from people, design ways that make it easy for them to provide it without making mistakes.

### Best practices

- Pre-gather as much information as possible to minimize what people must supply; support all available input methods so people can choose what works for them.
- Get information from the system whenever possible — don't ask people to enter data you can gather automatically or with permission (location, calendar).
- Be clear about the data you need: prompts in text fields ("username@company.com"), introductory labels ("Email"), or prefilled reasonable defaults.
- Use a secure text-entry field for sensitive data (input obscured with a filled circle per character; see SecureField). tvOS can set isSecureDigitEntry on a digit entry view; in visionOS the system shows entered data only to the wearer (e.g., a secure field blurs during AirPlay).
- Never prepopulate a password field — ask people to enter their password or use biometric or keychain authentication.
- Offer choices instead of requiring text entry: pickers, menus, and selection components are easier and more efficient than typing.
- Let people provide data by dragging and dropping or pasting when possible.
- Dynamically validate field values and give feedback as soon as a problem is detected; use a number formatter for numeric data (accept only numeric values, display with specific decimal places, as percentage, or currency).
- When data entry is necessary, make clear that required data must be provided before proceeding — e.g., enable Next/Continue only after required fields are filled.

### Platform considerations

- macOS: Consider an expansion tooltip to show the full version of clipped or truncated text in a field (works for iOS/iPadOS apps running on a Mac too).

### Resources

- SecureField (SwiftUI), isSecureDigitEntry (tvOS)
- Input events — SwiftUI

## Drag and drop

Using drag and drop, people can move or duplicate selected photos, text, and other content by dragging the selection from one location to another.

### Best practices

- General rules: dropping within the same container moves the content; dropping in a different container copies it; dragging between apps always results in a copy.
- Platform input variations: visionOS uses pinch-and-hold while dragging in any direction (including z-axis); iOS/iPadOS use touchscreen gestures, pointing devices, and full keyboard access; Universal Control lets people drag between Mac and iPad; on Mac, people can use a pointing device, full keyboard access, or VoiceOver.
- Support drag and drop throughout your app — people try it everywhere; system-provided text fields and text views have built-in support.
- Offer alternative ways to accomplish the same actions (e.g., menu commands for copy/move); use accessibility APIs (accessibilityDragSourceDescriptors, accessibilityDropPointDescriptors) so assistive technologies can drag and drop.
- Determine when dragging within your app moves vs copies; prefer the behavior most people expect and that's least likely to cause frustration or data loss.
- Support multi-item drag and drop when it makes sense (iOS, iPadOS, macOS, visionOS; macOS can drag items from several apps; iPadOS can add items mid-drag).
- Prefer letting people undo a drag-and-drop operation; ask for confirmation before operations that can't be undone (e.g., Finder confirming a drop into a write-only folder); provide a way to reverse results when undo isn't possible.
- Offer multiple versions of dragged content ordered from highest to lowest fidelity (e.g., PDF vector, lossless PNG with transparency, lossy JPEG) so the destination picks the best it can accept.
- Consider supporting spring loading: activate controls by dragging content over them (force-click on Magic Trackpad, hover on iPad).
- Providing feedback:
  - Display a translucent drag image as soon as people drag about three points; keep it until the drop.
  - Modify the drag image to help predict the result (e.g., a photo expanding to its default size); use drag flocking to group multiple items; avoid constant, radical changes.
  - Show whether a destination can accept content: insertion point or highlight only when it can; no feedback or an explicit "not allowed" image (circle.slash) when it can't; cue one destination at a time.
  - On an invalid or failed drop, give visual feedback — the item returns to its source or scales up and fades out.
- Accepting drops:
  - Auto-scroll a scrolling destination while the item is over it (system text views do this by default).
  - Pick the richest version your app can accept (native chart object over an image of it).
  - Extract only the relevant portion of dropped content (e.g., Mail uses only name and email address from a contact).
  - With a physical keyboard, check the Option key at drop time: holding Option forces a copy within the same container.
  - Provide feedback for time-consuming transfers: progress indicator, placeholder at the drop location; the system can display an alert for long cross-app transfers.
  - Provide feedback when dropped content initiates a task (e.g., printing): show it began and keep progress visible.
  - Apply appropriate styling to dropped text: keep original styles when source and destination support the same ones; otherwise apply the destination's style.
  - Maintain selection state after a drop so people can act immediately; for a copy within the same container, remove selection from the original; for cross-container drags, deselect in the source.

### Platform considerations

- Not supported in tvOS or watchOS.
- iOS, iPadOS: Let people perform multiple simultaneous drag activities — add items during a drag (with flocking feedback) and accept multiple simultaneous drops.
- macOS:
  - Consider letting people drag content into the Finder in a format your app can open later (e.g., Calendar exports .ics); use a clipping (temporary dragged-content container) when necessary — unrelated to the Clipboard.
  - Let people drag a background selection from an inactive window without activating it; let them drag an unselected item without affecting an existing background selection.
  - Consider a badge (small filled oval with a count) during multi-item drags; update it if the destination accepts only a subset.
  - Consider changing the pointer appearance (copy, drag link, disappearing item, operation not allowed).
  - Let people select and drag content in a single motion unless selecting multiple items.
- visionOS: When possible, launch your app to handle content dropped into empty space by associating a user activity with draggable content (NSUserActivity) — dropping a URL opens Safari; Quick Look-supported content opens Quick Look.

### Resources

- Drag and drop — UIKit; Drag and Drop — AppKit; File Provider; NSUserActivity

## Undo and redo

Undo and redo gives people easy ways to reverse many types of actions, which can also help people explore and experiment safely as they learn a new interface or task.

### Best practices

- Help people predict the results of undo and redo: describe the result in the iPhone shake-to-undo alert; use specific menu item labels like "Undo Typing" or "Redo Bold".
- Show the results of an undo or redo — scroll to affected content if it's offscreen so people don't repeat the action thinking it failed.
- Let people undo multiple times; avoid unnecessary limits — people expect to undo everything since a logical step like opening a document or saving.
- Consider letting people revert multiple changes at once (a batch of related adjustments, or all changes since opening/saving).
- Provide undo and redo buttons only when necessary; use standard system symbols and place buttons in a toolbar.

### Platform considerations

- Not supported in tvOS or watchOS.
- iOS, iPadOS: Avoid redefining standard gestures (three-finger swipe, shake). The undo/redo alert title automatically includes an "Undo " or "Redo " prefix (with trailing space); provide an additional word or two, e.g., "Undo Name" or "Redo Address Change".
- macOS: Place undo and redo at the top of the Edit menu and support Command-Z and Shift-Command-Z.

### Resources

- UndoManager — Foundation

## File management

Some apps can support documents and files that people expect to manage throughout the system.

### Best practices

- Creating and opening files:
  - Provide familiar menu commands like New and Open; iPadOS shows them in the shortcuts interface (hold Command on a connected keyboard), macOS shows them in the File menu.
  - Regardless of keyboard shortcuts, include an Add (+) button for creating documents (in the File menu on macOS).
  - If you require a custom file browser, support people's understanding of the platform file system (Finder, Files): show the most relevant location by default but let people browse the rest of the file system.
- Saving work:
  - Avoid making people save explicitly — automatically save periodically while editing, when closing a file, and when switching to another app.
  - Hide file extensions by default, but let people view them; reflect the current choice in all save/open interfaces.
- Quick Look:
  - Use a Quick Look viewer to let people preview files your app can't open (audio previews, photo markup, rotating/scaling 3D previews).
  - Consider a Quick Look generator if your app produces custom file types, so the Finder, Files, and Spotlight can display previews.

### Platform considerations

- No additional considerations for tvOS, visionOS, or watchOS (no document-browsing interfaces).
- iOS, iPadOS:
  - Document launcher (iOS 18/iPadOS 18): a full-screen, graphical way to browse, open, and create files, consisting of a title card (app title + two app-specific buttons), a background image plus accessory images, and a sheet with a file browser and optional controls. Guidance:
    - Assign the title card's buttons to your app's most important functions (primary usually creates a new document; e.g., Numbers: "Start Writing" / "Choose a Template").
    - Provide a background clearly distinct from accessories and title card (solid color, gradient, or pattern; no complex distracting images).
    - Be mindful of accessory placement — keep the app name and both buttons clearly visible; avoid clutter; test across screen sizes and orientations.
    - Use animation sparingly — gentle, repeating animations (e.g., breathing or swaying) only.
  - File provider app extension: display only documents appropriate in the current context (e.g., only PDFs for a PDF editor); optionally show modification dates, sizes, local/remote status; let people select a destination when exporting/moving (and create new subdirectories); avoid a custom top toolbar (the modal view already includes one).
- macOS:
  - Use the default file browser unless you have an important reason to create a custom one; make custom open interfaces convenient ("open recent", filter criteria, multi-select open); you can customize the open panel's button title (e.g., "Insert").
  - Provide a save interface for changing a file's name, format, and location; default new-document title is "Untitled"; let people choose the file format if you support several.
  - Consider extending the Save dialog with a custom accessory view of useful options (e.g., Mail's include-attachments option).
  - Finder Sync extensions (for apps syncing local and remote files): display sync-status badges, provide custom contextual menu items (favoriting, password protection), provide custom toolbar buttons for global actions like initiating a sync.
  - When autosaving is off (people can enable "Ask to keep changes when closing documents"): show unsaved-change indicators (dot on the window's close button and next to the document name in the Window menu) and present a save dialog on close/quit/logout/restart. When autosaving is on, don't show dots (it implies action is needed). You may append "Edited" to the title bar document title in both cases, removing it as soon as autosave or explicit save occurs.

### Resources

- DocumentGroupLaunchScene, Documents — SwiftUI
- File Provider; Finder Sync; Adding a document browser to your app

## Printing

An iOS, iPadOS, macOS, or visionOS app can integrate system-provided print functionality when it makes sense, presenting custom printer- and document-specific options if necessary.

### Best practices

- Make printing discoverable by placing the print action in standard system locations: a Print item in the macOS File menu; a toolbar button that opens an action sheet in iOS/iPadOS; an optional customizable-toolbar Print button on macOS.
- Present the printing option only when possible: dim the File menu item (macOS) or remove the action-sheet Print action (iOS/iPadOS) when there's nothing to print or no printers are available; dim or hide custom print buttons.
- Present relevant printing options — page range, multiple copies, two-sided — using the system-provided view when the printer supports them.

### Platform considerations

- Not supported in tvOS or watchOS.
- macOS:
  - Consider a custom category in the print panel for app-specific options (give it a unique name such as your app name; e.g., Keynote offers presenter notes, slide backgrounds, skipped slides).
  - Consider a page setup dialog for document-specific page size, orientation, and scaling; don't reimplement options the system already provides (orientation, reverse-order printing).
  - Make interdependencies between options clear (e.g., transparency printing unavailable when double-sided is on).
  - Separate advanced features from frequently used ones — hide advanced options behind a disclosure control labeled "Advanced Options".
  - Consider letting people preview the effect of a setting (e.g., a thumbnail updating with a tone control).
  - Consider storing modified settings with the document — at minimum until it's closed.

### Resources

- UIPrintInteractionController — UIKit; NSDocument — AppKit
