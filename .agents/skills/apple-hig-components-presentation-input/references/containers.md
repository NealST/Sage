> Source: https://developer.apple.com/design/human-interface-guidelines/page-controls
> Source: https://developer.apple.com/design/human-interface-guidelines/scroll-views

# Page controls, scroll views

## Page controls
A page control displays a row of indicator images, each of which represents a page in a flat list.

The scrolling row of indicators helps people navigate to the page they want. Indicators are small dots by default (a solid dot marks the current page), always equidistant, and clipped if there are too many to fit. Page controls can handle an arbitrary number of pages.

### Best practices
- Use page controls to represent movement between an ordered list of pages — not hierarchical or nonsequential relationships. For more complex navigation, use a sidebar or split view.
- Center a page control at the bottom of the view or window, so people always know where to find it.
- Don't display too many pages: more than about 10 dots are hard to count at a glance. If your app needs more than 10 peer pages, use a different arrangement — such as a grid — that lets people navigate in any order.

**Customizing indicators**
- You can supply a custom default indicator image and a different image for a specific page (Weather uses `location.fill` to mark the current location's page).
- Make custom indicator images simple and clear: avoid complex shapes, negative space, text, and inner lines — these details become muddy and indecipherable at very small sizes. Prefer simple SF Symbols or your own simple icons.
- Customize the default indicator image only when it enhances the control's overall meaning (for example, `bookmark.fill` when every page lists bookmarks).
- Avoid using more than two different indicator images — several unique images force people to memorize each meaning and look messy, even when each image is clear.
- Avoid coloring indicator images; custom colors reduce the contrast that differentiates the current page and keeps the control visible. Let the system color indicators.

### Platform considerations
- **Not supported in macOS.**
- **iOS, iPadOS**: The control can highlight the current-page indicator (so people can estimate relative position) and shrink indicators at both sides to suggest more pages.
  - Interaction: tapping the leading or trailing side of the current-page indicator reveals the next or previous page; in iPadOS, people can also use the pointer to target a specific indicator. Scrubbing (touching and dragging left or right) opens pages in sequence; scrubbing past an edge quickly reaches the first or last page. (Tapping is a discrete interaction; scrubbing is continuous.)
  - Avoid animating page transitions during scrubbing — people can scrub very quickly, and the scrolling animation for every transition causes lag and distracting visual flashes. Use the animated scrolling transition only for tapping.
  - Background styles for the translucent, rounded-rectangle appearance:

| Style | Background visibility | Use when |
|---|---|---|
| Automatic | Only while people interact with the control | The page control isn't the primary navigational element |
| Prominent | Always displayed | The control is the primary navigational control on screen |
| Minimal | Never displayed | Only showing the current page's position; no scrubbing feedback needed |

  - Avoid supporting the scrubber when you use the minimal background style — it provides no scrubbing feedback; use the automatic or prominent styles instead.
- **tvOS**: Use page controls only on collections of full-screen pages — they're designed for a full-screen environment where multiple content-rich pages are peers; additional controls make it difficult to maintain focus while moving between pages.
- **visionOS**: Page controls represent available pages and indicate the current page, but people don't interact with them.
- **watchOS**: Page controls appear at the bottom of the screen for horizontal pagination, or next to the Digital Crown for a vertical tab view; the indicator transitions between scrolling through a page's content and scrolling to other pages.
  - Use vertical pagination to separate multiple views into distinct, purposeful pages people scroll with the Digital Crown — more effective than horizontal pagination or many levels of hierarchical navigation.
  - Consider limiting a page's content to a single screen height; this makes each page serve a clear purpose and results in a more glanceable design. Use variable-height pages judiciously and place them after fixed-height pages when possible.

### Resources
- PageTabViewStyle — SwiftUI; UIPageControl — UIKit

## Scroll views
A scroll view lets people view content that's larger than the view's boundaries by moving the content vertically or horizontally.

A scroll view has no appearance itself but can display a translucent scroll indicator that typically appears after scrolling begins; indicators provide visual feedback about the scrolling action, showing whether visible content is near the beginning, middle, or end.

### Best practices
- Support the default scrolling gestures and keyboard shortcuts; people expect systemwide scrolling behavior everywhere. If you build custom scrolling, make sure your indicators use the elastic behavior people expect.
- Make it apparent when content is scrollable — indicators aren't always visible, so display partial content at a view edge to show there's more, and consider drawing attention to it.
- Avoid putting a scroll view inside another scroll view with the same orientation — it creates an unpredictable interface. A horizontal scroll view inside a vertical one (or vice versa) is fine.
- Consider supporting page-by-page scrolling when it suits the content: define the page size (typically the view's current height or width) and define a unit of overlap (a line of text, a row of glyphs, part of a picture) to subtract from the page size, helping people retain context.
- Scroll automatically to help people find their place when: your app performs an operation that selects content or places the insertion point in a hidden area (like search results); people start entering information in a location that's not visible (return to the insertion point as soon as they begin typing); the pointer moves past the view's edge during a selection (follow the pointer); or people select something and scroll away before acting on it (scroll the selection into view first). In all cases, scroll only as much as necessary — a partially visible selection doesn't need to be fully scrolled into view.
- If you support zoom, set appropriate maximum and minimum scale values — zooming text until a single character fills the screen rarely makes sense.

**Scroll edge effects** (iOS, iPadOS, macOS)
- A scroll edge effect provides visual separation between floating interface elements (like toolbars) and the scrolling content behind them; with custom bars, you may need to add it manually or adjust its style.
- Prefer the automatic style: it provides a more opaque separation suited to top toolbars with many controls, text outside Liquid Glass controls, and pinned table headers. If you use the soft style, thoroughly test that controls remain legible in a variety of contexts.
- Use a scroll edge effect only when a scroll view is behind floating interface elements — it isn't decorative, and it doesn't block or darken content; it keeps controls visually distinct.
- Apply one scroll edge effect per view; in split view layouts on iPad and Mac, each pane can have its own, but keep them consistent in height to maintain alignment.

### Platform considerations
- **iOS, iPadOS**: Consider showing a page control when a scroll view is in page-by-page mode (it shows how many chunks of content are available and which is visible); if you do, don't also show the scrolling indicator on the same axis — redundant controls confuse people.
- **macOS**: A scroll indicator is commonly called a scroll bar. When space is tight, use small or mini scroll bars in a panel — and use the same size for all controls in that panel.
- **tvOS**: Views can scroll, but they aren't treated as distinct objects with scroll indicators; when content exceeds the screen, the system automatically scrolls to keep focused items visible.
- **visionOS**: The scroll indicator has a small, fixed size and appears in a predictable location relative to the window — vertically centered at the trailing edge during vertical scrolling, horizontally centered at the bottom edge during horizontal scrolling. When people look at the indicator and begin a drag, it enables a jog bar experience: tick marks speed up or slow down with small gesture adjustments for precise control of scrolling acceleration.
  - If necessary, account for the indicator's size — it's a little thicker than in iOS; increase tight margins so it doesn't overlap content.
  - **Look to Scroll**: in supporting views, people scroll using only their eyes — scrolling starts when they look near the scroll view's boundary (top/bottom for vertical, sides for horizontal) and works alongside existing gestures.
    - Support Look to Scroll in reading or browsing views for a comfortable, hands-free experience (it doesn't work by default; add it to each individual scroll view).
    - Avoid it for secondary content — views containing UI controls or dense information that requires quick, precise scrolling (Notes supports it in the reading view, not the note list).
    - Maintain consistency across content: if you support it for one view, support it for all similar views (for example, every collection view of videos).
    - Define clear scroll areas: prefer making the view the full width or height of the window for generous space and clear edges; if you inset a scroll view, provide clear boundaries so people know where to look.
    - Remove custom scroll effects or animations (like parallax) before supporting Look to Scroll — they can make it behave unexpectedly.
- **watchOS**: Prefer vertically scrolling content — people use the Digital Crown to navigate to and within apps.
  - Use tab views to provide page-by-page scrolling: tab views display as pages, and a vertical stack lets people rotate the Digital Crown through full-screen pages, with a page indicator next to the Crown showing position.
  - Consider limiting a page's content to a single screen height for glanceability; long pages still work because the page indicator expands into a scroll indicator when necessary. Use variable-height pages judiciously and place them after fixed-height pages when possible.

### Resources
- ScrollView — SwiftUI; UIScrollView — UIKit; NSScrollView — AppKit; WKPageOrientation — WatchKit; look — SwiftUI
