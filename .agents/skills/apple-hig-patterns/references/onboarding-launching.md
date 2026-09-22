> Source: https://developer.apple.com/design/human-interface-guidelines/launching
> Source: https://developer.apple.com/design/human-interface-guidelines/onboarding
> Source: https://developer.apple.com/design/human-interface-guidelines/offering-help
> Source: https://developer.apple.com/design/human-interface-guidelines/going-full-screen
> Source: https://developer.apple.com/design/human-interface-guidelines/live-viewing-apps

## Launching

A streamlined launch experience helps people start using your app or game immediately.

### Best practices

- Launch instantly — people don't want to wait more than a couple of seconds.
- If the platform requires it, provide a launch screen: iOS, iPadOS, and tvOS display it at start and quickly replace it with your first screen. macOS, visionOS, and watchOS don't require launch screens.
- If you need a splash screen, display it at the beginning of your onboarding flow — or as soon as launching completes if you have no onboarding. Keep it a beautiful graphic that communicates branding succinctly.
- Restore the previous state when your app restarts; never make people retrace steps. Restore granular details: scroll to the most recent position, display windows in the state and location people left them.
- Launch screens: downplay the launch experience — it's not onboarding, a splash screen, or artistic expression; its sole function is the perception of speed and readiness.
- Design a launch screen nearly identical to your first screen; mismatches cause an unpleasant flash. If the first screen is a solid color, the launch screen shows only that color. Match the device's current orientation and appearance mode.
- Avoid text on the launch screen — content there doesn't change, so it won't be localized.
- Don't advertise: no splash-screen-like designs, no "About" windows, no logos or branding unless fixed parts of the first screen.

### Platform considerations

- Launch screens: not applicable for macOS, visionOS, or watchOS.
- iOS, iPadOS: Launch in the device's current orientation; if the interface runs in only one orientation, launch in that orientation. Ensure landscape-only interfaces respond correctly whether the device rotates left or right.
- tvOS: The launch screen is static, unlike the layered images elsewhere in a tvOS app. In a live-viewing app, consider automatically starting playback of new or recently viewed live content after a few seconds of inactivity.
- visionOS: Consider launching in the Shared Space even if your app is fully immersive — a window provides context and load time, and lets people choose when to transition to a Full Space.

### Resources

- Specifying your app's launch screen — Xcode
- Responding to the launch of your app — UIKit

## Onboarding

Onboarding can help people get a quick start using your app or game.

### Best practices

- Design onboarding that's fast, fun, and optional; it occurs after launching completes, not as part of the launch experience.
- Teach through interactivity — people retain more when they perform tasks (test an action, discover a feature, try a game mechanic) than when viewing instructional material.
- Consider context-specific tips instead of a single onboarding flow; display instructions near the interface area they describe (see TipKit).
- If a prerequisite onboarding flow is needed, keep it brief and enjoyable; teaching too much overwhelms people and reduces retention.
- If you offer a separate tutorial, make it optional; don't re-present it on subsequent launches, but keep it easy to find later (help, account, or settings area).
- Keep onboarding content focused on your experience — not on how to use the system or device.
- Briefly display a splash screen only if necessary, just long enough to absorb at a glance.
- Don't let large downloads hinder onboarding — include enough content in your package for people to start interacting immediately.
- Avoid displaying licensing details in onboarding; let the App Store show agreements and disclaimers.
- Postpone nonessential setup flows and customization; provide reasonable defaults so most people can start immediately.
- If private data access is required before functioning, integrate the permission request into onboarding (showing why and the benefit); otherwise request at first use of the specific function.
- Prefer letting people experience the app before prompting for ratings or purchases.

### Resources

- TipKit

## Offering help

Although the most effective experiences are approachable and intuitive, you can provide contextual help when necessary.

### Best practices

