> Source: https://developer.apple.com/design/human-interface-guidelines/live-photos
> Source: https://developer.apple.com/design/human-interface-guidelines/photo-editing
> Source: https://developer.apple.com/design/human-interface-guidelines/imessage-apps-and-stickers
> Source: https://developer.apple.com/design/human-interface-guidelines/voiceover
> Source: https://developer.apple.com/design/human-interface-guidelines/icloud

## Live Photos
Live Photos lets people capture favorite memories in a sound- and motion-rich interactive experience that adds vitality to traditional still photos.

When Live Photos is available, the Camera app captures audio and extra frames before and after the shot; people press a Live Photo to see it spring to life.

### Best practices
- Apply effects and adjustments to all frames; if your app can't, give people the option of converting the photo to a still.
- Keep Live Photo content intact — don't disassemble it and present frames or audio separately; people should experience it with the same visual treatment and interaction model across all apps.
- In sharing flows, let people preview the entire contents before deciding, and always offer sharing as a traditional photo.
- Show a progress indicator while a Live Photo downloads and a clear indication when it's playable.
- In environments that don't support Live Photos, display a traditional still representation; don't attempt to replicate the interactive experience.
- Make Live Photos easily distinguishable from stills — a hint of movement works best; since there are no built-in motion effects, design and implement custom ones.
- When movement isn't possible, show the system-provided badge above the photo, with or without text; never show a playback button a viewer could interpret as video playback.
- Keep badge placement consistent on every photo — a corner typically looks best.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, or tvOS. Not supported in watchOS.
- visionOS: people can view a Live Photo, but they can't capture one.

### Resources
- PHLivePhoto (PhotoKit), LivePhotosKit JS

## Photo editing
Photo-editing extensions let people modify photos and videos within the Photos app by applying filters or making other changes.

Edits always save as new files, safely preserving originals. The extension is reached from a photo in edit mode via the extension icon in the toolbar, and its interface appears in a modal view with a top toolbar; dismissing the view confirms and saves the edit, or cancels it.

### Best practices
- Confirm cancellation of edits: don't immediately discard changes — ask people to confirm and warn that edits will be lost (no confirmation needed when no edits were made).
- Don't provide a custom top toolbar; the modal view already includes one, and a second is confusing and wastes editing space.
- Let people preview edits before closing the extension and returning to the Photos app.
- Use your app icon as the extension icon so people trust the extension comes from your app.

### Platform considerations
- No additional considerations for iOS, iPadOS, or macOS. Not supported in tvOS, visionOS, or watchOS.

### Resources
- App extensions, PhotoKit

## iMessage apps and stickers
An iMessage app can help people share content, collaborate, and even play games with others in a conversation; stickers are images that people can use to decorate a conversation.

iMessage apps and sticker packs live inside Messages conversations (and in effects in Messages and FaceTime) as standalone apps or as extensions of your iOS or iPadOS app.

### Best practices
- Provide one primary experience per iMessage app — content must be easy to understand and immediately available; create separate iMessage apps for additional functionality or content collections.
- Consider surfacing shareable content from your iOS/iPadOS app, like a shopping list or trip itinerary, or support a simple collaborative task such as choosing a restaurant or movie.
- Put essential, frequently used features in the compact view (below the message transcript); reserve additional content for the expanded view.
- Let people edit text only in the expanded view, where the keyboard doesn't hide the app's content (the compact view occupies roughly keyboard space).
- Design stickers that are expressive, inclusive, and versatile: legible against a wide range of backgrounds and when rotated or scaled, with transparency to help them blend with text, photos, and other stickers.
- Provide a localized alternative description for every sticker so VoiceOver can speak it.

### Specifications
Icons (supply square-cornered; the system applies the rounding mask). The icon appears in Messages, notifications, Settings, the App Store, and the Messages app drawer:

| Usage | @2x (pixels) | @3x (pixels) |
|---|---|---|
| Messages, notifications | 148x110, 143x100 | — |
| | 120x90 | 180x135 |
| | 64x48 | 96x72 |
| | 54x40 | 81x60 |
| Settings | 58x58 | 87x87 |
| App Store | 1024x1024 | 1024x1024 |

