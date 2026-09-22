> Source: https://developer.apple.com/design/human-interface-guidelines/modality
> Source: https://developer.apple.com/design/human-interface-guidelines/multitasking

## Modality

Modality is a design technique that presents content in a separate, dedicated mode that prevents interaction with the parent view and requires an explicit action to dismiss.

### Best practices

- Use modality only when there's a clear benefit: ensuring people receive critical information, confirming or modifying a recent action, performing a distinct narrowly scoped task, or providing an immersive/focused experience.
- Keep modal tasks simple, short, and streamlined — complicated modal tasks make people lose track of the context they suspended.
- Avoid creating an "app within an app": don't present a hierarchy of views inside a modal task; if subviews are necessary, provide a single path through the hierarchy and avoid buttons people might mistake for the dismiss button.
- Consider a full-screen modal style for in-depth content or complex tasks (video, photos, camera views, document markup, photo editing). In visionOS, a full-screen modal fills a window in the Shared Space and can become more immersive in a Full Space.
- Always give people an obvious way to dismiss a modal view, following platform conventions: top toolbar button or swipe down on iOS, iPadOS, watchOS; button in the main content view on macOS and tvOS.
- If closing a modal view could lose user-generated content, get confirmation first and offer ways to resolve it (e.g., an action sheet with a save option on iOS).
- Make it easy to identify a modal view's task — provide a title that names the task or text that describes it.
- Let people dismiss a modal view before presenting another one; multiple visible modals create clutter and add cognitive load. An alert can appear above other content (including modals), but never display more than one alert at a time.
- Components vary by platform: all platforms use alerts; iOS/iPadOS/macOS tend to use sheets or popovers for task-scoped options; iPadOS/macOS/visionOS may use a separate window. (Nonmodal full-screen experiences are a separate pattern — see Going full screen.)

### Resources

- Presentation modifiers — SwiftUI; UIModalPresentationStyle — UIKit; Modal Windows and Panels — AppKit

## Multitasking

Multitasking lets people switch quickly from one app to another, performing tasks in each.

### Best practices

- With rare exceptions (some games, visionOS apps running in a Full Space), every app needs to work well with multitasking — people may think something is wrong if it doesn't.
- Always be prepared to save and restore context, because you can't know when people will initiate multitasking.
- Pause activities requiring attention or active participation when people switch away (games, media viewing); when they return, let them continue as if they never left.
- Respond smoothly to audio interruptions: pause audio indefinitely for primary-audio interruptions (music, podcasts, audiobooks); temporarily lower volume or pause for short interruptions (GPS directions), resuming when the interruption ends.
- Finish user-initiated tasks (downloads, video processing) in the background before suspending — people expect them to complete.
- Use notifications sparingly: notify when a suspended time-sensitive task completes so people can switch back; don't notify about routine or secondary task completion (let people check on return).

### Platform considerations

- Not supported in watchOS.
- iOS: People can use FaceTime or watch video in Picture in Picture while using another app; the app switcher displays all open apps; a FaceTime call can continue while people use another app.
- iPadOS:
  - People view and interact with several apps' windows at once; an app can support multiple open windows.
  - Apps run either full-screen (switch windows via the app switcher) or windowed (resizable, arrangeable like macOS; system window controls for tiling, full screen, minimize, close; frontmost window identified by colored controls and drop shadow).
  - Videos and FaceTime can play in a PiP overlay regardless of full-screen or windowed mode.
  - Apps don't control multitasking configurations or receive any indication of the ones people choose — adapt gracefully to different screen sizes.
- macOS: Multitasking is the default experience; multiple windows get drop shadows and visual effects distinguishing window states.
- tvOS: People can play or browse content while playing movies or TV shows in Picture in Picture (where supported).
- visionOS:
  - People run multiple apps in the Shared Space, switching between windows and volumes; only one window is active at a time — the looked-at window becomes active while others turn translucent and recede along the z-axis. Closing a window backgrounds the app without quitting it.
  - When an app is the Now Playing app, closing its window pauses audio (resume in Control Center without reopening).
  - Don't interfere with system multitasking behavior (the feathered mask on windows people look away from) — don't change the appearance of a window's edges.
  - Don't pause a window's video playback when people look away — people expect playback to continue while they view or work in another window.
  - Be prepared for your audio to duck when people look away, unless your app is the Now Playing app.

### Resources

- Responding to the launch of your app — UIKit; Multitasking on iPad, Mac, and Apple Vision Pro — UIKit
