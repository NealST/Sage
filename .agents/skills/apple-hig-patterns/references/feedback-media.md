> Source: https://developer.apple.com/design/human-interface-guidelines/feedback
> Source: https://developer.apple.com/design/human-interface-guidelines/loading
> Source: https://developer.apple.com/design/human-interface-guidelines/playing-audio
> Source: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
> Source: https://developer.apple.com/design/human-interface-guidelines/playing-video

## Feedback

Feedback helps people know what's happening, discover what they can do next, understand the results of actions, and avoid mistakes.

### Best practices

- Match the significance of information to how it's delivered: status information can be passive; a warning about possible data loss needs to interrupt.
- Make sure all feedback is accessible — provide color, text, sound, and haptics so people receive it whether they silence the device, look away, or use VoiceOver.
- Consider integrating status feedback into your interface, near the items it describes (e.g., Mail's toolbar shows the latest update and unread count).
- Use alerts to deliver critical — ideally actionable — information; alerts lose impact if overused or trivial.
- Warn people when they initiate unexpected and irreversible data loss; don't warn when data loss is the expected result (e.g., Finder doesn't warn on every file deletion).
- Confirm completion of sufficiently significant actions (e.g., Apple Pay transaction); people expect tasks to succeed, so they only need to know when they don't.
- Show people when a command can't be carried out and explain why (e.g., Maps can't give directions to and from the same location).

### Platform considerations

- watchOS: Avoid displaying indeterminate progress indicators (loading spinners) — they make people feel they must keep watching; instead reassure them they'll get a notification when the process completes.

### Resources

- Animation and haptics — UIKit

## Loading

The best content-loading experience finishes before people become aware of it.

### Best practices

- Show something as soon as possible — placeholders, graphics, or animations while content loads; an empty screen reads as a problem with your app.
- Let people do other things while content loads (e.g., a game loads the next level while players view an in-game menu).
- If loading is unavoidably long, give people something interesting (gameplay hints, tips, feature introductions); gauge remaining time accurately so content isn't too short or repeated.
- Improve installation and launch time by downloading large assets in the background — schedule asset downloads (game level packs, 3D models, textures) right after install, during updates, or at other nondisruptive times (Background Assets framework).
- Show progress clearly: use a determinate progress indicator when you know how long loading will take and an indeterminate one when you don't; for games, consider a custom loading view matching the game's style.

### Platform considerations

- watchOS: Avoid loading indicators — people expect quick interactions; display content immediately. If content needs a second or two, a loading indicator is still better than a blank screen.

### Resources

- Background Assets

## Playing audio

People expect rich audio experiences that automatically adjust when the context changes on the device.

### Best practices

- Respect system behavior: in silent mode, play only audio people explicitly initiate (media, alarms, audio/video messaging); volume settings should affect all sound in your app; reroute automatically when headphones connect, and pause immediately when they disconnect.
- Adjust relative, independent levels automatically when necessary — never the overall system volume.
- Permit rerouting of audio when possible (stereo, car radio, Apple TV) unless there's a compelling reason not to.
- Use the system-provided volume view (slider + output-rerouting control; MPVolumeView).
- Choose an audio category that fits how your app uses sound:

| Category | Meaning | Behavior |
|---|---|---|
| Solo ambient | Sound isn't essential, but silences other audio (e.g., a game soundtrack) | Responds to silence switch; doesn't mix; no background |
| Ambient | Sound isn't essential, doesn't silence other audio (e.g., game that plays music from another app) | Responds to silence switch; mixes; no background |
| Playback | Sound is essential, might mix (e.g., audiobook, language-learning app) | Ignores silence switch; may or may not mix; background playback |
| Record | Sound is recorded (e.g., note-taking app audio mode) | Ignores silence switch; doesn't mix; background recording |
| Play and record | Sound recorded and played, potentially simultaneously (e.g., audio messaging, video calling) | Ignores silence switch; may or may not mix; background record and play |

