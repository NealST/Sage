> Source: https://developer.apple.com/design/human-interface-guidelines/text-fields
> Source: https://developer.apple.com/design/human-interface-guidelines/combo-boxes
> Source: https://developer.apple.com/design/human-interface-guidelines/digit-entry-views
> Source: https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards

# Text fields, combo boxes, digit entry views, virtual keyboards

## Text fields
A text field is a rectangular area in which people enter or edit small, specific pieces of text.

### Best practices
- Use a text field to request a small amount of information (a name, an email address); use a text view for larger amounts of text.
- Show a hint to communicate purpose: placeholder text (like "Email" or "Password") appears when the field is empty. Because placeholders disappear when people start typing, also include a separate label describing the field.
- Use secure text fields to hide private data — always use one when your app asks for sensitive data like a password.
- Match the size of a text field to the quantity of anticipated text; size helps people visually gauge how much to provide.
- Evenly space multiple text fields so each is clearly associated with its introductory label; stack vertically when possible and use consistent widths for an organized layout (first/last name fields one width, address/city another).
- Ensure tabbing between fields flows as people expect — move focus in a logical sequence (the system attempts this automatically).
- Validate when it makes sense: if only digits are legitimate, alert people who enter other characters. Timing depends on context — validate an email address when people switch to another field; validate a user name or password before they switch.
- Use a number formatter for numeric data: it configures the field to accept only numeric values and can display decimals, percentages, or currency; don't assume the presentation, which varies significantly by locale.
- Adjust line breaks to the field's needs: by default the system clips text beyond the bounds; alternatively, wrap to a new line at the character or word level, or truncate (ellipsis) at the beginning, middle, or end.
- Consider an expansion tooltip to show the full version of clipped or truncated text when the pointer hovers over the field.
- In iOS, iPadOS, tvOS, and visionOS apps, show the appropriate keyboard type for the content people are entering (numbers, URLs, and so on).
- Minimize text entry in tvOS and watchOS apps — long passages and numerous fields are time-consuming; gather information more efficiently, such as with buttons.

### Platform considerations
- No additional considerations for tvOS or visionOS.
- **iOS, iPadOS**:
  - Display a Clear button at the trailing end of a text field so people can erase input without repeated Delete taps.
  - Use images and buttons to provide clarity and functionality: custom images at both ends, or a system-provided button like Bookmarks. Use the leading end to indicate the field's purpose and the trailing end to offer additional features.
- **macOS**: Consider a combo box when you need to pair text input with a list of choices.
- **watchOS**: Present a text field only when necessary — prefer displaying a list of options over requiring text entry.

### Resources
- TextField, SecureField — SwiftUI; UITextField — UIKit; NSTextField — AppKit

## Combo boxes
A combo box combines a text field with a pull-down button in a single control.

People can enter a custom value into the field or click the button to choose from a list of predefined values; a custom value isn't added to the list of choices.

### Best practices
- Populate the field with a meaningful default value from the list; the default doesn't have to be the first item.
- Use an introductory label to tell people what types of items to expect — title-style capitalization, ending with a colon.
- Provide relevant choices: people value both custom entry and the convenience of the most likely choices.
- Make sure list items aren't wider than the text field — truncation makes items hard to read.

### Platform considerations
- **Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS** (macOS only).

### Resources
- NSComboBox — AppKit

## Digit entry views
A digit entry view fills the entire screen and prompts people to enter a series of digits, like a PIN, using a digit-specific keyboard.

An optional title and prompt can appear above the line of digits.

### Best practices
- Use secure digit fields, which display asterisks instead of the entered digit; always use one when your app asks for sensitive data.
- Clearly state the purpose of the digit entry view with a title and prompt explaining why someone needs to enter digits.

### Platform considerations
- **Not supported in iOS, iPadOS, macOS, visionOS, or watchOS** (tvOS only).

### Resources
- TVDigitEntryViewController — TVUIKit

## Virtual keyboards
On devices without physical keyboards, the system offers various types of virtual keyboards people can use to enter data.

A virtual keyboard provides keys optimized for the current task (an email keyboard can include "@", a period, and ".com"); it doesn't support keyboard shortcuts. When it makes sense, you can replace the system keyboard with a custom view supporting app-specific data entry, and in iOS, iPadOS, and tvOS offer a custom keyboard via an app extension.

### Best practices
- Choose a keyboard that matches the type of content people are editing (for example, the numbers-and-punctuation keyboard for numeric data). Specify a semantic meaning for a text input area so the system provides a matching keyboard and can refine its corrections.
- Available keyboard types: ASCII capable, ASCII capable number pad, Decimal pad, Default, Email address, Name phone pad, Number pad, Numbers and punctuation, Phone pad, Twitter, URL, Web search.
- Consider customizing the Return key type if it clarifies the experience — the type is based on the keyboard, but a search Return key suits an app that initiates search, for consistency with other search entry points.

**Custom input views**
- Create a custom input view when it enhances data-entry tasks in your app (Numbers provides one for spreadsheet values); it replaces the system keyboard while people are in your app.
- Make sure a custom input view makes sense in context — people should understand its benefit, or they'll wonder why they can't regain the system keyboard.
- Play the standard keyboard sound while people type — it's familiar feedback people expect; they can turn keyboard sounds off for all interactions in Settings > Sounds.

**Custom keyboards** (iOS, iPadOS, tvOS app extensions)
- After people choose a custom keyboard in Settings, they can use it for text entry within any app — except when editing secure text fields and phone number fields. People can choose multiple custom keyboards and switch between them at any time.
- Build a custom keyboard to expose unique functionality systemwide (a novel input method, or a language the system doesn't support); if you want custom input only within your app, use a custom input view instead.
- Provide an obvious, easy way to switch between keyboards — people expect Globe-key-like quick switching.
- Avoid duplicating system-provided keyboard features: on some devices the Emoji/Globe key and Dictation key automatically appear beneath the keyboard even with custom keyboards, you can't affect them, and repeating them is confusing.
- Consider providing a keyboard tutorial in your app — how to choose it, activate it during text entry, use it, and switch back to the standard keyboard. Avoid displaying help content within the keyboard itself.

### Platform considerations
- **Not supported in macOS.**
- **iOS, iPadOS**:
  - Use the keyboard layout guide to make the keyboard feel integrated and to keep important parts of your interface visible while the keyboard is onscreen.
  - Place custom controls above the keyboard thoughtfully: an input accessory view should offer controls relevant to the current task; apply Liquid Glass to the containing view for consistency if your app uses it elsewhere or the view looks out of place (standard toolbars adopt it automatically); use the keyboard layout guide and standard padding so the system positions controls as expected.
- **tvOS**: The system displays a linear virtual keyboard when people select a text field using the Siri Remote; with other devices, a grid keyboard screen appears and the content layout adapts automatically. Activating a digit entry view displays a digit-specific keyboard.
- **visionOS**: The system-provided keyboard supports both direct and indirect gestures and appears in a separate window people can move where they want; you don't need to account for its location in your layouts.
- **watchOS**: A text field can show a keyboard if the device screen is large enough; otherwise people use dictation or Scribble. You can't change the keyboard type, but setting the text field's content type helps the system improve suggestions; people can also use a nearby paired iPhone to enter text.

### Resources
- keyboardType(_:), textContentType(_:) — SwiftUI; UIKeyboardType, UITextContentType — UIKit
