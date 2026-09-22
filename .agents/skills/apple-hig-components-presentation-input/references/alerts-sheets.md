> Source: https://developer.apple.com/design/human-interface-guidelines/alerts
> Source: https://developer.apple.com/design/human-interface-guidelines/action-sheets
> Source: https://developer.apple.com/design/human-interface-guidelines/sheets

# Alerts, action sheets, sheets

## Alerts
An alert gives people critical information they need right away.

For example, an alert can tell people about a problem, warn them when their action might destroy data, or let them confirm a purchase or another important action they initiated.

### Best practices
- Use alerts sparingly. They interrupt the current task; make each one offer only essential information and useful actions.
- Avoid using an alert merely to provide information — people dislike interruptions that aren't actionable. Prefer an in-context alternative (for example, Mail shows an indicator people can choose to learn more when a server connection is unavailable).
- Avoid alerts for common, undoable actions — even destructive ones (deleting an email or file), because people intend to discard the data and can undo. Do display an alert for an uncommon destructive action people can't undo, in case it was initiated accidentally.
- Avoid showing an alert when your app starts. Make new or important information easily discoverable; for startup problems (like no network connection), show cached or placeholder data with a nonintrusive label describing the problem.

**Content anatomy**
- All platforms: a title, optional informative text, and up to three buttons.
- iOS, iPadOS, macOS, and visionOS: can also include a text field.
- macOS and visionOS: can include an icon and an accessory view; macOS can also add a suppression checkbox and a Help button.
- Write alert copy in a direct, neutral, approachable tone; don't be oblique or accusatory, and don't mask the severity of the issue.
- Write a title that clearly and succinctly describes the situation — what happened, the context, and why. Avoid useless titles ("Error", "Error 329347 occurred") and titles that wrap to more than two lines. Complete sentence → sentence-style capitalization with ending punctuation; sentence fragment → title-style capitalization, no ending punctuation.
- Include informative text only if it adds value; keep it short, in complete sentences with sentence-style capitalization and appropriate punctuation.
- Avoid explaining alert buttons. If guidance is truly needed, use a device-agnostic term like "choose" and refer to the button by its exact title, without quotes.
- Include a text field only when people's input is needed to resolve the situation (for example, a secure text field for a password).

**Buttons**
- Create succinct, logical button titles: one or two words describing the result, preferring verbs and verb phrases related to the alert text ("View All", "Reply", "Ignore"). Use "OK" for acceptance in informational alerts only; never "Yes"/"No". Always title the canceling button "Cancel". Use title-style capitalization and no ending punctuation.
- Avoid "OK" as the default button title unless the alert is purely informational — its meaning is unclear in confirmations; a specific title like "Erase", "Convert", "Clear", or "Delete" clarifies the action.
- Place buttons where people expect: the most likely choice — and always the default button — on the trailing side of a row or the top of a stack; Cancel typically on the leading side or at the bottom of a stack.
- Use the destructive style only for a destructive action people didn't deliberately choose. When people deliberately choose a destructive action (like Empty Trash), don't apply the destructive style to its button — the convenience of pressing Return to confirm their original intent outweighs reaffirming destructiveness.
- If there's a destructive action, include a "Cancel" button as a clear, safe way out — but never make Cancel the default. To encourage people to read an alert, avoid making any button the default. A single-button alert whose button must also be the default should use "Done", not "Cancel".
- Provide alternative ways to cancel when it makes sense:

| Action | Platform |
|---|---|
| Exit to the Home Screen | iOS, iPadOS |
| Pressing Escape (Esc) or Command-Period (.) on an attached keyboard | iOS, iPadOS, macOS, visionOS |
| Pressing Menu on the remote | tvOS |

### Platform considerations
- **tvOS, watchOS**: No additional considerations.
- **iOS, iPadOS**:
  - Use an action sheet — not an alert — to offer choices related to an intentional action; an alert can confirm or cancel but doesn't provide additional choices.
  - When possible, avoid displaying an alert that scrolls; minimize the potential by keeping titles short and messages brief.
- **macOS**:
  - The system displays your app icon in an alert automatically; you can supply an alternative icon or symbol.
  - Configure repeating alerts so people can suppress subsequent occurrences; append a custom accessory view when necessary; include a Help button that opens your help documentation.
  - Use a caution symbol (like `exclamationmark.triangle`) sparingly — frequent use diminishes its significance. Use it only when extra attention is really needed, such as confirming an action that might cause unexpected data loss; not for tasks whose only purpose is overwriting or removing data (save, empty trash).
- **visionOS**:
  - In the Shared Space, an alert appears in front of the app's window, slightly forward along the z-axis, and stays anchored to the window if the window moves. In a Full Space, the alert is centered in the wearer's field of view.
  - An accessory view in a visionOS alert: maximum height 154 pt, 16-pt corner radius.

### Resources
- alert(_:isPresented:actions:) — SwiftUI; UIAlertController — UIKit; NSAlert — AppKit

## Action sheets
An action sheet is a modal view that presents choices related to an action people initiate.

Developer note: in SwiftUI, offer action sheet functionality on all platforms with a presentation modifier for a confirmation dialog; in UIKit, use `UIAlertController.Style.actionSheet` in iOS, iPadOS, and tvOS.