Stickers — pick one size (small, regular, or large) for the whole pack; don't mix sizes. Prepare images at @3x; the system downscales to @2x and @1x at runtime:

| Sticker size | @3x dimensions (pixels) |
|---|---|
| Small | 300x300 |
| Regular | 408x408 |
| Large | 618x618 |

A sticker file must be 500 KB or smaller. Transparency and animation support by format:

| Format | Transparency | Animation |
|---|---|---|
| PNG | 8-bit | No |
| APNG | 8-bit | Yes |
| GIF | Single-color | Yes |
| JPEG | No | No |

### Platform considerations
- No additional considerations for iOS or iPadOS. Not supported in macOS, tvOS, visionOS, or watchOS.

### Resources
- Messages framework, Adding Sticker packs and iMessage apps to the system Stickers app, Messages camera, and FaceTime

## VoiceOver
VoiceOver is a screen reader that lets people experience your app's interface without needing to see the screen.

Supporting VoiceOver helps people who are blind or have low vision access information and navigate your interface; it works in apps and games built for Apple platforms, including Unity apps using Apple's Unity plug-ins.

### Best practices
Descriptions:
- Provide alternative labels for all key interface elements — more descriptive than the generic labels system controls get by default — and add labels to custom elements; keep them up to date as the interface and content change.
- Describe meaningful images, covering only what the image itself conveys (VoiceOver already reads surrounding context like nearby captions).
- Make charts and other infographics fully accessible: concisely describe what each conveys, and expose interactive drill-downs to VoiceOver through the accessibility APIs.
- Exclude purely decorative images from VoiceOver — it respects people's time and reduces cognitive load.

Navigation:
- Give every page a unique, succinct title and use accurate section headings so people can build a mental model of the information hierarchy.
- Describe relationships that exist only visually (grouping, order, links): VoiceOver reads in the active language's reading order (top-to-bottom, left-to-right in US English), so group related elements — each image with its caption — rather than leaving them ungrouped.
- Announce visible content and layout changes so people's mental map stays accurate.
- Support the VoiceOver rotor (navigation by headings, links, and other content types, plus the braille keyboard) where possible.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, or watchOS.
- visionOS: custom gestures aren't always accessible — with VoiceOver on, apps and games that define custom gestures don't receive hand input by default, so voice exploration isn't disrupted; people can opt out via Direct Gesture mode, which disables standard VoiceOver gestures and lets apps process hand input directly.

### Resources
- Accessibility, VoiceOver, Supporting VoiceOver in your app

## iCloud
iCloud is a service that lets people seamlessly access the content they care about — photos, videos, documents, and more — from any device, without performing explicit synchronization.

Transparency is fundamental: people don't need to know where content resides — they assume they're always accessing the latest version.

### Best practices
- Make your app work with iCloud automatically (people enable it in Settings); if people might want a choice, show a simple all-or-nothing option the first time your app opens.
- Don't ask which documents to keep in iCloud — people expect everything to be available; perform file-management tasks automatically.
- Keep content up to date while respecting device storage and bandwidth: for very large documents, let people control when updates download, indicate when a newer version exists in iCloud, and provide subtle feedback if a download takes more than a few seconds.
- Respect storage space — it's a finite resource people pay for: store information people create and understand, not app resources or regenerable content; remember every app's Documents folder is included in iCloud backups, so be picky about what goes there.
- Behave appropriately when iCloud is unavailable: no alert when someone turns it off or enables Airplane Mode, but quietly let them know changes won't reach other devices until access is restored.
- Keep app state information in iCloud (e.g., the last page viewed) and sync only settings people want on all their devices — some settings matter more at work than at home.
- Warn and ask for confirmation before deleting a document — deletion removes it from iCloud and all other devices.
- Make conflict resolution prompt and easy: detect and resolve version conflicts automatically when possible; otherwise use an unobtrusive notification that makes differentiating and choosing between versions easy, as early as possible.
- Include iCloud content in search results — people expect their content to be universally available.
- Games: consider saving player progress with the GameSave framework (device sync plus built-in alerts for offline play and conflicts) or custom UI built on GameSave data.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources
- CloudKit, GameSave
