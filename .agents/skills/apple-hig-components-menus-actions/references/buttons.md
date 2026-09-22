> Source: https://developer.apple.com/design/human-interface-guidelines/buttons
> Source: https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons
> Source: https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons

# Buttons, pull-down buttons, pop-up buttons

## Buttons
A button initiates an instantaneous action.

A button communicates its function through three attributes: **style** (visual style based on size, color, and shape), **content** (a symbol or icon, a text label, or both), and **role** (a system-defined semantic role that can affect appearance).

### Best practices

**General**
- Include enough space around a button to visually distinguish it from surrounding components and make it easy to activate. Minimum hit region: 44x44 pt — in visionOS, 60x60 pt — regardless of input method (fingertip, pointer, eyes, remote).
- Always include a press state for a custom button; without one, a button feels unresponsive.

**Style**
- Use a prominent visual style (system applies the accent color to its background) for the most likely action in a view; keep prominent buttons to one or two per view.
- Use style — not size — to visually distinguish the preferred choice among options; same-size buttons signal a coherent set of choices, while different sizes look confusing and inconsistent.
- Avoid applying a similar color to button labels and content layer backgrounds; over bright, colorful content prefer the default monochromatic label appearance.

**Content**
- Ensure each button clearly communicates its purpose via symbol, text label, or both, depending on platform.
- Associate familiar actions with familiar icons (for example, `square.and.arrow.up` for Share); use SF Symbols where possible.
- Consider text when a short label communicates more clearly than an icon; use title-style capitalization and start with a verb, such as "Add to Cart."
- In macOS and visionOS, the system displays a tooltip after people hover over a button briefly.

**Role**

| Role | Meaning | Appearance effect |
|---|---|---|
| Normal | No specific meaning | — |
| Primary | The default button people are most likely to choose | App accent color |
| Cancel | Cancels the current action | — |
| Destructive | Performs an action that can result in data destruction | System red color |

- Assign the primary role to the button people are most likely to choose; it responds to the Return key, and in a temporary view (sheet, editable view, alert) pressing Return can automatically close the view.
- Don't assign the primary role to a destructive action, even if it's the most likely choice — people sometimes choose a prominent button without reading it.

### Platform considerations

- **tvOS**: No additional considerations.
- **iOS, iPadOS**: Configure a button to display an activity indicator for an action that doesn't instantly complete; you can also show an alternate label (for example, "Checkout" becomes "Checking out…" while the indicator is visible and the button image is hidden).
- **macOS** — unique button types:
  - *Push buttons* (the standard type): display text, symbol, icon, image, or a combination; can act as the default button; can be tinted.
    - Use a flexible-height push button only for tall or variable-height content (two lines of text, tall icon); it keeps the same corner radius and content padding as standard buttons (`NSButton.BezelStyle.flexiblePush`).
    - Append a trailing ellipsis (…) to the title when the push button opens another window, view, or app.
    - Consider supporting spring loading (drag selected items over the button and force click to activate it without dropping the items).
  - *Square buttons* (gradient buttons): initiate an action related to a view, like adding or removing table rows.
    - Contain symbols or icons — not text; can behave like push buttons, toggles, or pop-up buttons; place in close proximity to (usually within or beneath) the associated view.
    - Use in a view, not the window frame — not in toolbars or status bars (use a toolbar item instead).
    - Prefer a symbol (`NSButton.BezelStyle.smallSquare`); avoid using labels to introduce square buttons — their purpose is generally clear from context.
  - *Help buttons*: circular, consistently sized, contain a question mark; open app-specific help documentation.
    - Use the system-provided help button; open the help topic related to the current context, or the top level of help documentation if no specific topic applies.
    - Include no more than one help button per window; use within a view, not the window frame; avoid displaying text that introduces it.

    | View style | Help button location |
    |---|---|
    | Dialog with dismissal buttons (like OK and Cancel) | Lower corner, opposite the dismissal buttons and vertically aligned with them |
    | Dialog without dismissal buttons | Lower-left or lower-right corner |
    | Settings window or pane | Lower-left or lower-right corner |
  - *Image buttons*: display an image, symbol, or icon; can behave like a push button, toggle, or pop-up button.
    - Use in a view, not the window frame; for a toolbar, use a toolbar item.
    - Include about 10 pixels of padding between the image edges and the button edges (the button edges define the clickable area); avoid a system-provided border (`isBordered`).
    - If a label is needed, position it below the image button.