- Respond to audio controls (Control Center, headphone controls) only when actively playing, in a clear audio context, or connected via Bluetooth/AirPlay; don't halt other apps' audio otherwise.
- Don't repurpose audio controls — they must behave consistently; if your app doesn't support a control, don't respond to it.
- Create custom audio player controls only for commands the system doesn't support (custom skip increments, related content such as scores).
- Let other apps know when your temporary audio finishes so they can resume (notifyOthersOnDeactivation).
- Handling interruptions:
  - Determine how to respond to audio-session interruptions (e.g., tell the system to avoid interrupting for an incoming call unless accepted; a VoIP app must end the call when the iPad Smart Folio closes to avoid unmuting the microphone without people's knowledge).
  - When an interruption ends, decide whether to resume automatically: resumable (incoming call) vs nonresumable (new playlist); a media app should check the type, a game may resume unconditionally (shouldResume).

### Platform considerations

- iOS, iPadOS: Use the system's sound services for short sounds and vibrations (Audio Services).
- macOS: Notification sounds mix with other audio by default.
- tvOS: The system plays audio only when people initiate it; tvOS doesn't play sounds accompanying alerts or notifications.
- visionOS:
  - Prefer playing sound — silence (especially in immersive moments) can feel lifeless; avoid communicating important information with sound only.
  - Design custom sounds for custom UI elements; use Spatial Audio (ambient audio plus object-anchored sources) for an intuitive, engaging experience.
  - Define a range of places sounds can originate (sound follows a moving window).
  - Vary potentially repetitive sounds (randomize pitch/volume during playback rather than creating new files).
  - Decide between wearer-fixed sound (perceived as pointed at the person, e.g., Mindfulness) and object-tracked sound (enhances realism).
  - Now Playing audio pauses when its window closes; non-Now-Playing audio can duck when people look away.
- watchOS: The system manages playback — short clips in the foreground, or longer background audio. Use 64 kbps HE-AAC encoding for media assets. Consider a Now Playing view so people can control current or recent audio without leaving your app.

### Resources

- AVAudioSession / AVAudioSession.Category — AVFAudio; notifyOthersOnDeactivation; shouldResume
- MPVolumeView; Audio Services; Configuring your app for media playback — AVFoundation; MusicKit

## Playing haptics

Playing haptics can engage people's sense of touch and bring their familiarity with the physical world into your app or game.

### Best practices

- Use system-provided haptic patterns according to their documented meanings; if a documented use case doesn't fit, use a generic pattern or create your own where supported.
- Use haptics consistently so people learn to associate patterns with specific experiences (a failure pattern reused for success confuses people).
- Prefer haptics that complement visual and auditory feedback — match intensity and sharpness to the accompanying animation; synchronize sound with haptics.
- Avoid overusing haptics; the best experience is often one people don't consciously notice but miss when off. User-test to find the balance.
- Prefer short haptics complementing discrete events; long-running haptics suit gameplay flows but dilute meaning in apps (and feel unpleasant on Apple Pencil Pro).
- Make haptics optional — let people turn them off or mute them.
- Be aware haptic vibrations can disrupt device features like the camera, gyroscope, or microphone.
- Custom haptics: build patterns from transient events (brief taps/impulses, like the Flashlight button) and continuous events (sustained vibrations, like the lasers message effect); control sharpness (soft/rounded/organic vs crisp/precise/mechanical) and intensity; combine with optional audio (Core Haptics).

### Platform considerations

- iOS: On supported iPhone models, use standard UI components (toggles, sliders, pickers play system haptics) or a feedback generator (UIFeedbackGenerator):
  - Notification — Success (task completed), Warning (produced a warning), Error (error occurred).
  - Impact — physical metaphors: Light, Medium, Heavy (object size/weight), Rigid (hard/inflexible), Soft (soft/flexible).
  - Selection — a UI element's values are changing.
- macOS: With a Magic Trackpad, provide one of three patterns in response to drag or force click (NSHapticFeedbackPerformer): Alignment (dragged item aligns, scales to fit, reaches min/max), Level change (movement between discrete pressure levels, e.g., fast-forward pressure), Generic (general feedback).
- watchOS: Apple Watch Series 4+ provides Digital Crown haptic detents by default. System haptic types (WKHapticType): Notification, Up, Down, Success, Failure, Retry, Start, Stop, Click, Play — each conveys a specific meaning (Notification is the same haptic the system plays for local/remote notifications).
- Game controllers can provide haptic feedback in iPadOS, macOS, tvOS, and visionOS apps; Apple Pencil Pro and some trackpads provide haptics on supported iPad models.

### Resources

- Core Haptics; UIFeedbackGenerator; NSHapticFeedbackPerformer; WKHapticType; Playing Haptics on Game Controllers

## Playing video

People expect to enjoy rich video experiences on their devices, regardless of the app or game they're using.

### Best practices

- Use the system video player for consistent, familiar interactions; if you truly need a custom player, reference the system player's behavior and interface closely.
- Playback modes (system-selected by aspect ratio, people can switch): full-screen (aspect-fill) scales to fill with edge cropping — default for wide video (2:1 through 2.40:1); fit-to-screen (aspect) shows the entire video with letterbox/pillarbox — default for standard (4:3, 16:9, up to 2:1) and ultrawide (above 2.40:1).
- Always display video at its original aspect ratio — embedded letterbox/pillarbox padding makes videos smaller in both modes and display incorrectly in edge-to-edge contexts like iPad PiP.
- Provide additional information (image, title, description) when it adds value without obscuring playback (externalMetadata); visionOS and tvOS players also offer transport controls and content tabs (Info, Episodes, Chapters).
- Support interactions people expect regardless of input device: Space to play/pause on a connected keyboard (Apple Vision Pro, Mac, iPhone, iPad, Apple TV); familiar Siri Remote gestures on Apple TV.
- tvOS: Use a transport control for playback-related actions (favoriting) and custom content tabs for supplementary info or recommendations; keep actions to a step or two and content succinct.
- Avoid letting audio from different sources mix as viewers switch modes — handle secondary audio correctly (silenceSecondaryAudioHintNotification).
- Integrating with the TV app:
  - Ensure a smooth transition: the TV app fades to black and skips your launch screen — present your own black screen before playing or resuming.
  - Show expected content immediately — no splash screens, detail screens, or intro animations; if an interstitial is unavoidable, offer Select (step through) and Play (skip).
  - Never ask people whether to resume playback — resume automatically.
  - Play or pause when people press Space on a connected Bluetooth keyboard.
  - Play content for the correct viewer: switch automatically to the profile the TV app specifies; if unspecified, ask once before playback.
  - Use the previous end time when resuming a long clip.
- Loading content: avoid loading screens when possible; if loading takes more than two seconds, show a black screen with a centered activity spinner and no surrounding content; start playback as soon as enough content loads (continue loading in background); keep loading-screen branding minimal on the black background.
- Exiting playback: show a contextually relevant screen (detail view with a resume option, or a menu listing the content, or your main menu); prepare the exit view as soon as the playback notification arrives, ready for an immediate exit.

### Platform considerations

- tvOS: Defer to content when displaying logos or noninteractive overlays above video — keep them small and unobtrusive; some devices are prone to image retention, so keep overlays short and prefer translucent SDR graphics over bright, opaque content. Implement interactive overlays (quizzes, surveys) with a minimum 0.5 second delay before pausing media, and give people a clear way to dismiss and resume.
- visionOS:
  - Help people stay comfortable: let them choose when to start a video, use a small resizable window, keep surroundings visible.
  - In fully immersive experiences, avoid letting virtual content obscure playback or transport controls (the system places the player at a predictable optimal location).
  - Don't automatically start a fully immersive playback experience.
  - Create a thumbnail track to support scrubbing — supply thumbnails 160 px wide for performance (HLS Trick Play).
  - Don't expand an inline video player to fill a window — inline video is 2D with controls in the same plane; keep window content visible (AVPlayerViewController).
  - Use a RealityKit video player for splash or transitional views — no playback controls or system integration needed; it handles 2D/3D aspect ratios and closed captions, and can play video on a custom surface.
- watchOS: The system manages playback — short clips in the foreground, embedded inline via a movie element or in a separate interface (VideoPlayer). Keep clips short — no longer than 30 seconds (disk space, wrist fatigue). Don't scale video clips. Use recommended encodings:

| Attribute | Value |
|---|---|
| Video codec | H.264 High Profile |
| Video bit rate | 160 kbps at up to 30 fps |
| Resolution (full screen) | 208x260 px (portrait orientation) |
| Resolution (16:9) | 320x180 px (landscape orientation) |
| Audio | 64 kbps HE-AAC |

  - Poster images: don't make them look like system controls; make them represent the clip's contents (tapping replaces the image with inline playback).

### Resources

- AVKit; AVPlayerViewController; Configuring your app for media playback — AVFoundation
- HTTP Live Streaming (HLS Trick Play); RealityKit; VideoPlayer; silenceSecondaryAudioHintNotification