- Let tasks inform the help type: an inline view for simple one- or two-step tasks; a tutorial for complex multistep goals. Relate help to the precise current action, and make it easy to dismiss or avoid.
- Use relevant, consistent language and images — no Siri Remote tips showing a game controller, no "click" copy on iPhone or "tap" copy on Mac.
- Make all help content inclusive.
- Don't explain how standard components work; describe what the element does in your app. For nonstandard input usage (e.g., holding the Siri Remote rotated 90 degrees), orient people quickly with animation or graphics instead of lengthy description.
- Tips (small, transient views describing a feature; see TipKit):
  - Choose the appropriate tip type: popover to preserve content flow; inline to keep surrounding information visible; annotation-style inline to point at a specific UI element; hint-style when unrelated to specific UI.
  - Use tips only for simple features — more than three actions is too complicated for a tip.
  - Make tips short, actionable, and engaging: one or two sentences, direct action-oriented language; no promotional content or content about a different feature or flow.
  - Define parameter-based or event-based eligibility rules so tips reach only people who benefit; with multiple tips, set a reasonable display frequency (e.g., once every 24 hours).
  - If an image or symbol is associated with the feature, include it in the tip and prefer the filled variant; don't repeat the same image in both the tip and the UI it points to.
  - Use buttons to direct people to settings or additional resources such as a setup flow.

### Platform considerations

- macOS, visionOS: Tooltips (help tags) appear when the pointer holds over an element (Mac, including iPhone/iPad apps) or when a person looks at or points to an element (visionOS). Guidance:
  - Describe only the control people indicate interest in — not nearby controls or the larger task.
  - Explain the action the control initiates; begin with a verb ("Restore default settings").
  - Avoid repeating the control's name in its tooltip.
  - Be brief: limit tooltip content to a maximum of 60 to 75 characters (localization changes length); prefer sentence fragments without articles; if a control needs lots of text, simplify the interface.
  - Use sentence case; omit ending punctuation in complete sentences unless your app's style requires it.
  - Consider context-sensitive tooltips, e.g., different text per control state.
- No additional considerations for iOS, iPadOS, tvOS, or watchOS.

### Resources

- TipKit
- NSHelpManager — AppKit
- help(_:)

## Going full screen

iPhone, iPad, and Mac offer full-screen modes that let people expand a window to fill the screen, hiding system controls and providing a distraction-free environment.

### Best practices

- Support full-screen mode when it makes sense: games, media viewing (videos, photo slideshows), or in-depth tasks that benefit from distraction-free focus.
- Adjust layout in full-screen mode if necessary, but don't programmatically resize the window; keep adjustments subtle to avoid visually jarring transitions.
- Continue providing access to essential features and controls — e.g., media playback controls must stay available or be easy to reveal.
- Except in games, let people reveal the Dock while in full-screen mode on iPadOS and macOS. Games may defer the initial bottom-edge swipe (iPadOS) or hide the Dock entirely (macOS).
- After people switch away, help them resume where they left off; pause games and slideshows automatically so nothing is missed.
- Let people choose when to exit full-screen mode; don't end it automatically when switching away or finishing an activity.
- Temporarily hide toolbars and navigation controls to prioritize content, but let people restore them with a familiar gesture (tap, swipe down, move cursor to top). Keep controls visible when essential. visionOS windows can hide these controls, but people expect different immersive behaviors on Apple Vision Pro.

### Platform considerations

- Not supported in tvOS, visionOS, or watchOS. (Apple TV and Apple Watch apps already fill the screen by default; Apple Vision Pro users expand windows or use the Digital Crown for immersion.)
- iOS, iPadOS: Retain the default Home Screen indicator behavior (auto-hides, reappears on bottom interaction). If unexpected exits result, enable two swipes rather than one to exit (preferredScreenEdgesDeferringSystemGestures).
- macOS:
  - Use the system-provided full-screen experience so windows work in all contexts (e.g., accommodating the camera housing area).
  - In a game, don't change the display mode when players go full screen — people expect control of display mode.
  - Always let people choose when to enter full screen: the window's Enter Full Screen button, View menu item, or Control-Command-F shortcut. Avoid a custom menu of window modes; games may also provide a custom full-screen toggle.

