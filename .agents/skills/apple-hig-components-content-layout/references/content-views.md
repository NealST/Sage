> Source: https://developer.apple.com/design/human-interface-guidelines/charts
> Source: https://developer.apple.com/design/human-interface-guidelines/image-views
> Source: https://developer.apple.com/design/human-interface-guidelines/text-views
> Source: https://developer.apple.com/design/human-interface-guidelines/web-views

# Charts, image views, text views, web views

## Charts
Organize data in a chart to communicate information with clarity and visual appeal.

An effective chart highlights a few key pieces of information in a dataset, helping people gain insights and make decisions (upcoming weather, stock trends, fitness progress).

### Anatomy
- A **mark** is the visual representation of a data value; you create a chart by supplying one or more series of data values, assigning each value to a mark. Choosing a mark type — bar, line, or point — specifies the chart style (bar chart, line chart, scatter plot). Depicting individual values is called plotting; the area containing the marks is the **plot area**.
- A **scale** maps data values (numbers, dates, categories) to visual attributes determined by the mark type, such as position, color, or height.
- An **axis** defines a frame of reference for a set of marks — many charts display a horizontal and a vertical axis at the plot area edges, each representing a variable like time, amount, or category. An axis can include **ticks** (reference points like 0, 50%, and 100%) and **grid lines** extending from each tick across the plot area to help people estimate values.
- Descriptive content: labels naming axes, grid lines, ticks, or marks; accessibility labels for assistive technologies; titles, subtitles, and annotations for context; and a **legend** describing chart properties unrelated to a mark's position, such as using color or shape to denote value categories.

### Marks
- Use bar marks to help people compare values across categories or view the relative proportions of parts in a whole; for data changing over time, bar charts work especially well when each value can represent a sum (total steps in a day).
- Use line marks to show how values change over time: a line connects all values in one series, and its slope reveals the magnitude of change and overall trends.
- Use point marks to depict individual data values as visually distinct marks; a set of point marks shows how two data properties relate and helps people inspect individual values and identify outliers and clusters.
- Consider combining mark types when it adds clarity — e.g., add point marks on top of a line to highlight individual data points while still showing the trend.

