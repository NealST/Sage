> Source: https://developer.apple.com/design/human-interface-guidelines/progress-indicators
> Source: https://developer.apple.com/design/human-interface-guidelines/gauges
> Source: https://developer.apple.com/design/human-interface-guidelines/rating-indicators
> Source: https://developer.apple.com/design/human-interface-guidelines/activity-rings

## Progress indicators

Progress indicators let people know that your app isn't stalled while it loads content or performs lengthy operations. All are transient — visible only while an operation is ongoing.

Two types:
- **Determinate** — task with a well-defined duration (e.g., file conversion); fills a linear track (leading to trailing) or circular track (clockwise).
- **Indeterminate** (activity indicator/spinner) — unquantifiable tasks (e.g., loading or synchronizing complex data); animated spinning image on all platforms; macOS also supports an indeterminate progress bar.

### Best practices

- Prefer a determinate indicator when possible; it helps people decide whether to wait, restart later, or abandon the task.
- Report advancement accurately; even out the pace — showing 90% in five seconds and the last 10% in five minutes can feel deceptive or stalled.
- Keep indicators moving; a stationary one suggests a frozen app. If a process stalls, provide feedback explaining the problem and what people can do.
- Switch a progress bar from indeterminate to determinate as soon as the duration becomes known.
- Don't switch between the circular (spinner) and bar styles mid-task — the size/shape change disrupts the interface.
- If helpful, display a succinct, accurate description of the task; avoid vague terms like "loading" or "authenticating".
- Display progress indicators in a consistent location across screens and platforms.
- When feasible, let people halt processing — include a Cancel button when interruption has no side effects; add Pause when interrupting loses partial progress (e.g., a partial download).
- When halting loses progress, show an alert offering to confirm the cancellation or resume the process.

### Platform considerations

- tvOS, visionOS: no additional considerations.
- iOS, iPadOS — refresh controls (`UIRefreshControl`): a specialized activity indicator, hidden by default and revealed when people drag the view down.
  - Perform automatic content updates; don't make people responsible for initiating every refresh.
  - Supply a short title only if it adds value (e.g., last update time); never use the title to explain how to refresh.
- macOS: an indeterminate indicator can be a bar or circular spinner. Prefer a spinner for background operations or constrained space (e.g., in a text field or next to a button); avoid labeling a spinner — it appears when people initiate a process, so a label is usually unnecessary.
- watchOS: indicators render in white over the scene background by default; change via tint color.

### Resources

ProgressView (SwiftUI); UIProgressView, UIActivityIndicatorView, UIRefreshControl (UIKit); NSProgressIndicator (AppKit).

## Gauges

A gauge displays a specific numerical value within a range of values. It uses a circular or linear path mapped to the range: the standard style shows an indicator at the current value; the capacity style shows a fill that stops at the value. An **accessory** variant mimics watchOS complications and works well in iOS Lock Screen widgets.

### Best practices

- Write succinct labels describing the current value and both endpoints of the range; VoiceOver reads visible labels even when a style doesn't display them all.
- Consider filling the path with a gradient that communicates purpose (e.g., red-to-blue for hot-to-cold temperatures).

### Platform considerations

- iOS, iPadOS, visionOS, watchOS: no additional considerations. **Not supported in tvOS.**
- macOS: also supports **level indicators** (`NSLevelIndicator`), configurable for capacity, rating, or (rarely) relevance.
  - Capacity style can be continuous (translucent track filled by a solid bar) or discrete (row of equal segments that fill completely — never partially — matching total capacity).
  - Use the continuous style for large ranges; discrete segments become too small to be useful.
  - Change the fill color to signal significant range levels (default is green; tiered state shows a sequence of colors in one indicator).
  - Rating style: see Rating indicators. Relevance style (rare): shaded horizontal bar, e.g., visualizing search-result relevancy.

### Resources

Gauge (SwiftUI); NSLevelIndicator (AppKit). Related: Ratings and reviews.

## Rating indicators

A rating indicator uses a series of horizontally arranged graphical symbols — by default, stars — to communicate a ranking level. It never displays partial symbols (values round to complete symbols), and symbols are evenly spaced; they don't expand or shrink to fit the component's width.

### Best practices

- Make it easy to change rankings — let people adjust an item's rank inline, without navigating to a separate editing screen.
- If you replace the star with a custom symbol, make sure its purpose is clear; people may not associate other symbols with a rating scale.

### Platform considerations

- macOS only. **Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS.**

### Resources

NSLevelIndicator.Style.rating (AppKit). Related: Ratings and reviews.

## Activity rings

Activity rings show an individual's daily progress toward Move, Exercise, and Stand goals. watchOS always shows three rings with the Activity app's colors and meanings; iOS shows a single Move ring (approximation from steps and workout data) or all three rings when an Apple Watch is paired.

### Best practices

- Display Activity rings when relevant to your app's purpose — especially health/fitness apps and apps contributing to HealthKit (e.g., workout metrics screens, post-workout summary screens).
- Use Activity rings only for Move, Exercise, and Stand information; never for other data, and never show Move/Exercise/Stand progress in another ring-like element.
- Show progress for a single person only; make ownership obvious with a label, photo, or avatar.
- Keep the visual appearance identical everywhere:
  - Never change the ring colors (no filters, no opacity changes).
  - Always display on a black background; prefer enclosing rings and background within a circle by adjusting the corner radius (not a circular mask).
  - Keep the black background visible around the outermost ring; if needed add a thin black stroke — no gradient, shadow, or other effect.
  - Scale rings appropriately; design the surrounding interface to blend with the rings, never the reverse.
- For ring-related labels and current/goal values, use the colors that match each ring (HIG specifies Move, Exercise, and Stand colors as RGB values).
- Maintain ring margins: the element needs a minimum outer margin no less than the distance between rings; never let other elements crop, obstruct, or encroach on it.
- Differentiate other ring-like elements from Activity rings with padding, lines, labels, color, or scale.
- Don't send notifications repeating Activity app updates, and don't show a ring element in your notifications; referencing Activity progress is fine if unique to your app.
- Don't use Activity rings for decoration (labels, background graphics) or branding (app icon, marketing materials).

### Platform considerations

- iPadOS, watchOS: no additional considerations. **Not supported in macOS, tvOS, or visionOS.**
- iOS: Activity rings are available via `HKActivityRingView`; appearance adapts automatically — three rings with a paired Apple Watch, Move ring only (approximated activity) without one. Activity history can mix both styles.

### Resources

HKActivityRingView (HealthKit). Related: Workouts; videos "Track workouts with HealthKit on iOS and iPadOS", "Build a workout app for Apple Watch", "Build custom workouts with WorkoutKit".
