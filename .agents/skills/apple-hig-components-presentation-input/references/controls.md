> Source: https://developer.apple.com/design/human-interface-guidelines/pickers
> Source: https://developer.apple.com/design/human-interface-guidelines/segmented-controls
> Source: https://developer.apple.com/design/human-interface-guidelines/sliders
> Source: https://developer.apple.com/design/human-interface-guidelines/steppers
> Source: https://developer.apple.com/design/human-interface-guidelines/toggles
> Source: https://developer.apple.com/design/human-interface-guidelines/color-wells
> Source: https://developer.apple.com/design/human-interface-guidelines/image-wells

# Pickers, segmented controls, sliders, steppers, toggles, color wells, image wells

## Pickers
A picker displays one or more scrollable lists of distinct values that people can choose from.

The system provides several picker styles with different appearances; the exact values shown and their order depend on the device language. Date pickers offer additional ways to choose values, like a calendar view or a numeric keypad.

### Best practices
- Consider a picker for medium-to-long lists of items. For a fairly short list, use a pull-down button instead (a picker adds too much visual weight); for a very large set, use a list or table (adjustable height, and tables can include an index for faster targeting).
- Use predictable and logically ordered values — before interaction, many values are hidden, and people should be able to predict them (like an alphabetized country list) to move through items quickly.
- Avoid switching views to show a picker; display it in context, below or near the field being edited (typically at the bottom of a window or in a popover).
- Consider less granularity for minutes in a date picker: the default minute list has 60 values (0 to 59); increase the interval only if it divides evenly into 60 (for example, quarter hours: 0, 15, 30, 45).

### Platform considerations
- No additional considerations for visionOS.
- **iOS, iPadOS**:
  - Date picker styles:

| Style | Description |
|---|---|
| Compact | A button that displays editable date and time content in a modal view |
| Inline | Time only: a button with wheels of values; dates and times: an inline calendar view |
| Wheels | Scrolling wheels; also supports data entry through built-in or external keyboards |
| Automatic | A system-determined style based on the current platform and mode |

  - Date picker modes:

| Mode | Selectable values |
|---|---|
| Date | Months, days of the month, and years |
| Time | Hours, minutes, and (optionally) an AM/PM designation |
| Date and time | Dates, hours, minutes, and (optionally) an AM/PM designation |
| Countdown timer | Hours and minutes, up to a maximum of 23 hours 59 minutes; not available in the inline or compact styles |

  - Values and their order depend on the device location; in a compact layout, the picker opens as a popover over your content.
  - Use the compact date picker when space is constrained: it displays a button showing the current value in your accent color; tapping opens a modal view with a familiar calendar-style editor and time picker, where people can make multiple edits before tapping outside to confirm.
- **macOS**: Choose a date picker style that suits your app — textual for limited space and specific date/time selections; graphical for browsing days in a calendar, selecting a range of dates, or when a clock face fits.
- **tvOS**: Pickers are available with SwiftUI.
- **watchOS**: People navigate picker lists with the Digital Crown for precise, engaging selection; lists can use the wheels style, including date and time pickers. You can configure a picker to display an outline, caption, and scrolling indicator. For longer lists, a navigation link displays the picker as a button — tapping shows the options, or people can scrub through them with the Digital Crown without tapping.

### Resources
- Picker — SwiftUI; UIDatePicker, UIPickerView — UIKit; NSDatePicker — AppKit

## Segmented controls
A segmented control is a linear set of two or more segments, each of which functions as a button.

Segments are usually equal in width and can contain text or images (labels can also sit beneath segments or the control). A control offers a single choice from a set of options — or, in macOS, single or multiple choices — and can instead function as a set of momentary buttons that perform actions without showing a selection state.

### Best practices
- Use a segmented control to provide closely related choices that affect an object, state, or view (choosing attributes in an inspector; actions on the current view in a toolbar).
- Consider a segmented control when it's important to group functions together or clearly show their selection state — grouping is preserved regardless of view size or placement, helping people see at a glance which controls are selected.
- Keep control types consistent within a single control: don't assign actions to segments in a selection-state control, and don't show selection states in a control that performs actions.
- Limit the number of segments — too many are hard to parse and time-consuming to navigate:

| Context | Guideline |
|---|---|
| Wide interface | No more than about 5-7 segments |
| iPhone | No more than about 5 segments |

- Keep segment size consistent: equal widths feel balanced; keep icon and title widths consistent too.
- Prefer either text or images — not a mix — in a single control; mixing leads to a disconnected, confusing interface.
- Use similar-size content in each segment; because segments are equal width, content filling some but not others doesn't look good.
- Use nouns or noun phrases for segment labels, with title-style capitalization; a control displaying text labels doesn't need introductory text.

