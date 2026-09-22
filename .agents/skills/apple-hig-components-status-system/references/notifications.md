> Source: https://developer.apple.com/design/human-interface-guidelines/notifications
> Source: https://developer.apple.com/design/human-interface-guidelines/live-activities
> Source: https://developer.apple.com/design/human-interface-guidelines/snippets

## Notifications

A notification gives people timely, high-value information they can understand at a glance. Sending requires the person's consent; people then use Settings to choose styles and delivery times by urgency.

Anatomy: a banner/view on a Lock Screen, Home Screen, Home View, or desktop; a badge on an app icon; an item in Notification Center. Communication notifications (calls, messages) use a distinct interface with prominent contact images/avatars and group names instead of the app icon.

### Best practices

- Provide concise, informative notifications — people want quick, valuable updates.
- Don't send multiple notifications for the same thing, even without a response; flooding Notification Center may cause people to turn off all notifications from your app.
- Don't tell people to perform in-app tasks; use notification actions for simple tasks people can do without opening the app.
- Use an alert — not a notification — to display an error message.
- Handle notifications gracefully when your app is in the foreground: your notifications don't display, so present the information discoverably but not intrusively (increment a badge, insert new data into the current view).
- Avoid sensitive, personal, or confidential information — you can't predict where a notification will be seen.

### Content

- The system shows a title at the top; for communication notifications it shows the sender's name; otherwise it shows your app name if you provide no title.
- Create a short title only when it adds context (headline, event name, email subject); with only a generic title like "New Document", let the system show your app name. Use title-style capitalization and no ending punctuation.
- Write succinct, easy-to-read body content: complete sentences, sentence case, proper punctuation; don't truncate manually — the system does it when needed.
- Provide generically descriptive text for hidden previews (people can hide previews in Settings): e.g., "Friend request," "New comment," "Reminder," "Shipment" (`hiddenPreviewsBodyPlaceholder`); sentence-style capitalization.
- Don't include your app name or icon — the system displays your app icon at the leading edge (communication notifications show the sender's contact image badged with a small app icon).
- Consider a sound (`UNNotificationSound`): custom sounds should be short, distinctive, professionally produced; never rely on sound alone for important information; vibration can't be provided programmatically.

### Notification actions

A notification's detail view can contain up to four buttons for actions without opening your app.

- Provide beneficial, context-appropriate actions for common, time-saving tasks.
- Use short title-case labels that describe the result; no app name or extraneous text; keep text brief to avoid truncation; account for localization.
- Avoid actions that merely open your app — tapping the notification already does that.
- Prefer nondestructive actions; for destructive ones give enough context to avoid unintended consequences (the system gives destructive actions a distinct appearance).
- Provide a simple, recognizable interface icon per action (SF Symbols; displayed on the trailing side of the title).

### Badging

A badge is a small filled oval with a number on the app icon indicating unread notifications; it disappears when notifications are addressed and people can disable it in Settings.

- Use a badge only for unread notification counts — never for weather, dates/times, stock prices, game scores, or other numerics.
- Don't make badging the only channel for essential information; surface important information in the app as well.
- Keep badges up to date — update as soon as people open the corresponding notifications; reducing the count to zero removes related notifications from Notification Center.
- Don't create custom images or components that mimic a badge; people who disabled badges will be frustrated by look-alikes.

### Platform considerations

- iOS, iPadOS, macOS, tvOS, visionOS: no additional considerations.
- watchOS: notifications occur in two stages — short look and long look — plus Notification Center; on supported devices people can double-tap to respond.
  - Short looks appear on wrist raise and vanish on lower. Don't use a short look as the only channel for critical information; keep titles discreet (no sensitive information).
  - Long looks show more detail (scroll with swipe or Digital Crown; dismiss by tapping or lowering the wrist). Static interfaces show message plus static text/images; dynamic interfaces access full content and more appearance options. You can customize the content area but not the overall structure (system sash at top, Dismiss button below all custom buttons). Provide at minimum a static interface (the system falls back to it when dynamic content is unavailable — package static resources with your app); prefer providing a dynamic one too. Consider rich custom long looks (SwiftUI animations, or SpriteKit/SceneKit) so people get information without launching the app.
  - Sash: choose a background color or blurred appearance (blurred works well over a photo). Content area: transparent by default; use white at 18% opacity to match system notifications, or a custom color.
  - Provide up to four custom actions below the content area; the system always adds the Dismiss button at the bottom; with an iPhone companion app, the system reuses its registered actionable notification types.
  - Double tap: the system runs the first nondestructive action — order actions with the most frequently used first (e.g., parking extension options 5 minutes, 15 minutes, 1 hour, most common first).

### Resources

UNUserNotificationCenter (Asking permission to use notifications; User Notifications; User Notifications UI); UNNotificationSound. Related: Managing notifications, Alerts.

## Live Activities

