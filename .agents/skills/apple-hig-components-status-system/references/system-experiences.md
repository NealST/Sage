> Source: https://developer.apple.com/design/human-interface-guidelines/app-shortcuts
> Source: https://developer.apple.com/design/human-interface-guidelines/controls
> Source: https://developer.apple.com/design/human-interface-guidelines/status-bars
> Source: https://developer.apple.com/design/human-interface-guidelines/top-shelf

## App Shortcuts

An App Shortcut gives people access to your app's key functions or content throughout the system. People initiate them with Siri, Spotlight, or the Shortcuts app; the Action button on iPhone or Apple Watch; or by squeezing Apple Pencil.

App Shortcuts use App Intents, are available immediately when installation finishes (before first launch), and can reflect people's choices. Each App Shortcut includes one or more actions; each app can include up to 10 App Shortcuts. People can also combine your app's actions into their own custom shortcuts in the Shortcuts app.

### Best practices

- For common app functionality, consider adopting app schemas instead — apps in common domain areas can expose actions and content to Apple Intelligence, letting Siri surface features contextually without individual App Shortcuts.
- Use App Shortcuts for unique features or custom content not covered by app schemas.
- Offer App Shortcuts for your app's most common and important tasks — straightforward tasks people complete without leaving their current context work best; opening the app is acceptable when it eases multistep tasks.
- Add flexibility with a single optional parameter using predictable, familiar values (people won't have the list in front of them), e.g., "Start [morning, daily, sleep] meditation".
- Ask for clarification when optional information is missing — suggest the most recently used or contextually likely option as the default plus a short list of alternatives.
- Keep voice interactions simple: if a phrase is too complicated to say aloud, it's too hard to remember; ask for additional required information in a subsequent step.
- Make App Shortcuts discoverable in your app with occasional tips when people perform common actions (`SiriTipUIView`).

Responding to App Shortcuts:

- Snippets suit custom views with static information or dialog options (weather, order confirmation); Live Activities suit information that stays relevant and changes over time, like timers and countdowns (`LiveActivityIntent`).
- Provide all critical information in the full dialogue text so audio-only responses (AirPods, HomePod) are complete.

Editorial guidelines:

- Provide brief, memorable activation phrases and natural variants; the app name must be included but can be creative ("Create a Keynote", "Add a new presentation in Keynote" — `AppShortcutPhrase`).
- Use title case for "App Shortcuts" and the "Shortcuts app", always with "Shortcuts" plural.
- Use lowercase for individual shortcuts ("Run a shortcut by asking Siri.").

### Platform considerations

- visionOS, watchOS: no additional considerations. **Not supported in tvOS.**
- iOS, iPadOS: App Shortcuts appear in Spotlight's Top Hit when people search for your app or in the Shortcuts area below; each includes an SF Symbols symbol you choose or a preview image of linked content. Order shortcuts by importance — the order sets initial ordering in Spotlight and the Shortcuts app; the system then prioritizes by frequency of use.
- macOS: App Shortcuts aren't supported; App Intents actions are, so people can build custom shortcuts with them in the Shortcuts app on Mac.

### Resources

App Intents, SiriKit, AppShortcutPhrase, SiriTipUIView, LiveActivityIntent. Related: Siri, Siri Style Guide, Shortcuts User Guide.

## Controls

A control provides quick access to a feature of your app from Control Center, the Lock Screen, or the Action button. Control buttons perform an action, link to an area of your app, or launch a camera experience on a locked device; control toggles switch between two states (e.g., on/off). People add controls by pressing and holding an empty Control Center area, customizing the Lock Screen, or configuring the Action button in Settings.

Anatomy: symbol image (SF Symbols or custom), title, and optional value. Display varies by location: Control Center shows the symbol (plus title and value at larger sizes); the Lock Screen shows the symbol; the Action button shows the symbol and value in the Dynamic Island on press and hold.

### Best practices

- Offer controls for actions with the most benefit without launching your app — e.g., a control that launches a Live Activity keeps people informed without navigation.
- Update controls when someone interacts, when an action completes, or remotely via push notification; reflect state accurately, including in-progress actions.
- Choose a descriptive symbol that suggests the behavior (title and value may not be shown); for toggles, provide symbols for both on and off states (e.g., `door.garage.open` / `door.garage.closed`).
- Use symbol animations to highlight state changes: animate toggle transitions; for buttons with duration-based actions, animate indefinitely while running and stop on completion (`SymbolEffect`).
- Select a tint color that works with your brand — the system applies it to a toggle's on-state symbol and to the value/symbol in the Dynamic Island for Action button use.
- Help people supply configuration the system needs (e.g., choosing a specific light); prompt for it when the control is first added; it can be reconfigured anytime (`promptsForUserConfiguration()`).
- Provide hint text for the Action button, built with verbs (`controlWidgetActionHint(_:)`).
- Include a placeholder for variable titles/values — shown in the controls gallery and before assignment to the Action button so people know what the control does.
- Hide sensitive information when the device is locked: have the system redact the title and value (and optionally the symbol state — the symbol then displays in its off state).
- Require authentication for actions that affect security, such as unlocking a house door or starting a car (`IntentAuthenticationPolicy`).

Camera experiences on a locked device (iOS 18+):

- A control can launch directly into your app's camera experience while the device is locked (`LockedCameraCapture`); anything beyond capture requires authentication.
- Use the same camera UI in your app and your camera experience — the transition after capture (posting, editing) is then seamless.
- Provide instructions for adding the control.

### Platform considerations

- iOS, iPadOS, macOS: no additional considerations. **Not supported in watchOS, tvOS, or visionOS.**

### Resources

WidgetKit, LockedCameraCapture. Related: Widgets, Action button.

## Status bars

A status bar appears along the upper edge of the screen and displays information about the device's current state, like the time, cellular carrier, and battery level.

### Best practices

- Obscure content under the status bar — its background is transparent by default, and controls visible behind it may appear (but fail) to be interactive. Prefer a scroll edge effect that places a blurred view behind the status bar (`UIScrollEdgeEffect`).
- Consider temporarily hiding the status bar for full-screen media (as Photos does) for a more immersive experience.
- Avoid permanently hiding the status bar — people would have to leave your app to check the time or connectivity. Let people redisplay it with a simple, discoverable gesture (a single tap in Photos).

### Platform considerations

- iOS, iPadOS only. **Not supported in macOS, tvOS, visionOS, or watchOS.**

### Resources

UIStatusBarStyle, preferredStatusBarStyle (UIKit).

## Top Shelf

The Apple TV Home Screen provides an area called Top Shelf, which showcases your content in a rich, engaging way while also giving people access to their favorite apps in the Dock. With full-screen Top Shelf support, people can swipe through content views, play trailers and previews, and get more information. The system provides layout templates (downloadable from Apple Design Resources).

### Best practices

- Help people jump right into content: the carousel actions and carousel details templates each include a primary playback button and a More Info button that opens your app to content details.
- Feature new content — new releases and episodes, upcoming movies and shows; avoid promoting content people already purchased, rented, or watched.
- Personalize favorites with targeted recommendations, resuming media playback, or jumping back into active gameplay.
- Avoid advertisements and prices; showing purchasable content is fine, but display prices only when people show interest.
- Showcase compelling dynamic content, preferring layered images; static images are a fallback.
- If you don't provide full-screen content, supply at least one static image (shown when your app is in the Dock and focused); tvOS flips and blurs it to fit a width of 1920 px at 16:9. Don't imply interactivity in a static image — it isn't focusable.

| Static fallback image | Size |
|---|---|
| Top Shelf image | 2320x720 pt (2320x720 px @1x, 4640x1440 px @2x) |

### Dynamic layouts

- **Carousel actions** — full-screen video and images with a few unobtrusive controls; ideal for content people already know (user-generated content, franchise content). Provide a succinct title, optionally a brief subtitle (date range for an album, show name for an episode).
- **Carousel details** — extends carousel actions with information such as plot summary, cast list, and metadata. Provide a title identifying the currently playing content near the top of the screen; above it, optionally a succinct phrase or app attribution ("Featured on My App").
- **Sectioned content row** — a single labeled row of focusable content (recently viewed, new, favorites); a label appears when an item comes into focus and small Touch surface movements animate the focused image; can show multiple labels. Load enough images to span the full screen width and include at least one label.
- **Scrolling inset banner** — large images spanning nearly the full screen width, auto-scrolled on a timer until one is focused (then circling back after the last); focus effect applies lighting and a 3D effect for layered images; swiping pans between banners. Provide three to eight images (fewer feels ineffective; more is hard to navigate). This layout shows no labels under content — bake text into the image (on a dedicated layer above others in layered images) and add it to the accessibility label so VoiceOver reads it.

Sectioned content row image sizes:

| Aspect | Actual size | Focused/safe zone | Unfocused size |
|---|---|---|---|
| Poster (2:3) | 404x608 pt (808x1216 px @2x) | 380x570 pt (760x1140 px @2x) | 333x570 pt (666x1140 px @2x) |
| Square (1:1) | 608x608 pt (1216x1216 px @2x) | 570x570 pt (1140x1140 px @2x) | 500x500 pt (1000x1000 px @2x) |
| 16:9 | 908x512 pt (1816x1024 px @2x) | 852x479 pt (1704x958 px @2x) | 782x440 pt (1564x880 px @2x) |

Mixed image sizes in a row automatically scale up to the height of the tallest image (e.g., a 16:9 image scales to 500 px high next to a poster or square image).

Scrolling inset banner image size:

| Actual size | Focused/safe zone | Unfocused size |
|---|---|---|
| 1940x692 pt (3880x1384 px @2x) | 1740x620 pt (3480x1240 px @2x) | 1740x560 pt (3480x1120 px @2x) |

### Platform considerations

- tvOS only. **Not supported in iOS, iPadOS, macOS, visionOS, or watchOS.**

### Resources

Apple Design Resources (layout templates). Video: "Mastering the Living Room With tvOS".