### Platform considerations
- **Not supported in watchOS.**
- **iOS, iPadOS**: Consider a segmented control to switch between closely related subviews (Calendar's New Event sheet switches between event and reminder creation); use a tab bar for switching between completely separate sections of an app.
- **macOS**:
  - Consider introductory text to clarify the purpose; add a label below each segment when using symbols or interface icons, and provide a tooltip for each segment if your app includes tooltips.
  - Use a tab view — not a segmented control — for view switching in the main window area; a segmented control suits a toolbar or inspector pane.
  - Consider supporting spring loading: drag selected items over a segment and force click to activate it without dropping them; people can continue dragging afterward.
- **tvOS**: Consider a split view instead of a segmented control on screens that perform content filtering — people find back-and-forth navigation easy in a split view, and a segmented control may be harder to access depending on placement. Avoid putting other focusable elements close to segmented controls: segments become selected when focus moves to them, not when people click, so nearby elements invite accidental focus.
- **visionOS**: When people look at a segmented control that uses icons, the system displays a tooltip containing the descriptive text you supply.

### Resources
- segmented — SwiftUI; UISegmentedControl — UIKit; NSSegmentedControl — AppKit

## Sliders
A slider is a horizontal track with a control, called a thumb, that people can adjust between a minimum and maximum value.

The portion of track between the minimum value and the thumb fills with color; optional left and right icons can illustrate the meaning of the extremes.

### Best practices
- Customize a slider's appearance if it adds value — track color, thumb image and tint, and end icons can blend with your design and communicate intent (small/large image icons on an image-size slider).
- Use familiar slider directions: minimum on the leading side and maximum on the trailing side (horizontal), minimum at the bottom and maximum at the top (vertical). People expect a percentage slider to run from 0 on the leading side to 100 on the trailing side.
- Consider supplementing a slider with a corresponding text field and stepper, especially for a wide range: people appreciate seeing and entering the exact value, and a stepper offers convenient whole-value increments.

### Platform considerations
- **Not supported in tvOS.**
- **iOS, iPadOS**: Don't use a slider to adjust audio volume — use a volume view, which includes a volume-level slider and a control for changing the active audio output device.
- **macOS**: Sliders can include tick marks for pinpointing specific values. A linear slider's thumb is a narrow lozenge with a filled track; a circular slider's thumb is a small circle, with tick marks as evenly spaced dots around the circumference.
  - Consider giving live feedback as the value changes, showing results in real time (Dock icons scale dynamically while adjusting the Size slider).
  - Choose a style matching expectations: a horizontal slider for moving between a fixed starting and ending point (opacity from 0 to 100 percent); a circular slider when values repeat or continue indefinitely (rotation 0-360 degrees, spin counts).
  - Consider using a label to introduce a slider — sentence-style capitalization, ending with a colon.
  - Use tick marks to increase clarity and accuracy; they help people understand the scale and locate specific values.
  - Consider labels on tick marks for even greater clarity (numbers or words): labeling every tick is usually unnecessary — minimum and maximum often suffice; use periodic labels for nonlinear values (like the Energy Saver pane), and provide a tooltip displaying the thumb's value on hover.
- **visionOS**: Prefer horizontal sliders — it's generally easier for people to gesture from side to side than up and down.
- **watchOS**: A slider is a horizontal track — discrete steps or a continuous bar — representing a finite range; people tap buttons on its sides to change the value by a predefined amount. If necessary, create custom glyphs to communicate what the slider does (the system displays plus and minus signs by default).

### Resources
- Slider — SwiftUI; UISlider — UIKit; NSSlider — AppKit

## Steppers
A stepper is a two-segment control that people use to increase or decrease an incremental value.

A stepper sits next to a field that displays its current value, because the stepper itself doesn't display a value.

### Best practices
- Make the value a stepper affects obvious — since the stepper displays no value itself, people need to know which value they're changing.
- Consider pairing a stepper with a text field when large value changes are likely: steppers work well for small changes requiring a few taps or clicks, while a field lets people enter specific values that vary widely (copies to print, for example).

### Platform considerations
- No additional considerations for iOS, iPadOS, or visionOS. **Not supported in watchOS or tvOS.**
- **macOS**: For large value ranges, consider supporting Shift-click to change the value quickly — by more than the default increment (10 times the default, for example).

### Resources
- UIStepper — UIKit; NSStepper — AppKit

## Toggles
A toggle lets people choose between a pair of opposing states, like on and off, using a different appearance to indicate each state.

Styles include switch and checkbox, used differently per platform; all platforms also support buttons that behave like toggles by changing appearance for each state.

### Best practices
- Use a toggle to help people choose between two opposing values that affect the state of content or a view; for other action types — like choosing from a list of items — use a different component, such as a pop-up button.
- Clearly identify the setting, view, or content the toggle affects; context usually provides enough information, though macOS apps sometimes supply a label. A button that behaves like a toggle uses an interface icon that communicates its purpose plus a state-dependent appearance (typically the background).
- Make the visual differences between states obvious — add or remove a color fill, show or hide the background shape, or change inner details like a checkmark or dot. Avoid relying solely on different colors to communicate state, because not everyone can perceive the differences.

### Platform considerations
- No additional considerations for tvOS, visionOS, or watchOS.
- **iOS, iPadOS**:
  - Use the switch toggle style only in a list row; the row's content provides context, so no label is needed.
  - Change the default switch color only if necessary — the default green works well in most cases; an accent-color switch must contrast enough with the uncolored state to be perceptible.
  - Outside a list, use a button that behaves like a toggle, not a switch (the Phone app highlights its filter button in blue when active and removes the highlight when inactive); avoid supplying a label that explains the button's purpose — the interface icon plus alternate background appearances communicate it.
- **macOS**: In addition to the switch style, macOS supports checkboxes and radio buttons with similar behaviors.
  - Use switches, checkboxes, and radio buttons in the window body, not the window frame — in particular, avoid them in a toolbar or status bar.
  - *Switches*: Prefer a switch for settings you want to emphasize — it has more visual weight than a checkbox and suits controlling more functionality (turning a group of settings on or off). In a grouped form, consider a mini switch for single-row settings (its height matches buttons and other controls; use a regular switch for the primary setting and mini switches for subordinate ones). In general, don't replace a checkbox with a switch — keep existing checkboxes.
  - *Checkboxes*: A small, square button that's empty when off, contains a checkmark when on, and can contain a dash when mixed; typically includes a title on its trailing side (an editable checklist can omit the title).
    - Use a checkbox instead of a switch to present a hierarchy of settings: alignment and indentation show dependencies, such as a checkbox governing subordinate checkboxes.
    - Consider radio buttons when people need to choose from more than two mutually exclusive options — unique labels clarify each option.
    - Consider a label to introduce a group of checkboxes if their relationship isn't clear; describe the set and align the label's baseline with the first checkbox.
    - Accurately reflect a checkbox's state in its appearance: if it globally turns subordinate checkboxes on and off, show the mixed state when the subordinates differ (like a text-style setting governing bold, italic, and underline).
  - *Radio buttons*: A small, circular button followed by a label, typically displayed in groups of two to five mutually exclusive choices; selected is a filled circle, deselected is empty. The mixed state (a dash) is rarely useful — use a checkbox instead.
    - Prefer a set of radio buttons to present mutually exclusive options; if people can choose multiple options in a set, use checkboxes.
    - Avoid listing too many radio buttons — a long list takes space and overwhelms; more than about five options warrants a pop-up button.
    - For a single on/off setting, prefer a checkbox — the checkmark's presence or absence reads faster at a glance; use a pair of labeled radio buttons only in the rare case a checkbox doesn't clearly communicate the opposing states.
    - Use consistent spacing for horizontal radio buttons: measure the space needed for the longest label and use it throughout.

### Resources
- Toggle — SwiftUI; UISwitch — UIKit; NSSwitch, NSButton.ButtonType.toggle — AppKit

## Color wells
A color well lets people adjust the color of text, shapes, guides, and other onscreen elements.

A color well displays a color picker when people tap or click it — the system-provided one or a custom interface you design.

### Best practices
- Consider the system-provided color picker for a familiar experience: it's consistent, lets people save a set of colors accessible from any app, and provides familiarity when developing across iOS, iPadOS, and macOS.

### Platform considerations
- No additional considerations for iOS, iPadOS, or visionOS. **Not supported in tvOS or watchOS.**
- **macOS**: Clicking a color well highlights it (visual confirmation it's active), opens the color picker, and updates the well with the new selection. Color wells also support drag and drop — people can drag colors from one well to another, and from the color picker to a well.

### Resources
- UIColorWell, UIColorPickerViewController — UIKit; NSColorWell — AppKit

## Image wells
An image well is an editable version of an image view.

After selecting an image well, people can copy and paste its image or delete it; people can also drag a new image into a well without selecting it first.

### Best practices
- Revert to a default image when necessary: if your image well requires an image, display the default image again when people clear the well's content.
- If your image well supports copy and paste, make sure the standard copy and paste menu items are available — people expect to choose these menu items or use the standard keyboard shortcuts.

### Platform considerations
- **Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS** (macOS only).

### Resources
- NSImageView — AppKit