A Live Activity lets people track the progress of an activity, event, or task at a glance — frequent content and status updates over a few hours, with interaction, in glanceable locations across devices.

| Platform / system experience | Location |
|---|---|
| iPhone and iPad | Lock Screen, Home Screen, Dynamic Island, StandBy (iPhone) |
| Mac | The menu bar |
| Apple Watch | Smart Stack |
| CarPlay | CarPlay Dashboard |

A Live Activity must support four presentations: **compact** (Dynamic Island, single Live Activity; leading and trailing elements flanking the TrueDepth camera), **minimal** (two Live Activities in the Dynamic Island; one attached, one detached, circular or oval), **expanded** (touch and hold), and **Lock Screen** (banner at the bottom of the Lock Screen; also the alert banner on devices without Dynamic Island). On iPhone in StandBy it appears minimal; tapping transitions to the Lock Screen presentation scaled 2x (custom background colors extend to the full screen).

### Best practices

- Offer Live Activities for tasks and events with a defined beginning and end; best for short-to-medium durations not exceeding eight hours.
- Focus on important glanceable information; people tap for more detail in your app.
- Don't display ads or promotions.
- Avoid sensitive information (Lock Screen and Always-On displays are visible to others); show an innocuous summary, let people tap for details, or redact sensitive views.
- Match your app's visual identity in both dark and light appearances.
- If you include a logo mark, display it without a container; never use the entire app icon.
- Don't add app elements that draw attention to the Dynamic Island.
- Ensure text is easy to read: large, medium weight or heavier; use small text sparingly.

Layout:

- Adapt layouts and assets to different screen sizes, presentations, and scale factors (use the Specifications values below).
- Use only the space needed; adjust element size and placement to fit well together.
- Use familiar layouts — Apple Design Resources templates with default system margins and recommended text sizes (e.g., Smart Stack on Apple Watch).
- Use consistent margins and concentric placement; match inner corner radii to the outer one by subtracting the margin (`ContainerRelativeShape`); keep content snug within a margin concentric to the outer edge.
- When separating content blocks, use an inset container shape or a thick line; don't draw content to the edge of the Dynamic Island.
- Dynamically change height on the Lock Screen/expanded presentation — compact while locating a driver, taller once pickup time and driver details exist.

Colors:

- Custom background color is available only for the Lock Screen presentation (not compact/minimal/expanded); ensure contrast, especially for tint colors on Always-On displays with reduced luminance.
- The Dynamic Island uses a black opaque background — use bold colors for text and objects to convey identity and aid glanceability.
- Tint the key line color (the outline around the Dynamic Island in Dark Mode) to match your content.

Transitions and animations:

- System and custom animations have a maximum duration of two seconds; no animations play on Always-On displays with reduced luminance.
- Use animations to reinforce information and draw attention to updates; use the default content-replace transition or custom transitions (scale, opacity, movement) — e.g., numeric transitions for score changes, fades for timers.
- Animate layout changes by moving existing elements to new positions rather than removing and re-adding them.
- Avoid overlapping elements: animate out, then back in at the new position; in lists, animate only the moving element and fade the rest.

Interactivity:

- Tapping must open your app at the right location (deep link to related details and actions).
- Focus on simple, direct actions; prefer limiting interactivity to a single element to avoid accidental taps (music playback, workouts, live audio recording).
- Consider buttons/toggles for responding to updates (e.g., contact the driver while a ride is en route).

Starting, updating, ending:

- Start at appropriate, expected times (order placed, ride requested, match begins); make it easy to turn a Live Activity off in your app (e.g., unfollow a team), or people may disable Live Activities entirely in Settings.
- Offer an App Shortcut that starts your Live Activity (e.g., via the Action button).
- Update only when new content is available; keep the display unchanged while content and status are unchanged.
- Alert only for essential updates — alerts light up the screen and play the notification sound; don't over-alert and don't send push notifications for the same updates.
- Prefer a single Live Activity with a dynamic layout rotating through multiple events over separate Live Activities people must jump between.
- End immediately when the task or event ends; the system removes it at once from the Dynamic Island and CarPlay, but it remains up to four hours on the Lock Screen, Mac menu bar, and watchOS Smart Stack — consider a custom dismissal time proportional to duration (15–30 minutes is usually adequate).

Presentations:

- Start with the iPhone design, then refine for StandBy, CarPlay, and Apple Watch.
- Compact: show the most important dynamic information; design leading and trailing elements as one unit (consistent color and typography); keep content narrow, snug against the TrueDepth camera, without padding; don't obscure status bar information; balance similarly sized leading/trailing views (shortened units or less precise data); link both elements to the same screen.
- Minimal: stay recognizable; prefer updated information over a static logo (Timer shows remaining time).
- Expanded: an enlarged version of compact/minimal — maintain relative element placement so expansion is predictable; wrap content tightly around the TrueDepth camera.
- Lock Screen: don't replicate notification layouts; use custom background/tint colors sparingly so the design works on personalized Lock Screens; verify Dark Mode and Always-On contrast (default is light background in light appearance, dark in dark); verify the system-generated dismiss button color (`activitySystemActionForegroundColor(_:)`); use the standard margin of 14 points (tighter is acceptable for graphics and buttons, but avoid crowding).
- StandBy: update the layout for the larger scale; consider the default background color (blends with the bezel and lets the system scale slightly larger); use standard margins and don't extend graphics to the screen edge (content gets cut as the Live Activity extends); verify contrast with the Night Mode red tint.
- CarPlay: the system combines compact leading/trailing elements into one Dashboard layout; interactive elements are deactivated — prefer timely content over buttons and toggles; consider a custom layout with `ActivityFamily.small` for larger text or more information.

### Platform considerations

- iOS, iPadOS: no additional considerations. **Not supported in tvOS or visionOS.**
- macOS: active Live Activities appear in the menu bar of a paired Mac (compact, minimal, expanded); clicking launches iPhone Mirroring.
- watchOS: appears at the top of the Smart Stack (default view combines the compact leading/trailing elements); tapping opens your watchOS app, or a full-screen view with a button to open the app on iPhone. Consider a custom watchOS layout to show more information and add a button or toggle — but that layout also applies to CarPlay where interactivity is deactivated, so avoid buttons/toggles if people will use it while driving. Focus Smart Stack content on progress (e.g., delivery ETA), interactive elements (timer controls), and significant updates (score changes).

### Specifications

All values in points (pt). The Dynamic Island corner radius is 44 pt, matching the TrueDepth camera.

CarPlay sizes: 240x78, 240x100, 170x78. Test in the CarPlay simulator with Smart Display Zoom configurations: Widescreen 1920x720, Portrait 900x1200, Standard 800x480 (pt).

iOS dimensions:

| Screen (portrait) | Compact leading | Compact trailing | Minimal (width range) | Expanded (height range) | Lock Screen (height range) |
|---|---|---|---|---|---|
| 430x932 | 62.33x36.67 | 62.33x36.67 | 36.67–45x36.67 | 408x84–160 | 408x84–160 |
| 393x852 | 52.33x36.67 | 52.33x36.67 | 36.67–45x36.67 | 371x84–160 | 371x84–160 |

Dynamic Island widths:

| Devices | Compact/minimal width | Expanded width |
|---|---|---|
| iPhone 17 Pro Max, iPhone Air, 16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus, 14 Pro Max | 250 | 408 |
| iPhone 17 Pro, iPhone 17, 16 Pro, 16, 15 Pro, 15, 14 Pro | 230 | 371 |

iPadOS dimensions (Lock Screen, height range):

| Screen (portrait) | Lock Screen |
|---|---|
| 1366x1024 | 500x84–160 |
| 1194x834 | 425x84–160 |
| 1012x834 | 425x84–160 |
| 1080x810 | 425x84–160 |
| 1024x768 | 425x84–160 |

macOS: use the iOS dimensions. watchOS (Smart Stack — same as watchOS widgets):

| Apple Watch size | Live Activity size |
|---|---|
| 40mm | 152x69.5 |
| 41mm | 165x72.5 |
| 44mm | 173x76.5 |
| 45mm | 184x80.5 |
| 49mm | 191x81.5 |

### Resources

ActivityKit, SwiftUI, WidgetKit, "Developing a WidgetKit strategy".

## Snippets

When someone performs a task with Siri or an App Shortcut, a snippet shows the result or asks for confirmation. Snippets are compact views that appear in response to actions in Siri, Spotlight, or the Shortcuts app, attached to an app intent you design.

Two types: a **confirmation snippet** lets people confirm or cancel an action (optionally with options that affect the result); a **result snippet** provides information requiring no further action. An app intent that displays a snippet always shows a result; the confirmation step is optional.

Anatomy: dialogue (the app intent dialogue Siri speaks; included by default above the custom view), custom view (visually communicates the information; may include buttons), and system-provided buttons (confirmation: secondary Cancel plus a primary button with customizable label; result: a single Done button).

### Best practices

- Ensure legibility: sufficient contrast against the system background in light and dark appearances; consistent margins.
- Keep content concise — snippets are for lightweight, quick interactions. Create custom views no taller than the 400-point maximum height; remember fonts draw at various sizes per text-size preference. For more detail, deep-link into your app instead of enlarging the snippet.
- Choose a descriptive label for a confirmation snippet's primary button ("Order", not "OK" or "Proceed"); if unspecified, the default is "Continue".
- Communicate purpose visually — don't rely on the dialogue text; prefer omitting the spoken dialogue from the snippet's visual representation and let the custom view convey the information.

### Platform considerations

- iOS, iPadOS, macOS: no additional considerations. **Not supported in tvOS, visionOS, or watchOS.**

### Resources

App Intents ("Displaying static and interactive snippets"). Related: Siri, App Shortcuts, Live Activities.