- **visionOS**: Buttons typically have a visible background and play sound on interaction.
  - Standard shapes: icon-only → circle; text-only → rounded rectangle or capsule; icon + text → capsule.
  - Four interaction states: idle, hover, selected, unavailable. Custom hover effects are not supported.
  - Tooltips can appear when people look at a button briefly; buttons containing text generally don't need one.

  | Size | Height |
  |---|---|
  | Mini | 28 pt |
  | Small | 32 pt |
  | Regular | 44 pt |
  | Large | 52 pt |
  | Extra large | 64 pt |

  (All sizes available in circular, capsule (text only), capsule (text and icon), and rounded rectangle shapes.)
  - Prefer buttons with a discernible background shape and fill — except in a toolbar, context menu, alert, or ornament, where the larger component makes the button visible.
  - On top of a glass window, use the thin material as the button background; floating in space, use the glass material.
  - Avoid a custom button with white background fill and black text or icons — the system reserves this style for the toggled state.
  - Prefer circular or capsule shapes (eyes are drawn to corners; rounder shapes are easier to look at steadily); prefer capsule when a button stands alone.
  - Keep button centers at least 60 pt apart; for buttons 60 pt or larger, add 4 pt of padding so hover effects don't overlap; usually avoid small or mini buttons in vertical stacks or horizontal rows.
  - For text-labeled buttons in a stack or row: prefer rounded rectangle in a vertical stack, capsule in a horizontal row.
  - Use standard controls to take advantage of audible feedback sounds — visionOS doesn't play haptics.
- **watchOS**:
  - Inline buttons use the capsule shape and gain a material effect that contrasts with the background for legibility.
  - Use a toolbar to place buttons in the corners (the system moves the time and title to accommodate them and applies the Liquid Glass appearance).
  - Prefer full-width buttons for primary actions; if two buttons must share horizontal space, use the same height and images or short text titles.
  - Use toolbar buttons for navigation to related areas or contextual actions for the view's content.
  - Use the same height for vertical stacks of one- and two-line text buttons.

### Resources
- Button — SwiftUI; UIButton — UIKit; NSButton — AppKit

## Pull-down buttons
A pull-down button displays a menu of items or actions that directly relate to the button's purpose.

After people choose an item, the menu closes and the app performs the chosen action.

### Best practices
- Use a pull-down button to present commands or items directly related to the button's action — letting people clarify the button's target or customize its behavior without extra buttons (an Add button could present a menu specifying what to add; a Sort button could offer sort attributes; a Back button could list specific locations).
- If you need a list of mutually exclusive choices that aren't commands, use a pop-up button instead.
- Avoid putting all of a view's actions in one pull-down button — primary actions must stay easily discoverable.
- Balance menu length with ease of use: list a minimum of three items to make the interaction worthwhile; for one or two items use buttons, toggles, or switches instead; too many items slows people down.
- Display a succinct menu title only if it adds meaning — button content plus descriptive items usually provides enough context.
- Mark destructive menu items so the system highlights them in red; choosing one triggers a confirmation action sheet (iOS) or popover (iPadOS), helping people avoid losing data by mistake.
- Include an interface icon with a menu item when it provides value; display it after the label — SF Symbols stay aligned with text at every scale.

### Platform considerations
- Not supported in tvOS or watchOS. No additional considerations for macOS or visionOS.
- **iOS, iPadOS**: You can let people reveal the menu with a gesture on the button (for example, Safari in iOS 14+ shows tab actions on touch and hold of the Tabs button). Consider a More pull-down button for items that don't need prominent positions when space is constrained — but weigh its convenience against reduced discoverability, since the ellipsis icon doesn't help people predict contents.

### Resources
- MenuPickerStyle — SwiftUI; showsMenuAsPrimaryAction — UIKit; pullsDown — AppKit

## Pop-up buttons
A pop-up button displays a menu of mutually exclusive options.

After people choose an item, the menu closes and the button updates its content to indicate the current selection.

### Best practices
- Use a pop-up button for a flat list of mutually exclusive options or states that affect content or the surrounding view. Use a pull-down button instead when you need to offer a list of actions, let people select multiple items, or include a submenu.
- Provide a useful default selection — ideally the item most people are likely to want; the button shows the default until people choose something.
- Give people a way to predict the options without opening the button, such as an introductory label or a button label that describes the button's effect.
- Consider a pop-up button when space is limited and you don't need to display all options all the time.
- If necessary, include a Custom option in the menu for items needed only occasionally; you can display explanatory text below the list to help people understand the options.

### Platform considerations
- Not supported in tvOS or watchOS. No additional considerations for iOS, macOS, or visionOS.
- **iPadOS**: Within a popover or modal view, consider a pop-up button instead of a disclosure indicator to present multiple options for a list item — people can choose an option without navigating to a detail view. Best with a small, well-defined set of options that work well in a menu.

### Resources
- MenuPickerStyle — SwiftUI; changesSelectionAsPrimaryAction — UIKit; NSPopUpButton — AppKit