### Resources

- fullScreenCover(item:onDismiss:content:) — SwiftUI
- toggleFullScreen(_:), NSScreen, NSWindow.CollectionBehavior — AppKit
- preferredScreenEdgesDeferringSystemGestures — SwiftUI/UIKit
- hideDock — AppKit
- Managing your game window for Metal in macOS

## Live-viewing apps

A live-viewing app delivers live TV content (sports, news, events) that people expect to start watching immediately. In every screen, draw people's attention to live content and make sure they can distinguish it from video-on-demand (VOD) content at a glance.

### Best practices

- **Feature live content prominently and make it easy to access.** Minimize the interval between starting your app and playing content; when live content is in the first tab, people don't have to tap more than once to start viewing it.
- **Let people tap once — or not at all — to start playback.** For example, display a Watch Now button on top of featured or recently viewed live content; on tap it immediately disappears and playback begins, replacing the app UI with a full-screen, immersive viewing experience.
- **Make sure live content looks live.** Playing live content is the best way to make it feel live, but also mark it — e.g., show other channels in a "Live" collection row and give each item a badge, symbol, or sash identifying it as live.
- **Consider indicating the progress of currently playing live content.** People appreciate knowing where they'll land when they jump into in-progress live content; use a progress bar or other indicator to show how much content remains.
- **Give people additional actions and viewing alternatives.** Playback is always the primary action, but also make it easy to record, restart, download, and perform other supported actions — displayed in the same order throughout the app (e.g., Watch, Start Over, Record, Favorite). If content replays at other times, show this so people can schedule viewing.
- **Consider using a content footer for browsing channels during playback**, so people can browse without leaving the live playback experience. If you use one: give it a subtle treatment (such as darkening) so text stays legible and items stay distinct from content behind it; make the currently playing thumbnail easy to identify (badge it or tint its progress bar); match its categories to your electronic program guide (EPG); design a simple, predictable way to invoke and dismiss it (e.g., swipe up opens it, swipe down dismisses it).
- **Provide instant visual feedback when people change channels.** People need confirmation they've arrived at the channel they want, and feedback gives the streaming content time to load.
- **Match audio to the current context.** When people start playing live content, audio should match even while they browse with content playing in the background; when they navigate away from the live tab, they leave the live-viewing context, so audio needs to stop.

### Electronic program guide (EPG)

- **Prominently display current information and make it easy to return to playback.** The current program, channel, and time need to be easy to spot so people can instantly return to the current channel.
- **Make browsing the EPG effortless.** Help people page, scroll, or jump easily; consider a My Channels or Favorites group for quick access to the most-viewed content.
- **Group content into familiar categories** (Movies, TV Shows, Kids, Sports, Popular) to help people find it; if your app includes a content footer, organize its thumbnails using the same categories as the EPG.
- **Let people browse the EPG without leaving their current content** — e.g., continue playback in picture-in-picture (PiP) mode or in the background.

### Cloud DVR

- **Let people start and stop recording from the info panel** while live-streaming.
- **Let people record a future program in a view that provides details about the content**, with the option to record only that program or all future episodes.
- **Help people adapt the recording experience to their needs** — e.g., record only the current episode, only new episodes, or only games involving specific teams.
- **Allow playback and other content-specific actions within your cloud DVR area** — play or delete content and adjust recording settings.
- **Consider offering a control to manage cloud DVR settings** — e.g., delete already-watched recordings or content older than a set number of days; ideally let people set up automatic storage management that overwrites the oldest or already-viewed content.

### Platform considerations

No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources

- Related guidance: Remotes (apple-hig-inputs skill) and Playing video in [feedback-media.md](./feedback-media.md).
