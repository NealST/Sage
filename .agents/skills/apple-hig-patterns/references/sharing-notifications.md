> Source: https://developer.apple.com/design/human-interface-guidelines/collaboration-and-sharing
> Source: https://developer.apple.com/design/human-interface-guidelines/managing-notifications
> Source: https://developer.apple.com/design/human-interface-guidelines/searching
> Source: https://developer.apple.com/design/human-interface-guidelines/charting-data
> Source: https://developer.apple.com/design/human-interface-guidelines/workouts

## Collaboration and sharing

Great collaboration and sharing experiences are simple and responsive, letting people engage with the content while communicating effectively with others.

### Best practices

- Use the system interfaces and Messages integration: people can share or start collaborating by dropping a document into a Messages conversation or choosing a destination in the share sheet; works with CloudKit, iCloud Drive, or a custom solution (custom infrastructures must also support universal links). SharePlay enables real-time shared activities.
- Place the Share button in a convenient location like a toolbar; in SwiftUI, present a share link (ShareLink) that opens the system share sheet. iOS 16+/iPadOS 16+/macOS 13+ share interfaces include file-sharing method and collaboration permission choices.
- If necessary, customize the share sheet or sharing popover to offer your file-sharing types, including "send copy" (CloudKit: pass the file and collaboration object; iCloud Drive: supported by default; custom: include the file or a plain-text representation).
- Write succinct permission summary phrases, e.g., "Only invited people can edit" or "Everyone can make changes" — the system uses the summary in a button that reveals sharing options.
- Provide a minimal set of simple sharing options (who can access, edit vs read-only, whether collaborators can add participants), grouped for at-a-glance understanding.
- Prominently display the Collaboration button as soon as collaboration starts (next to the Share button) — it reminds people the content is shared and identifies who's sharing.
- Provide custom actions in the collaboration popover only if needed (the popover has three sections: collaborators + communication buttons, your custom items, manage-shared-file button); offer only essential items.
- Customize the collaboration-management button's title if it makes sense (default "Manage Shared File"). CloudKit sharing provides the management view; otherwise you build your own.
- Consider posting collaboration event notifications in Messages — content changes, membership changes, participant mentions — with a universal link to the relevant view (SWHighlightEvent).

### Platform considerations

- Not available in tvOS.
- visionOS: The system streams the current window to collaborators by default when sharing from the Shared Space; transitioning to a Full Space pauses the stream for others until the app returns.
- watchOS: In SwiftUI apps, use ShareLink to present the system-provided share sheet.

### Resources

- Shared with You; ShareLink — SwiftUI; SWHighlightEvent; Supporting universal links in your app

## Managing notifications

Notifications can give people timely and important information, whether the device is locked or in use.

### Best practices

- Get permission before sending any notification; people can change the decision in settings and silence all notifications (except government alerts in some locales).
- Support Focus and scheduled delivery: people reserve time for activities (sleeping, working, reading, driving), choose contacts and apps that can break through, and opt into Time Sensitive alerts. A Focus may delay an alert, but the notification itself is available as soon as it arrives.
- Use communication notifications (SiriKit intents; INSendMessageIntent, UNNotificationContentProviding) for direct communications like calls and messages — people can use Siri to customize behaviors. For all other tasks, use noncommunication notifications and specify a system-defined interruption level:

| Level | Meaning | Overrides scheduled delivery | Breaks through Focus | Overrides Ring/Silent (iPhone/iPad) |
|---|---|---|---|---|
| Passive | Information viewed at leisure (restaurant recommendation) | No | No | No |
| Active (default) | Information people appreciate when it arrives (sports score) | No | No | No |
| Time Sensitive | Directly impacts the person, requires immediate attention (account security, package delivery) | Yes | Yes | No |
| Critical | Urgent health/safety information demanding immediate attention; extremely rare (government, health, home apps) | Yes | Yes | Yes |

- Sending a Critical notification requires an entitlement.
- Build trust by accurately representing the urgency of each notification — people can turn off all notifications if a high urgency level interrupts them with low-priority information.
- Use Time Sensitive only for notifications relevant in the moment (happening now or within an hour); the system explains such notifications on first arrival and periodically gives people opportunities to turn them off (UNNotificationInterruptionLevel).
- Marketing notifications:
  - Don't send marketing or promotional content unless people explicitly agree; people can grant permission for offers related to features, content, or events.
  - Never use the Time Sensitive interruption level for marketing — it must never break through Focus or scheduled delivery.
  - Get explicit permission before sending: an alert or modal describing the information types with a clear opt in/out.
  - Provide an in-app settings screen where people can manage their notification choices.

### Platform considerations

- watchOS: iPhone notification settings apply to the same apps on Apple Watch by default; people manage them in the Apple Watch app or via per-notification options (swipe left: Mute 1 Hour, Turn off Time Sensitive).

### Resources

- User Notifications; UNNotificationInterruptionLevel; INSendMessageIntent; UNNotificationContentProviding

## Searching

People use various search techniques to find content on their device, within an app, and within a document or file.

