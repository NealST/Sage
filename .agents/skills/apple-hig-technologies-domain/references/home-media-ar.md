> Source: https://developer.apple.com/design/human-interface-guidelines/homekit
> Source: https://developer.apple.com/design/human-interface-guidelines/carplay
> Source: https://developer.apple.com/design/human-interface-guidelines/game-center
> Source: https://developer.apple.com/design/human-interface-guidelines/shareplay
> Source: https://developer.apple.com/design/human-interface-guidelines/shazamkit
> Source: https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
> Source: https://developer.apple.com/design/human-interface-guidelines/augmented-reality

# Home, media, social & AR technologies

## HomeKit
HomeKit lets people securely control connected accessories in their homes using Siri or the Home app on iPhone, iPad, Apple Watch, and Mac; your iOS, tvOS, or watchOS app can integrate to provide setup, fine-grained configuration, custom features, automations, and support.

Object model: a home is the root of a hierarchy containing rooms, accessories, and zones (people can have multiple homes); an accessory is a physical device, typed by category; a service is a controllable feature (e.g., the light on a garage-door opener); a characteristic is a controllable attribute of a service (speed, brightness); a service group bundles services controlled as a unit; an action changes a characteristic; a scene groups actions across accessories; an automation reacts to situations (location, time, sensors); a zone groups rooms (e.g., upstairs).

