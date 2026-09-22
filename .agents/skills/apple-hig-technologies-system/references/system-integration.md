> Source: https://developer.apple.com/design/human-interface-guidelines/airplay
> Source: https://developer.apple.com/design/human-interface-guidelines/always-on
> Source: https://developer.apple.com/design/human-interface-guidelines/app-clips
> Source: https://developer.apple.com/design/human-interface-guidelines/mac-catalyst
> Source: https://developer.apple.com/design/human-interface-guidelines/nfc

## AirPlay
AirPlay lets people stream media content wirelessly from iOS, iPadOS, macOS, and tvOS devices to Apple TV, HomePod, and TVs and speakers that support AirPlay.

### Best practices
- Prefer the system-provided media player (`AVPlayerViewController`): it supports chapter navigation, subtitles, closed captioning, and AirPlay. Build a custom player only if it can't meet your needs.
- Provide content in the highest possible resolution: include the full range of resolutions in your HLS playlist so AVFoundation can select per device — 720p content that looks great on iPhone looks low quality streamed to a 4K TV.
- Stream only the content people expect; don't stream background loops or short videos that only make sense inside your app (`usesExternalPlaybackWhileExternalScreenIsActive`).
- Support both AirPlay streaming and mirroring for maximum flexibility.
- Support remote control events so people can play, pause, and fast-forward from the lock screen, Siri, or HomePod.
- Don't stop playback when your app backgrounds or the device locks — continue the streamed show, and avoid automatic mirroring people didn't choose.
- Don't interrupt another app's playback unless your app is starting immersive content; play launch-time or auto-play inline videos on the local device only (`ambient`).
- Keep the rest of your app functional during AirPlay; if people navigate away from playback, don't let other in-app videos start and interrupt the stream.
- If you must build a custom player, match the appearance and behavior of system buttons, show distinct visual states (playback started, occurring, unavailable), use only Apple-provided symbols in AirPlay controls, and position the AirPlay icon in the lower-right corner (iOS 16 and iPadOS 16 and later).

Icons and naming:
- Use the black icon on white or light backgrounds, the white icon on black or dark backgrounds, and a custom color only when other technology icons use the same color.
- Position the icon consistently with other technology icons; keep the icon and the name "AirPlay" noninteractive — never in custom buttons or interactive elements.
- Pair the icon with the name AirPlay (below or beside it, same font as your layout); don't use the icon within text or as a replacement for the name.
- Emphasize your app over AirPlay — make AirPlay references less prominent than your app name or identity.
- Capitalize as "AirPlay" (one word, uppercase A and P); all-uppercase is acceptable only in all-uppercase layouts. Always use AirPlay as a noun.
- Use terms like "works with," "use," "supports," and "compatible" — e.g., "[App Name] is compatible with AirPlay," "Compatible with Apple AirPlay." Refer to AirPlay in technical specs or when content is AirPlay-specific.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, or visionOS. Not supported in watchOS.

### Resources
- AVFoundation, AVKit

## Always On
On devices that include the Always On display, the system can continue to display an app's interface when people suspend their interactions with the device.

Always On is low power and privacy preserving: the display dims and motion is minimized. On iPhone 14 Pro and iPhone 14 Pro Max it shows Lock Screen items (widgets, Live Activities) when the device is set face up; on Apple Watch it dims the watch face when the wrist drops. Notifications still appear on both; tapping the display exits Always On.

### Best practices
- Hide sensitive information people wouldn't want casual observers to see, such as bank balances or health data — including personal info visible in notifications.
- Keep other personal information glanceable when it makes sense: workout pace and heart rate on Apple Watch; flight arrival or ride-sharing arrival on iPhone. People who want nothing visible can turn Always On off.
- Keep important content legible and dim nonessential content: increase dimming on secondary text, images, and color fills; remove rich images or large color areas and use dimmed colors instead.
- Maintain a consistent layout: avoid distracting changes when Always On begins or ends — transition interactive components to an unavailable appearance rather than removing them.
- Within Always On, make infrequent, subtle updates (a sports app pauses play-by-play and updates only the score); unnecessary motion is especially distracting on iPhone because the device often lies face up in view.
- Gracefully transition motion to a resting state; don't stop it instantly, which suggests something went wrong.