### Best practices

- If search is important, give it a primary position — a search field in the bottom toolbar (Notes) or a dedicated tab in tab-bar apps (Photos, Apple TV).
- Aim to make all app content searchable from a single, clearly identified location; for apps with distinct sections, a local search can act as a filter on the current view (Music).
- Clearly display the current search scope using descriptive placeholder text, a scope bar, or a title (Mail always references the mailbox being searched); consider helping people scope searches by attributes (creation date, file size, file type) via scope bars and tokens.
- Provide suggestions — recent searches before typing, predictive search suggestions while typing (searchSuggestions(_:)) — to help people search faster and type less.
- Take privacy into account before displaying search history; if shown, provide a way to clear it.
- Systemwide search (Spotlight, iOS/iPadOS/macOS):
  - Make your content searchable in Spotlight by making it indexable with descriptive metadata; people can then find it without opening your app first.
  - Define metadata for custom file types you handle via a Spotlight File Importer plug-in (CSImportExtension).
  - Use Spotlight to offer advanced file-search capabilities within your app (e.g., a button that initiates a Spotlight search on the current selection, displaying results in a custom view).
  - Prefer system-provided open and save views, which include a built-in field to search and filter the entire system.
  - Implement a Quick Look generator if your app produces custom file types, so Spotlight and other apps can show previews.

### Resources

- Adding your app's content to Spotlight indexes — Core Spotlight; CSImportExtension; Quick Look; searchSuggestions(_:)

## Charting data

Presenting data in a chart can help you communicate information with clarity and appeal.

### Best practices

- Use charts to support data-driven tasks: analyzing trends (historical or predicted values), visualizing the current state of a process or changing quantity, and comparing items across categories.
- Not every dataset needs a chart — if you just need to provide data, offer a scrollable, searchable, sortable list or table instead.
- Use a chart when you want to highlight important information about a dataset; charts are visually prominent and draw attention.
- Keep a chart simple, letting people choose when they want additional details — too much data is overwhelming; let people reveal detail gradually (levels of detail, subsets, progressively functional versions).
- Make every chart accessible: provide accessibility labels describing chart values and components, and accessibility elements that help people interact with the chart.
- Designing effective charts:
  - Prefer common chart types (bar, line) people already know how to read.
  - If presenting data in a novel way, help people learn to interpret it (Activity animates each ring to show its metric).
  - Examine data from multiple levels — macro (totals, averages), mid-level (useful subsets), individual points (specific values) — and display perspectives that encourage engagement.
  - Add descriptive text (titles, subtitles, annotations, headlines/summaries) to aid comprehension and highlight actionable takeaways — e.g., Weather's "Chance of light rain in the next hour". A headline doesn't replace accessibility labels.
  - Match chart size to its functionality, topic, and level of detail — large enough for details and interactivity; small charts work for glanceable info or previews of larger versions.
  - Prefer consistency across multiple charts serving a similar purpose; use different types/styles only to highlight meaningful differences.
  - Maintain continuity among charts using the same dataset — one chart type and consistent colors, annotations, layouts, and descriptive text (Health Trends small charts and expanded views share a style).

### Resources

- Swift Charts; Charts (HIG components)

## Workouts

A great workout or fitness experience encourages people to engage with their current activity and helps them track their progress on their devices.

### Best practices

- Leverage device activity data and familiar components for Apple Watch, iPhone, or iPad workout experiences; people wear Apple Watch during workouts and may carry iPhone/iPad, while larger or stationary devices (iPad Pro, Mac, Apple TV) suit live or recorded workout sessions.
- In a watchOS fitness app, use workout sessions to provide useful data and controls: people most likely care about elapsed or remaining time, calories burned, or distance traveled, plus controls like lap or interval markers. watchOS keeps displaying the app between wrist raises.
- Avoid distracting people with irrelevant information during a workout — no browsing workout lists or other parts of the app. Typical watchOS arrangement: large session controls (End, Resume, New) on the leftmost screen; metrics on a dedicated glanceable screen; media playback controls on the rightmost screen.
- Use a distinct visual appearance to indicate an active workout — real-time updating metric values and a unique layout make sessions recognizable at a glance.
- Provide workout controls that are easy to find and tap; give clear feedback when a session starts or stops.
- If sensor data is unavailable during a workout (e.g., water blocking heart rate), help people understand what's still recorded — use language similar to the system Workout app's explanations (e.g., GPS not used during Pool Swim; calories still tracked via the accelerometer).
- Provide a summary at the end of a session; consider including Activity rings so people can check current progress.
- Discard extremely brief sessions — either automatically discard data or ask people whether to record it.
- Make text legible in motion: large font sizes, high-contrast colors, most important information easiest to read.
- Use Activity rings only for their documented purpose — the rings' colors and meanings match the Activity app.

### Platform considerations

- Not supported in macOS, tvOS, or visionOS. No additional considerations for iOS, iPadOS, or watchOS.

### Resources

- WorkoutKit; Workouts and activity rings — HealthKit