### Best practices
- Use the HomeKit terminology and object model so home automation feels approachable; even if your UI isn't room/zone based, reference the model when helping people set up or control accessories (voice commands depend on location: "Siri, turn on the lights upstairs").
- Make an accessory's related HomeKit details (zone, room) easy to find — not buried in a hard-to-discover settings screen; an accessory detail view works well.
- Recognize that people can have more than one home; show the relevant home in the accessory detail view.
- Don't present duplicate home settings — never ask people to set up their home again or show a duplicate view; defer to Home app settings and present them intuitively.
- Never surface "service" or "characteristic" in UI — use descriptive names like "garage door opener" and "speed"; always use "scene" in UI (the API term is action set).
- Use the system-provided setup flow (fast: naming, network join, pairing, room/category assignment, favorites in a few steps); provide a purpose string explaining why you need access to Home data.
- Don't require an account or personal information for setup — defer to HomeKit; if you offer additional services like cloud, make account setup optional and offer it after initial setup.
- Honor setup choices: don't force people to set up other platforms during the HomeKit flow (it delays use and confuses).
- Offer any custom accessory-setup experience only after basic functionality is available via the system flow, to highlight unique features.
- Suggest service names that suit your accessory; never suggest company names or model numbers as service names.
- Enforce HomeKit naming rules when people rename services (the system flow checks originals): alphanumeric, space, and apostrophe characters only; start and end with an alphabetic or numeric character; no emojis; briefly explain violations and suggest alternatives.
- Help people avoid location information in service names ("kitchen light" causes unpredictable voice results) — remove the room/zone from the name and assign the accessory to that room or zone instead.
- Present example Siri voice commands right after setup (using the chosen service name); teach more complex commands afterward (e.g., in a scene detail view: You can say "Hey Siri, set 'Movie Time.'").
- Siri recognizes names of homes, rooms, zones, services, and scenes, plus accessory categories and characteristics (e.g., "brighter" implies a brightness characteristic); recommend creating zones and service groups when they enable useful context-specific commands.
- Offer shortcuts only for accessory-specific functionality HomeKit doesn't support (e.g., "Order AC filters"), never for scenes or actions HomeKit already handles; if you support both, clearly indicate what shortcuts add so people aren't confused by multiple voice-control methods.
- Be clear about what people can do in your app versus the Home app (e.g., guide creation of a scene containing your accessory's actions, then suggest adding HomeKit-compatible shades/TV in the Home app).
- Defer to the HomeKit database: automatically reflect changes made in the Home app or other apps; if you must manage conflicts, present them visually (e.g., old and new service names side by side).
- Ask permission before writing to the HomeKit database when people make changes in your app; never overwrite HomeKit settings without explicit direction.
- Cameras: never block camera images with other content (supplementary alerts are fine); show a microphone button only if the camera supports bidirectional audio.
- HomeKit icon: use only Apple-provided icons (download from Resources); use the HomeKit icon in setup or instructional communications — black on light backgrounds, white on dark, or a custom color when other technology icons use one; position it consistently with other technology icons.
- Use the HomeKit icon noninteractively — never in custom interactive elements or buttons, never within text or as a replacement for the word; pair it with the name "HomeKit" correctly (below or beside, matching how other technologies are referenced); the Apple Home app icon may reference or open the app's App Store product page.
- Referring to HomeKit: emphasize your app over HomeKit; follow Apple trademark guidelines — no Apple trademarks in your app name or images, singular form only, never possessive, never translated, no category descriptors ("iPad," not "tablet"), no implied sponsorship or endorsement, correct credit lines wherever legal information appears.
- Refer to Apple devices/OSes only in technical specifications or compatibility descriptions.
- Capitalize "HomeKit" (one word, H and K) and "Apple Home" (two words); all-caps only to match an all-caps layout.
- Don't use "HomeKit" as a descriptor — say "[Brand] lightbulbs work with HomeKit," not "HomeKit-enabled thermostat" or "HomeKit lightbulbs."
- Don't suggest HomeKit performs an action ("HomeKit unlocked the back door" — wrong); "Compatible with Apple HomeKit" and "Open HomeKit settings" are fine; for the app, use "Apple Home" on first mention, then "the Home app."

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources
- HomeKit; performAccessorySetup(using:completionHandler:); Apple Design Resources (HomeKit icons); MFi portal (licensees).

## CarPlay
CarPlay lets people get directions, make calls, send and receive messages, listen to music, and more from the car's built-in display, all while staying focused on the road; apps run from the connected iPhone with simplified, driving-optimized interfaces built from system-defined templates (audio, communication, navigation, fueling, and others) — iOS renders content and handles vehicle input, so no layout adjustments per screen or hardware are needed.

### Best practices
- Design for driving: quick task completion with minimal interaction.
- Eliminate app interactions on iPhone when CarPlay is active (interactions happen on the car's controls/display); if setup is required on iPhone, make sure it happens before the vehicle is in motion.
- Never lock people out of CarPlay because the connected iPhone requires input; the app must work when iPhone is inaccessible (in a bag, in the trunk, locked); let people resolve iPhone problems after the vehicle stops.
- Ensure features work while iPhone is locked — most people use CarPlay that way.
- Audio (your app coexists with the car radio and navigation voice prompts): let people choose when playback starts — never auto-start unless your app plays a single audio source or resumes previously interrupted audio; don't start an audio session until ready to play (starting one silences other sources).
- Start playback as soon as audio has sufficiently loaded (the system keeps the selection highlighted with a spinner until your app signals readiness); display the Now Playing screen when audio is ready — don't delay playback for descriptive info, load it in the background.
- Resume playback only after resumable interruptions (a phone call — yes; a Siri-initiated playlist — no); if audio was actively playing when a resumable interruption began, resume when it ends.
- Automatically adjust relative audio levels if needed, but never change overall output volume — people control that.
- Provide useful, high-value information in a clean layout that's easy to scan from the driver's seat; no nonessential details or visual embellishments; keep similar-function elements visually consistent.
- Make primary content stand out and feel actionable — large items read as more important and easier to tap; place the most important content and controls in the upper half of the screen.
- Prefer a limited color palette that coordinates with your app logo; never use the same color for interactive and noninteractive elements.
- Test your color scheme in an actual car under varied lighting (time of day, weather, window tint): consider night brightness and sunlight washout; ensure the app looks great in both light and dark appearances (CarPlay may switch automatically); choose inclusive colors.
- Supply high-resolution @2x and @3x images for all artwork; mirror your iPhone app icon (one design works for both); never use black for the icon background — lighten it or add a border so it doesn't blend into the display.
- Report errors in CarPlay, never on the connected iPhone; never direct people to pick up their iPhone to read or resolve an error.

Common display sizes:

| Dimensions (pixels) | Aspect ratio |
|---|---|
| 800x480 | 5:3 |
| 960x540 | 16:9 |
| 1280x720 | 16:9 |
| 1920x720 | 8:3 |

CarPlay app icon: 120x120 px @2x, 180x180 px @3x.

### Platform considerations
- Not supported in iPadOS, macOS, tvOS, visionOS, or watchOS. No additional considerations for iOS.

### Resources
- CarPlay App Programming Guide.

## Game Center
Game Center is Apple's social gaming network, which lets players track their progress and connect with friends across Apple platforms, and boosts the discovery of your game across players' devices (Games app, App Store, notifications).

Build with GameKit (full-featured UI, or present data in custom UI).

### Best practices
- At launch, determine whether the player is signed in; if not, initialize them with Game Center then — seamless sign-in maximizes discovery (Top Played chart, friend-based social recommendations).
- Access point (Apple-designed element for viewing profile/info without leaving your game; leads to the Game Overlay in iOS/iPadOS/macOS or the in-game dashboard in visionOS/tvOS): display it in menu screens (main menu or settings), never during active gameplay or in splash screens, cinematics, or tutorials that precede the main menu.
- Avoid placing controls near the access point — it can appear at any of the four corners and has collapsed and expanded versions; check for overlap with important UI (in visionOS, its location varies by game type, such as immersive or volume-based).
- Consider pausing your game while the Game Overlay or dashboard is present.
- Custom UI can deep-link into specific areas of the Overlay/dashboard (leaderboards, profile); use the official artwork from Apple Design Resources without adjusting dimensions or visual effects.
- Use correct terminology in custom UI: "Game Center" (not GameKit, GameCenter, game center), "Game Center Profile" (not Profile/Account/Player Info), "Achievements" (not Awards/Trophies/Medals), "Leaderboards" (not Rankings/Scores/Leaders), "Challenges" (not Competitions), "Add Friends" (not Add/Add Profiles); use system-provided translations of "Game Center."
- Achievements: map yours to the four Game Center states (locked, in-progress, hidden, completed) — the system groups them into Completed and Locked groups.
- Determine display order before uploading — achievements appear in upload order (e.g., matching the common path through your game).
- Be succinct: the achievement card limits title and description to two lines each (beyond that, text truncates); title-style capitalization for the title, sentence-style for the description.
- Use progressive achievements so the system shows progress with encouraging messages.
- Design rich, unique, high-quality achievement images (reusing one asset across achievements or supplying none — a placeholder appears — feels unrewarding); the system applies a circular mask, so keep content centered.

| Achievement image attribute | Value |
|---|---|
| Format | PNG, TIF, or JPG |
| Color space | sRGB or P3 |
| Resolution | 72 DPI (minimum) |
| Image size | 512x512 pt (1024x1024 px @2x) |
| Mask diameter | 512 pt (1024 px @2x) |

- Leaderboards: choose classic (all-time best score; e.g., most perfect score, most coins in a run, longest endless-runner time) or recurring (resets on an interval you define; daily puzzles, seasonal events, weekly battle modes).
- Use leaderboard sets to organize multiple boards by theme (difficulty modes, activity types, genres); create a unique image per leaderboard that showcases its gameplay.
- In iOS/iPadOS/macOS supply a single image; in tvOS supply an animated set for focus effects. Mind cropping: the system crops set-member artwork in iOS/iPadOS/macOS, and the tvOS focus effect may crop layer edges — keep primary content visible.

| Leaderboard image attribute | Value |
|---|---|
| Format | JPEG, JPG, or PNG |
| Color space | sRGB or P3 |
| Resolution | 72 DPI (minimum) |
| Image size | 512x512 pt (1024x1024 px @2x) |
| Cropped area | 512x312 pt (1024x624 px @2x) |

- Challenges (built on leaderboards; time-limited competitions with friends): create short, skill-based challenges with a clear way to gauge accomplishment, taking 1–5 minutes (fastest lap, most enemies in a round, fewest mistakes in a daily puzzle).
- Avoid challenges that track overall progress or personal bests — regular players get an unfair advantage; track the most recent score after each attempt instead.
- Make challenges easy to jump into: deep-link to the exact mode or level where the challenge begins and complete initial onboarding (e.g., the tutorial) first, telling players the challenge follows automatically.
- Create high-quality challenge artwork (shown in the Game Overlay, Games app, and invitation previews); keep primary content clear of where the title and description overlay it; localize any text via App Store Connect or Xcode.

| Challenge artwork attribute | Value |
|---|---|
| Format | JPEG, JPG, or PNG |
| Color space | sRGB or P3 |
| Resolution | 72 DPI (minimum) |
| Image size | 1920x1080 pt (3840x2160 px @2x) |
| Cropped area | 1465x767 pt (2930x1534 px @2x) |

- Multiplayer (real-time and turn-based, joined via party codes, the Game Overlay, dashboard, or Games app): use party codes to coordinate real-time sessions — typically eight alphanumeric characters like "2MP4-9CMF" — whether you use Game Center matchmaking/networking or your own.
- With party codes, let players join late, leave early, and return later; provide a way to view the current party code in game; allow manual code entry.
- Support multiplayer through in-game UI (default interface invites nearby/recent players, Game Center friends, and contacts) or your custom UI.
- Provide engaging multiplayer activity artwork — players see the preview image in a party code, the Games app, and in-game UI — using the same specifications as challenge artwork (1920x1080 pt, cropped area 1465x767 pt, JPEG/JPG/PNG, sRGB or P3, 72 DPI minimum).

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, or visionOS.
- tvOS: you can display an optional image at the top of the dashboard — a simple, easily recognizable image that looks great at a distance (your logo or word mark; never your app icon): 600x180 pt (1200x360 px @2x), PNG/TIF/JPG, sRGB or P3, 72 DPI minimum.
- watchOS: GameKit features and API are available, but there's no system-supported Game Center UI to invoke — Game Center content for watchOS games appears on a connected iPhone.

### Resources
- GameKit; Adding an access point to your game; Rewarding players with achievements; Encourage progress and competition with leaderboards; Creating engaging challenges from leaderboards; Creating activities for your game; Apple Design Resources (tvOS template).

## SharePlay
SharePlay lets people experience activities together from anywhere — watching a movie, playing a game, or sketching on a whiteboard — each from their own device, kept in sync by the system alongside FaceTime or Messages.

Activities can start from a control in your app, a FaceTime call, or a shared link; the system asks each participant to open your app (inviting anyone without it to download from the App Store). If the activity involves purchased or subscribed content, each participant needs their own copy or subscription — the system prompts anyone without access.

### Best practices
- Use SharePlay for real-time experiences; for asynchronous collaboration, give people a way to share or save the activity after the session (e.g., edit a Freeform board together live, then share a link).
- Design the experience to fit the activity: a single shared view for watching/browsing, or role-adapted views (each player's own perspective in a game).
- Design activities that work across Apple platforms — different devices, settings, and communication methods.
- Make starting easy: a clear, recognizable control with the SharePlay symbol, the share sheet, or (visionOS) the Share button next to the window bar.
- Let people join without friction: get them to the shared content fast (no unrelated views); guide sign-in/downloads/subscriptions in a view that dismisses when done; offer provisional access to nonsubscribers or support Family Sharing; defer nonessential steps (join the match now, set up profiles later).
- Describe activities clearly and concisely (title, short summary, poster image) so people know what they're joining; keep descriptions short enough to avoid truncation.
- Keep people oriented as the activity changes: the system coordinates media playback (pausing for one pauses for all); for other changes, use in-app cues showing who's doing what (e.g., participants' initials beside their contributions).
- Use the term correctly: SharePlay as a noun ("Join SharePlay") or verb (a "SharePlay Movie" button); never pair it with adjectives (no "virtual"/"spatial" SharePlay) or alter it (no SharePlayed, SharePlays, SharePlaying).

### Platform considerations
- Not supported in watchOS. No additional considerations for tvOS.

**iOS, iPadOS, and macOS**
- Support Picture in Picture for shared video so people can keep watching together while doing other things (on iPhone and iPad, in a PiP window; on Mac, in a window people bring forward).

**visionOS**
- Standard windows are shareable through screen mirroring by default via the Share button; adopt SharePlay to share volumetric windows and immersive content.
- The system creates a shared context so everyone experiences content in the same relative location — align windows and volumes across devices, and position 3D objects, play sounds, and support interactions that strengthen the feeling of being together.
- Prefer starting the experience from a window (easy to find and share via the Share button); an activity starting in an immersive space needs custom UI to start it.
- Resolve conflicts naturally: if only one person can use a tool or object, don't show take-control UI — let people speak or gesture for a turn; consider a simple rule like "last change wins."
- Reserve unique views for moments that call for them (keep views and immersion in sync generally); when someone enters a personal immersive view, replace their spatial Persona with a contact photo and let everyone keep talking over FaceTime Audio.
- Let people opt in to immersion changes mid-task: check whether a change would interrupt someone, and if so, prompt them to join when ready (everyone else transitions immediately).
- Keep per-participant comfort/accessibility adjustments (volume, subtitles) unique to each person.
- Make leaving and rejoining easy: a clear control to rejoin; a windowed version of the activity lets people multitask while staying connected to the activity and FaceTime Audio.
- Personas: remote Apple Vision Pro participants can appear as spatial Personas (eye contact, gestures, movement) or contact photos (if not set up); iPhone/iPad/Mac/Apple TV participants appear in a 2D video window; people on Vision Pro in the same room see each other through passthrough. Support everyone who isn't a spatial Persona — if your experience relies on facial expressions or gestures, offer alternatives.
- Spatial templates (automatic seat arrangements around content): side-by-side places participants along a curve, all facing the content — ideal for viewing together, less nonverbal interaction; surround arranges a circle around the content — ideal for tabletop games and 3D or per-participant content, encouraging verbal and nonverbal interaction; conversational places content at the circle's edge — for people being together while the app performs a background task like playing music.
- Divide a complex activity into stages, each with its own template — mixing system and custom templates beats one complex custom template; let people initiate transitions (unexpected seat swaps are disorienting); keep transitions smooth (avoid frequent or excessive movement; fade out and back in with visual cues for reorientation).
- Custom templates (when no system template fits; seats apply only to spatial Personas, others participate without seats): account for physically present people — a template can seat a remote Persona but not someone in the room, so guide positions with visual markers; control seat orientation (default: toward content center).
- Support the maximum number of seats — Apple Vision Pro supports up to five spatial Personas, so define all five seats up front whenever possible and keep a seat in place after someone leaves (adding/removing seats is disorienting); for participant-limited activities, consider spectator seats.
- Place seats at least a meter apart (closer spatial Personas become contact photos, breaking presence); define the fill order so the arrangement stays balanced when not every seat is occupied (left-to-right can feel unbalanced).
- Keep roles (player, spectator, team member) independent of seats — roles must work for people without seats, and anyone can fill an open seat; reserve a specific spot only for a role that truly requires it (a game host at the head of a table).

### Resources
- Group Activities; Presenting SharePlay activities from your app's UI; Synchronizing data during a SharePlay activity; SpatialTemplateSeatElement; isSpatial / isNearbyWithLocalParticipant; Implementing SharePlay for immersive spaces in visionOS.

## ShazamKit
ShazamKit supports audio recognition by matching an audio sample against the ShazamKit catalog or a custom audio catalog — for example, genre-synced graphics, closed captions or sign language synced to audio, or synchronized in-app and virtual content for online learning and retail.

### Best practices
- If you need the microphone for samples, request access and help people understand why you're asking.
- Stop recording as soon as possible — record only as long as it takes to get the needed sample.
- Let people opt in to storing recognized songs in their iCloud library — even though Music Recognition and the Shazam app show your app as the source, people want control over which apps store content in their library.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources
- ShazamKit.

## Sign in with Apple
Sign in with Apple provides a fast, private way to sign into apps and websites — people use their existing Apple Account, skip forms, email verification, and passwords, and can share a unique, random relay email address that forwards to their personal inbox.

It's available on every platform — including non-Apple platforms — with Face ID, Touch ID, or Optic ID and built-in two-factor authentication; Apple doesn't use it to profile people or their activity.

### Best practices
- Ask people to sign in only in exchange for value — show a brief, approachable description of the benefits (personalization, additional features, data sync).
- Delay sign-in as long as possible; forced sign-in before anything useful causes abandonment (let people explore first).
- If you require an account, have people set it up before offering sign-in options — explain why, then let them choose among Sign in with Apple and other methods.
- Consider account linking (before or after signing in): suggest linking when a Sign in with Apple email matches an existing account, or surface a linking suggestion in the account's settings view.
- In commerce apps, wait until after purchase to ask for an account: with guest checkout, offer quick account creation on the confirmation page (with Apple Pay, reuse the name and email from the transaction).
- Welcome people to their new account immediately when Sign in with Apple completes — don't stall the experience asking for unrequired information.
- Indicate the current sign-in method (e.g., "Using Sign in with Apple" in settings or account views).
- Minimize data requests: clarify whether additional data is required (terms agreement, region, birth date, real-identity laws) or just recommended (explain the benefit and keep it optional).
- Don't ask people for a password (unless they've stopped using Sign in with Apple) — and don't ask for a personal email address when they've shared a private relay address: show their relay address in your app, point them to Settings > Apple Account > Password & Security > Apps using Apple Account to retrieve it, or use other identifiers like an order number or phone number.
- Ask for optional data after engagement (a phone number for text updates, social info for playing with friends); never block account access or features when people decline.
- Be transparent about collected data — welcome people using the name or email they shared so they see how it's used and where to find a relay address.
- Use system-provided buttons (`ASAuthorizationAppleIDButton` / `WKInterfaceAuthorizationAppleIDButton` / web APIs): guaranteed Apple-approved appearance, ideal proportions at any size, automatic title translation, configurable corner radius (iOS, macOS, web), and a VoiceOver alternative-text label.
- Display the button prominently — no smaller than other sign-in buttons, no scrolling to reach it; use one title variant consistently (Sign in with Apple, Sign up with Apple, Continue with Apple; watchOS provides only Sign in).
- Appearances: white (dark backgrounds), white with outline (light backgrounds lacking contrast; iOS, macOS, web only — avoid on dark/saturated backgrounds), black (light backgrounds); the watchOS button uses a system-defined dark gray fill to contrast with the pure black background. Adjust corner radius to match other buttons.
- Custom buttons: people must instantly recognize it as Sign in with Apple (App Review evaluates custom buttons); use only the logo artwork from Apple Design Resources (PNG, SVG, PDF; black and white, with built-in padding) — never create a custom Apple logo.
- Logo rules: use the file to position the logo (never use the logo alone as the button); match the logo file height to the button height; never crop it or add vertical padding.
- Don't change titles (only Sign in with Apple, Sign up with Apple, Continue with Apple), general shape (logo + text buttons are rectangular; logo-only buttons circular or rectangular), or logo/title colors (both black or both white — never custom colors).
- You may change: title font/weight/size, title case (all caps allowed), background (subtle texture or gradient; overall color stays black or white), corner radius, bezel and shadow.
- Logo + text buttons: SVG/PDF for any height; PNG only in 44 pt buttons (the default and recommended height); prefer the system font — the title's font size should be 43% of the button height (button height = 233% of the title size, rounded); preserve default capitalization (first word and "Apple" capitalized) unless your interface is all-caps.
- Vertically center the title, then add the logo at full button height (its built-in padding keeps alignment); inset the logo to align with other authentication logos if needed; keep the margin between title and trailing edge at least 8% of the button's width.
- Logo-only buttons: 1:1 aspect ratio; SVG/PDF at any size, PNG only at 44x44 pt; the artwork already includes padding — don't add horizontal padding, crop the artwork, or use the logo alone; use a mask (circular, rounded rectangle) to change shape; minimum margin around the button: 1/10 of its height.

| Attribute | Minimum |
|---|---|
| Width | 140 pt (140 px @1x, 280 px @2x) |
| Height | 30 pt (30 px @1x, 60 px @2x) |
| Margin around button | 1/10 of the button's height |

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources
- Authentication Services; ASAuthorizationAppleIDButton; WKInterfaceAuthorizationAppleIDButton; Displaying Sign in with Apple buttons on the web; Apple Design Resources (logo artwork); Sign in with Apple button (live previews).

## Augmented reality
Augmented reality (AR) lets you deliver immersive, engaging experiences that seamlessly blend virtual objects with the real world, using the camera to present the physical world live while superimposing 3D objects.

Offer AR features only on capable devices: if AR is your app's primary purpose, make the app available only on ARKit-supporting devices; for optional AR features, don't show an error on unsupported devices — just don't offer the feature.

### Best practices
- Let people use the entire display — devote maximum screen to the world and virtual objects; avoid controls and information that diminish immersion.
- Strive for convincing illusions: detailed 3D assets with lifelike textures, proper scale, placement on detected surfaces, environmental lighting reflection, simulated camera grain, top-down diffuse shadows, and visual updates as the camera moves; update scenes 60 times per second so objects don't jump or flicker.
- Prefer small or coarse reflective surfaces — ARKit reflections are approximations of the captured environment.
- Use audio and haptics to enhance immersion (confirm object contact with a sound effect or bump; background music envelops).
- Minimize text in the environment; display only needed information.
- Put necessary information or controls in screen space (fixed to a consistent location, easy to find while the AR environment moves); consider indirect controls — 2D controls in screen space — for persistent controls, positioned so people don't adjust their grip, with translucency to avoid blocking the scene.
- Anticipate varied real-world environments (little room to move, no large flat surfaces): communicate requirements and expectations up front, and consider different feature sets for different environments.
- Be mindful of comfort: prolonged holding at a distance/angle fatigues — place objects to reduce the need to move closer, and in games keep levels short with downtime.
- Introduce motion gradually (don't make people dodge a projectile on entry), and keep people safe — avoid encouraging rapid, sweeping, or expansive motions.
- Coaching: use the built-in coaching view to guide initialization and relocalization; hide unnecessary app UI while it's showing; if you need custom coaching (specific info like plane detection, or a different visual style), use the system view as reference.
- Object placement: use the coaching view to help people find a horizontal or vertical surface; show a custom indicator when placement is possible, aligned with the detected plane.
- Integrate placed objects immediately — don't wait for more accurate surface data; refine position subtly afterward (e.g., gently nudge an object back onto the surface).
- Guide people toward offscreen virtual objects with visual or audible cues (e.g., an indicator along the left edge).
- Don't precisely align objects with detected surface edges — boundaries are approximations that change as the environment is analyzed.
- Use plane classification to inform placement (furniture only on "floor," a game board only on "table").
- Prefer direct manipulation for object interaction (more immersive and intuitive); indirect controls work better when people are moving around.
- Support standard, familiar gestures (single-finger drag to move, two-finger rotation to spin).
- Keep interactions simple: touch gestures are 2D while the world is 3D — limit movement to the surface the object rests on and rotation to a single axis; respond to gestures within reasonable proximity of an object (assume intent near small, thin, or distant objects).
- Let people scale objects only when it makes sense (fine in an imaginary environment; not for furniture shopping) — and never use scaling to adjust an object's distance (enlarging a distant object yields a larger distant-looking object).
- Beware conflicting gestures (pinch vs. two-finger rotation) and test that they're interpreted correctly.
- Keep object movement consistent with the environment's physics — objects stay attached to real-world surfaces and never jump, vanish, or reappear during movement.
- Explore interactions beyond gestures, like motion and proximity (a character turning its head as someone approaches).
- Multiuser experiences: each participant maps independently and ARKit merges the maps; consider allowing people occlusion (virtual objects behind people in the camera feed enhance realism); let new participants join an ongoing experience via implicit map merging.
- React to real-world objects via reference images and objects (ARKit reports when and where they're detected — posters launching spaceships, a sculpture summoning a virtual tour guide).
- When a detected image first disappears, delay removing attached virtual objects — wait up to one second before fading out (ARKit doesn't track image position changes, so this prevents flickering).
- Use no more than 100 distinct reference images at a time (detection works best); if you need more, change the active set by context (e.g., a museum app loads only images in the person's area).
- Limit reference images requiring accurate position (tracking costs more resources) — use tracked images only when the image may move or attached content is small relative to the image.
- Communicate with approachable terminology — avoid technical terms like ARKit, world detection, and tracking: say "Unable to find a surface. Try moving to the side or repositioning your phone," not "Unable to find a plane. Adjust tracking"; "Tap a location to place the [object]," not "Tap a plane to anchor an object."
- Prefer 3D hints in a 3D context (a rotation indicator around an object beats 2D text instructions); use 2D text hints only when people aren't responding to contextual hints.
- Make important text readable: display critical labels, annotations, and instructions in screen space; 3D text must face people and keep the same type size regardless of distance from the labeled object.
- If necessary, provide a way to get more information (a visual indicator showing people can tap for details).
- Interruptions (app switches, phone calls) break tracking; support relocalization to restore virtual objects to their original positions: use the coaching view to help people return the device to its previous position/orientation; consider hiding previously placed objects during relocalization to avoid flicker, then redisplay at new positions.
- Minimize interruptions by embedding non-AR experiences within the AR experience (e.g., change upholstery without exiting AR); allow people to cancel relocalization (provide a reset button — it can otherwise continue indefinitely).
- When the front-facing camera loses face tracking for more than about half a second, show a visual indicator (keep any text instructions minimal).
- Let people reset the experience if it doesn't meet expectations; suggest fixes for problems: insufficient features detected — "Try turning on more lights and moving around"; excessive motion — "Try moving your phone slower"; slow surface detection — "Try moving around, turning on more lights, and making sure your phone is pointed at a sufficiently textured surface."
- AR icon: use the AR glyph only in controls that launch ARKit-based experiences; never alter it (size and color except), use it for other purposes, or pair it with non-ARKit AR; maintain minimum clear space of 10% of the glyph's height.
- AR badges (collapsed and expanded forms) identify products or objects viewable in AR with ARKit — use them only for that, never altered or recolored; prefer the full AR badge (use the glyph-only badge only in constrained spaces); badge only when your app mixes AR-viewable and non-AR objects (badging everything is redundant); keep placement consistent (same corner of each photo, visible but not occluding details); maintain minimum clear space of 10% of the badge's height.

### Platform considerations
- Not supported in macOS, tvOS, or watchOS. No additional considerations for iOS or iPadOS.
- visionOS: with the wearer's permission, use ARKit to detect surfaces in the person's surroundings, use hand and finger positions to inform custom gestures, and incorporate nearby physical objects into immersive experiences (see the ARKit developer docs for visionOS-specific guidance).

### Resources
- ARKit; ARCoachingOverlayView; ARTrackedRaycast; isCollaborationEnabled; Occluding virtual content with people; Detecting Images in an AR Experience; Managing Session Life Cycle and Tracking Quality; Verifying Device Support and User Permission; Apple Design Resources (AR icon and badges).