### Axes
- Use a fixed axis range when specific minimum and maximum values are meaningful for all possible data values (battery charge: 0%–100%); use a dynamic range when values vary widely and you want marks to fill the plot area (Health's Steps chart varies the Y-axis upper bound so the largest value sits near the top).
- Define the lower bound based on mark type and chart usage: zero works well for bar charts because people compare relative bar heights, but a zero lower bound can obscure meaningful differences occurring far from zero (a heart-rate chart using zero could hide the difference between resting and active readings).
- Prefer familiar tick and grid-line label sequences like 0, 5, 10 — people grasp the interval at a glance; an equally consistent but uncommon sequence like 1, 6, 11 makes people spend extra time on the interval.
- Tailor grid-line and label appearance to the chart's use cases: too many grid lines visually overwhelm and distract from the data; too few make a mark's value hard to estimate. If people can inspect individual data points by interacting with the chart, use fewer grid lines and light label colors so the data stays visually prominent.

### Descriptive content
- Write information-rich titles and labels describing a chart's purpose and functionality so people have context before examining the details — especially important for VoiceOver users and people with certain cognitive disabilities, who rely on descriptions to understand the chart's purpose and primary message.
- Summarize the chart's main message so people can grasp key information quickly (Weather uses a title and subtitle that succinctly describe expected precipitation for the next hour).

### Best practices
- Establish a consistent visual hierarchy: keep the data itself most prominent, with descriptions and axes providing context without competing with it.
- In a compact environment, maximize the plot area width: keep vertical-axis labels as short as possible without losing clarity, describe units elsewhere (e.g., in a title), and place a longer axis label such as a category name inside the plot area when it doesn't obscure important information.
- Make every chart accessible: support VoiceOver, supply accessibility labels describing chart components, and use Audio Graphs, which let VoiceOver construct tones that audibly represent the chart's data values and trend and also present high-level text summaries.
- Let people interact with the data when it makes sense, but don't require interaction to reveal critical information (Stocks shows a performance line graph for a chosen period; dragging a vertical indicator reveals the value at the selected time).
- Make interaction easy for everyone: when marks are too small to target with a finger or pointer, expand the hit target to the entire plot area so people can scrub across it to reveal values — hard-to-target marks are a problem for people with reduced motor control and uncomfortable for everyone.
- Make an interactive chart easy to navigate using keyboard commands (including full keyboard access) or Switch Control, which by default visit elements linearly. Two customization approaches: use accessibility APIs such as `accessibilityRespondsToUserInteraction(_:)` to specify a logical, predictable path (e.g., navigate along the X axis instead of jumping back and forth), or — particularly for very large datasets — let people move focus among subsets of values instead of every individual point. Both customizations also enhance the VoiceOver experience even when the chart isn't interactive.
- Help people notice important changes in marks or axes — unnoticed changes cause misreadings. Animate the changes, but also highlight them in other ways so VoiceOver users and people who turn off animations know about them.

### Color
- Avoid relying solely on color to differentiate data or communicate essential information; supplement color with different shapes or patterns so the chart works regardless of color perception (Health uses two different point-mark shapes in addition to red and black/white for the two blood-pressure components).
- Aid comprehension by adding visual separation between contiguous areas of color — e.g., separators between marks stacked in a single row or column help people distinguish individual marks.

### Chart accessibility labels
- Swift Charts provides a default Audio Graphs implementation plus a default accessibility element for each mark (or group of marks) that describes its value; customize Audio Graphs by supplying a chart title and descriptive summary that VoiceOver speaks.
- If you don't use Audio Graphs, provide an overview of the chart's structure and purpose: identify the chart type (bar, line, …), explain what each axis represents, and describe details like the upper and lower axis bounds.
- Unlike an image, which requires one descriptive accessibility label, a chart often needs an accessibility label for each important or interactive element. Decide per chart whether describing each mark, groups of marks, or — for a small chart inside a button that reveals a more detailed version — a single succinct high-level description works best.
- Write labels that support the chart's purpose: Maps summarizes elevation changes over portions of a route rather than labeling every moment, because the purpose is a sense of overall terrain; Health provides a label for each Steps bar because the purpose is the actual step count per period.
- Prioritize clarity and comprehensiveness: it's rarely enough to report a bare data value — include context like the associated date or location, don't repeat information available elsewhere (e.g., axis names Audio Graphs or your overview already provide), and follow context-setting information with a succinct description of the element's details.
- Avoid subjective terms like "rapidly," "gradually," and "almost" — they communicate your interpretation; use actual values so people form their own.
- Avoid ambiguous formats and abbreviations: "June 6" is clearer than "6/6"; "60 minutes" or "60 meters" is clearer than "60m."
- Describe what the chart's details represent, not what they look like — identify what each series represents, but don't narrate the colors that visually represent them.
- Be consistent throughout your app when referring to a specific axis (e.g., always mention the X axis first) so people spend less time figuring out which axis is relevant.
- Hide visible axis and tick text labels from assistive technologies — VoiceOver users get values and trend information from accessibility labels and Audio Graphs and don't need the visible label content.

### Platform considerations
- iOS, iPadOS, macOS, tvOS, visionOS: no additional considerations.
- watchOS: Avoid requiring complex chart interactions; prefer glanceable information and simple interactions that add value. If you offer the app on another platform, consider using that version to display more details and additional chart interactions (watchOS Heart Rate shows current-day data only; the Health app on iPhone shows several periods and lets people examine individual marks).

### Resources
- Swift Charts; Audio Graphs; `UIAccessibility.Notification` (UIKit); `NSAccessibility.Notification` (AppKit); Charting data (related HIG page)

## Image views
An image view displays a single image — or in some cases, an animated sequence of images — on a transparent or opaque background.

Within an image view, you can stretch, scale, size to fit, or pin the image to a specific location. Image views are typically not interactive.

### Best practices
- Use an image view when the primary purpose of the view is simply to display an image; if an image must be interactive, configure a system-provided button to display the image rather than adding button behaviors to an image view.
- To display an icon, consider a symbol or interface icon instead of an image view: SF Symbols provides a large library of streamlined, vector-based images renderable with various colors and opacities; an interface icon (also called a glyph or template image) is a bitmap whose nontransparent pixels can receive color. Both symbols and interface icons can use the accent colors people choose.
- Support rich image data in formats like PNG, JPEG, and PDF.
- Take care when overlaying text on images: compositing text over images decreases both the clarity of the image and the legibility of the text — ensure the text contrasts well with the image and make it stand out (e.g., text shadow or background layer).
- Use a consistent size for all images in an animated sequence: prescale images to fit the view so the system doesn't have to scale, and when the system must scale, performance is better when all images are the same size and shape.

### Platform considerations
- iOS, iPadOS: no additional considerations.
- macOS: For an editable image view, use an image well (an image view supporting copying, pasting, dragging, and Delete-key clearing of content). To make a clickable image, use an image button, which contains an image or icon and initiates an instantaneous app-specific action.
- tvOS: Many tvOS images combine multiple layers with transparency to create a feeling of depth (see Layered images).
- visionOS: Windows can use image views to display 2D and stereoscopic images as well as spatial photos; with RealityKit, you can also display images of any type outside image views next to 3D content, or generate a spatial scene from an existing 2D image.
- watchOS: Use SwiftUI to create animations when possible; alternatively use WatchKit to animate a sequence of images within an image element.

### Resources
- Image — SwiftUI; UIImageView — UIKit; NSImageView — AppKit; ImagePresentationComponent (visionOS/RealityKit); WKImageAnimatable (watchOS)

## Text views
A text view displays multiline, styled text content, which can optionally be editable.

Text views can be any height and scroll when content extends outside the view; by default, content is aligned to the leading edge and uses the system label color. In iOS, iPadOS, and visionOS, a keyboard appears when people select an editable text view.

### Best practices
- Use a text view for text that's long, editable, or in a special format: text views provide the most options for displaying specialized text and receiving text input. For a small amount of text, use a label (read-only) or a text field (editable) — they're simpler.
- Keep text legible: maintain readability despite multiple fonts, colors, and alignments; adopt Dynamic Type so text still looks good when people change text size; test with accessibility options like bold text turned on.
- Make useful text selectable: if the view contains useful information like an error message, serial number, or IP address, consider letting people select and copy it for pasting elsewhere.

### Platform considerations
- macOS, visionOS, watchOS: no additional considerations.
- iOS, iPadOS: Show the appropriate keyboard type — each keyboard type is designed for a different input, so the displayed keyboard must suit the content being edited.
- tvOS: You can display text in a text view, but because text input in tvOS is minimal by design, tvOS uses text fields for editable text instead.

### Resources
- Text — SwiftUI; UITextView — UIKit; NSTextView — AppKit

## Web views
A web view loads and displays rich web content, such as embedded HTML and websites, directly within your app.

For example, Mail uses a web view to show HTML content in messages.

### Best practices
- Support forward and back navigation when appropriate: web views support it, but the behavior isn't available by default — if people are likely to visit multiple pages, allow forward and back navigation and provide corresponding controls to initiate it.
- Avoid using a web view to build a web browser: letting people briefly access a website without leaving your app's context is fine, but Safari is the primary way people browse the web — replicating Safari's functionality in your app is unnecessary and discouraged.

### Platform considerations
- iOS, iPadOS, macOS, visionOS: no additional considerations. Not supported in tvOS or watchOS.

### Resources
- WKWebView — WebKit