### Best practices
- Use an action sheet — not an alert — to offer choices related to an intentional action (canceling an edited Mail message offers deleting the draft or saving it). An alert can confirm or cancel a destructive action but doesn't provide additional choices, and it's usually unexpected.
- Use action sheets sparingly; they interrupt the current task.
- Keep titles short enough to display on a single line — long titles are hard to read quickly and may truncate or require scrolling.
- Provide a message only if necessary; the title plus the current action's context usually provides enough information.
- If necessary, provide a Cancel button that lets people reject a data-destroying action. Place it at the bottom of the sheet (upper-left corner in watchOS); a SwiftUI confirmation dialog includes Cancel by default.
- Make destructive choices visually prominent: use the destructive style and place these buttons at the top of the sheet where they're most noticeable.

### Platform considerations
- No additional considerations for macOS or tvOS. **Not supported in visionOS.**
- **iOS, iPadOS**:
  - Use an action sheet — not a menu — to provide choices related to an action: people expect an action sheet to appear after performing an action that might require clarification, and a menu to appear when they choose to reveal it.
  - Avoid letting an action sheet scroll — more buttons means more time and effort, and scrolling can cause inadvertent taps.
- **watchOS**:
  - The system-defined style includes a title, an optional message, a Cancel button, and one or more additional buttons; appearance varies by device. Each button uses one of three styles:

| Style | Meaning |
|---|---|
| Default | The button has no special meaning |
| Destructive | Destroys user data or performs a destructive action in the app |
| Cancel | Dismisses the view without taking any action |

  - Avoid displaying more than four buttons including Cancel — aim for no more than three additional choices so people can view all options at once.

### Resources
- confirmationDialog(_:isPresented:titleVisibility:actions:) — SwiftUI; UIAlertController.Style.actionSheet — UIKit

## Sheets
A sheet helps people perform a scoped task that's closely related to their current context.

In macOS, tvOS, visionOS, and watchOS a sheet is always modal; in iOS and iPadOS it can be modal or nonmodal (a nonmodal sheet lets people affect the parent view without dismissing it, like the Notes format sheet). Common buttons: Cancel/Close (dismiss without saving), Done (dismiss after completing or saving), Back (navigate to a previous step or parent view — not to dismiss).

### Best practices
- For complex or prolonged flows, consider alternatives to sheets: a full-screen modal view in iOS/iPadOS (video, photos, camera, or multistep editing); a new window or full-screen mode in macOS (self-contained document editing suits a separate window; media benefits from full screen); a Full Space in visionOS.
- Display only one sheet at a time from the main interface. If something within a sheet results in another sheet, close the first before displaying the new one; if necessary, redisplay the first after the second is dismissed.
- Use a nonmodal view to present supplementary items that affect the main task in the parent view: a split view (visionOS), a panel (macOS), or a nonmodal sheet (iOS/iPadOS).
- Provide an alternative to Done: pair Done with a Cancel button (a clear exit without confirming or saving) or a Back button (previous step). Relying solely on Done implies completing the task is the only way out, which feels restrictive or misleading.
- Avoid showing all three buttons — Cancel, Done, and Back — together.

### Platform considerations
- **tvOS**: No additional considerations.
- **iOS, iPadOS**:
  - Single-view sheet: Cancel belongs on the leading edge of the top toolbar; Done (when present) on the trailing edge.
  - Multi-step flow: button placement varies across steps; on the first step, Cancel is leading and Done is trailing but inactive until the task is complete.
  - A resizable sheet expands when people scroll its contents or drag the grabber, resting at detents — heights at which a sheet naturally rests. System detents: large (fully expanded) and medium (about half). Sheets can have one or more custom detent values; adding medium lets the sheet rest at both heights, while specifying only medium prevents full expansion.
  - On iPhone, consider the medium detent for progressive disclosure (like the share sheet showing the most relevant items); skip it when content is more useful at full height (Messages and Mail compose sheets).
  - Include a grabber in a resizable sheet — it signals resizability, taps cycle through detents, and it works with VoiceOver so people can resize without seeing the screen.
  - Support swiping to dismiss a sheet; if people have unsaved changes when they begin swiping, use an action sheet to confirm.
  - In an iPadOS app, prefer the page or form sheet presentation styles (default size, centered content over a dimmed background).
- **macOS**:
  - A sheet is a cardlike view with rounded corners floating on its parent window; the parent is dimmed, but people expect to interact with other app windows before dismissing the sheet.
  - Present a sheet in a reasonable default size — people don't generally expect to resize sheets, though supporting resizing can help when people need a clearer view.
  - Let people interact with other app windows without first dismissing a sheet: when a sheet opens, bring its parent window (and modeless document-related panels) forward, but keep other windows accessible.
  - Use a panel instead of a sheet when people need to repeatedly provide input and observe results (for example, find and replace).
- **visionOS**:
  - A sheet floats in front of its parent window, dimming it and becoming the target of interaction.
  - Avoid a sheet that emerges from the bottom edge of a window; prefer centering it in the field of view.
  - Present in a default size that helps people retain context — avoid covering most or all of the window; consider letting people resize it.
- **watchOS**:
  - A sheet is a full-screen view that slides over current content; it's semitransparent, with a system material that blurs and desaturates the covered content.
  - Use a sheet only when a modal task requires a custom title or custom content presentation; for important information or a set of choices, use an alert or action sheet.
  - Keep sheet interactions brief and occasional — a temporary interruption to facilitate an important task; avoid using a sheet for navigation.
  - If you change the default label, prefer SF Symbols; avoid labels that suggest hierarchical navigation or that look like a page/app title in the top-leading corner (people won't know how to dismiss the sheet).

### Resources
- sheet(item:onDismiss:content:) — SwiftUI; UISheetPresentationController — UIKit; presentAsSheet(_:) — AppKit