### Platform considerations
- No additional considerations for iOS or watchOS. Not supported in iPadOS, macOS, tvOS, or visionOS.

### Resources
- Designing your app for the Always On state (watchOS developer documentation)

## App Clips
An App Clip is a lightweight version of your app or game that provides an on-the-go or demo experience that's instantly available, without downloading the full app.

Discovery happens via App Clip Codes (best option — recognizable, fast, secure), NFC tags, QR codes, location-based suggestions in Siri Suggestions, the Maps app, Smart App Banners, App Clip cards in Safari, and links shared in Messages (iOS 17+ apps can also embed links and previews that launch another app's App Clip). Create an App Clip for in-the-moment, finite tasks (renting a bike, ordering ahead, paying at a restaurant table, museum AR commentary) or for demos that let people experience the app or game before buying (a tutorial plus first level, a free workout, creating and saving a document).

### Best practices
- Let people complete the task or demo entirely within the App Clip; never require installing the full app to finish.
- Focus on essential features only; reserve advanced or complex features for the full app.
- Don't use App Clips solely for marketing, and don't display ads in them — they must provide real value.
- Avoid web views; App Clips use native components. If only web components exist, offer a quick link to your website instead.
- Design a linear, focused UI: no tab bars, complex navigation, or settings; minimize screens and entry forms and remove extraneous information.
- On launch, skip unnecessary steps and open the most contextually relevant part of the App Clip.
- Ensure immediate usability: include all required assets, omit splash screens, never make people wait.
- Keep it small — smaller clips launch faster, which matters most with limited bandwidth: reduce unnecessary code, remove unused assets, avoid downloading additional data.
- Make the App Clip shareable: support links to specific points inside it.
- Make payment easy: consider Apple Pay for express checkout and no-typing shipping info.
- Don't require an account before people get value; if an account is truly required, minimize the information requested (e.g., Sign in with Apple), or ask after task completion.

Privacy:
- App Clips can't perform background operations; limit the data you store and handle, store it securely, and never rely on previously stored on-device data — the system may remove the App Clip and its data between launches. Store login information off the device (Sign in with Apple does this).

Promoting the full app:
- App Clips aren't on the Home screen and are removed after inactivity; the system surfaces the App Clip card, a launch-time app banner, and you may show an SKOverlay — let demos complete fully before recommending install.
- Recommend the app at task completion or a natural pause, politely and nonintrusively: no repeated asks, no interruptions, no push notifications to prompt installs; clearly communicate the full app's additional features.

Notifications (permitted for up to 8 hours after launch):
- Request extended notification permission only if functionality spans more than a day (e.g., a car-rental return reminder).
- Keep notifications task-focused (e.g., delivery updates); never purely promotional; use only in response to an explicit user action.

App Clip cards:
- Make the card image clearly communicate the App Clip's features, tasks, or content; prefer photography or graphics over app screenshots.
- Don't put text in the header image — it isn't localizable and is hard to read.
- Card image: 1800x1200 px PNG or JPEG, no transparency.
- Copy: title of no more than 30 characters, subtitle of no more than 56 characters.
- Action button verb: View (media or informational/educational content), Play (games), Open (everything else).

App Clips for businesses (platform providers):
- One App Clip can power several experiences branded per business or location; keep the business's branding front and center and tone down your own.
- Handle multiple businesses or locations: let people switch between recent businesses and verify location on launch.

App Clip Codes:
- Two variants: scan-only (camera icon at center; for physically inaccessible or digital placement — posters, signage behind a counter, digital displays, email, social media) and NFC-integrated (iPhone icon; for physically reachable spots — tabletops, registers, storefront windows, signage, gift cards).
- Include the App Clip logo when space allows; omit it when clear-space requirements can't be met, on disposable paper or plastic items, or on gambling- or drinking-related items. The logo appears only as part of the badge, never on its own.
- Place codes only on flat or cylindrical surfaces; on a cylinder, code width must not exceed one-sixth of the circumference.
- Keep codes flat: avoid deformable materials (paper, plastic, fabric); attach a rigid card if needed; stickers must adhere well to flat surfaces.
- Choose locations that ensure reliable scanning (enough light for scan-only; no wide-angle scanning); keep codes unobstructed — never overlay text, logos, or images, never animate or dim them; display upright — never rotate the code or angle the center glyph.
- Use only generated codes (App Store Connect or the App Clip Code Generator tool); never create or modify a design — no filters, color augmentation, glows, shadows, gradients, or reflections; preserve the aspect ratio and scale all attributes, including stroke widths.
- Pick colors with enough contrast: use default color pairs or custom foreground/background colors (both tools reject combinations that scan poorly and can suggest alternatives).
- Add a simple call to action near codes: "Scan to [describe what people can do]" or "Hold your iPhone near the [object name] to launch an App Clip that [describe]."
- Use title case for "App Clips" and "App Clip Code"; never put Apple trademarks in your app name or images.

Minimum code sizes:
| Type | Minimum size |
|---|---|
| Printed communications | 3/4 inch (1.9 cm) diameter |
| Digital communications | 256x256 px, PNG or SVG file |
| NFC-integrated code | Embedded NFC tag at least 35 mm in diameter (or equivalent); a 35 mm tag requires a printed code of at least 1.37 inches (3.48 cm) in diameter |

- Keep the distance-to-code-size ratio no more than 20:1 (10:1 preferred for reliability): a code scanned from 40 inches (101 cm) away needs to be at least 4 inches (10.16 cm) in diameter.
- When displayed next to a QR code or other scannable item, make the App Clip Code at least that item's size.
- Provide clear space around a code at least equal to the space between the center glyph and the circular code; leave room for reliable scanning of adjacent codes.

Printing:
- Test printed codes before distributing them; use high-quality, non-textured, matte materials — avoid shine, gloss, reflective or holographic overlays, and thin laminates (use matte laminate if needed; UV-resistant materials outdoors).
- Professional printing: flexographic; desktop: inkjet. Receipt printers: print as close to the paper's maximum bounds as possible.
- Rasterize the SVG at 600 ppi or higher and print at a minimum of 300 dpi; level and calibrate the printer to avoid color misalignment, gamma errors, artifacts, or distorted (elliptical) codes.
- Convert the sRGB SVG to CMYK using a relative colorimetric (media-relative) intent with the Generic CMYK ICC profile (or Gracol 2013 profile on CMYKOV printers), allowing a CIELab Delta E of 2.5.
- Grayscale printers: generate grayscale codes only — color codes printed in grayscale scan less reliably.
- NFC-integrated codes: use Type 5 NFC tags.
- For large batches: run small test prints, print on templates showing the encoded invocation URL and SVG filename alongside each code, and maintain careful file management, versioning, and change tracking; verify printer calibration with Apple's test sheets (color pairs and grayscale bars).
- Legal: use codes only as Apple provides them — don't add symbols, seek registration, or use them in company/product names; stop displaying a code when its App Clip is inactive; don't translate Apple trademarks (they stay in English).

### Platform considerations
- No additional considerations for iOS or iPadOS. Not supported in macOS, tvOS, visionOS, or watchOS.

### Resources
- App Clips, App Store Connect, App Clip Code Generator, Apple Pay, Sign in with Apple

## Mac Catalyst
When you use Mac Catalyst to create a Mac version of your iPad app, you give people the opportunity to enjoy the experience in a new environment.

Good candidates are iPad apps that already support drag and drop, keyboard navigation and shortcuts, multitasking (Split View, Slide Over, Picture in Picture), and multiple windows (scenes). An app is a poor fit if it depends on the gyroscope, accelerometer, rear camera, HealthKit, or ARKit, or if its primary function is marking, handwriting, or navigation. Mac Catalyst adds automatic support for pointer interactions, keyboard-based focus and navigation, window management, toolbars, rich text interaction (copy/paste, contextual edit menus), file management, menu bar menus, and settings in the system Settings app; system UI (split view, file browser, activity view, form sheet, contextual actions, color picker) takes on a more Mac-like appearance.

### Best practices
- Start with the default iPad idiom ("Scale Interface to Match iPad"), which keeps layout consistent but scales iPadOS views and text down to 77% (a 17pt iPadOS baseline font renders as 13pt).
- Adopt the Mac idiom once the app feels at home on the Mac: text and artwork render at 100% with more detail, and graphics-intensive apps may gain performance and battery life — but first audit the layout, keep Mac assets in a separate asset catalog, and prefer text styles over fixed font sizes (fixed view/layout sizes cause significant rework).
- Limit appearance customizations to those available in both iPadOS and macOS — not all iPadOS control customizations exist on the Mac.
- Replace tab bars with a split view and sidebar (preferred — consistent across iPad and Mac, streamlined navigation) or a segmented control (only for flat hierarchies); also list top-level items in the macOS View menu so they remain reachable.
- Offer multiple ways to move between pages: Next and Previous buttons in addition to swipe gestures.
- Rework the layout for the wider screen: split single columns into multiple columns, use regular-width and regular-height size classes, reflow content side-by-side on window resize, present inspectors next to content instead of popovers, move controls into the window toolbar (listing their commands in the menu bar), adopt a top-down flow, and relocate buttons from the side and bottom screen edges (an iPad ergonomics concern that doesn't apply on Mac).
- Create a macOS version of your app icon with the lifelike rendering style people expect on macOS.
- Expect the persistent menu bar: pop-up/pull-down button menus and context menus convert automatically; add context menus to more objects (Mac users expect nearly every object to offer one); support shortcuts with `UIKeyCommand` and custom menus with `UIMenuBuilder`/`UICommand`.
- Most iPadOS gestures convert automatically:

| iPadOS gesture | Mouse | Trackpad |
|---|---|---|
| Tap | Left or right click | Click |
| Touch and hold | Click and hold | Click and hold |
| Pan | Left click and drag | Click and drag |
| Pinch | — | Pinch |
| Rotate | — | Rotate |

- For pinch and rotate, the system sends both touches to the view under the pointer, not the views under each touch.

### Platform considerations
- No additional considerations for iPadOS or macOS. Not supported in iOS, tvOS, visionOS, or watchOS.

### Resources
- Mac Catalyst (UIKit), Designing for macOS

## NFC
Near-field communication (NFC) allows devices within a few centimeters of each other to exchange information wirelessly — for example, iOS apps can scan tags on real-world objects to connect a toy with a game, offer coupons from an in-store sign, or track inventory.

### Best practices
- In-app tag reading supports single- or multiple-object scanning while the app is active; display the system scanning sheet whenever people are about to scan.
- Don't encourage physical contact — scanning only requires proximity: say "scan" and "hold near," never "tap" or "touch."
- Use approachable, conversational terms; avoid developer vocabulary like "NFC," "Core NFC," "Near-field communication," and "tag."

| Use | Don't use |
|---|---|
| Scan the [object name]. | Scan the NFC tag. |
| Hold your iPhone near the [object name] to learn more about it. | To use NFC scanning, tap your phone to the [object]. |

- Provide succinct instructional text for the scanning sheet: a complete sentence in sentence case with ending punctuation that identifies the object, kept short to avoid truncation; revise for subsequent scans ("Now hold your iPhone near another [object name].").
- Support background tag reading, where the system scans whenever the screen is illuminated and shows a tappable notification; it's unavailable when an NFC scanning sheet is visible, Wallet or Apple Pay is in use, cameras are in use, the device is in Airplane Mode, or the device is locked after a restart.
- Also provide in-app scanning for people whose devices don't support background reading.

### Platform considerations
- No additional considerations for iOS or iPadOS. Not supported in macOS, tvOS, visionOS, or watchOS.

### Resources
- Core NFC
