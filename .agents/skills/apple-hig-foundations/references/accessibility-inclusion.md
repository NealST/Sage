> Source: https://developer.apple.com/design/human-interface-guidelines/accessibility
> Source: https://developer.apple.com/design/human-interface-guidelines/inclusion

## Accessibility
Accessible user interfaces empower everyone to have a great experience with your app or game; an accessible interface is intuitive, perceivable (doesn't rely on a single method to convey information), and adaptable.

Audit your interface with Accessibility Inspector, and communicate feature support on the App Store with Accessibility Nutrition Labels.

### Best practices

**Vision**
- Support larger text sizes: let people enlarge text/icons by at least 200% (140% in watchOS apps), via custom UI or Dynamic Type.
- Use recommended defaults for custom type sizes (below); with a thin font weight, aim larger than recommended.
- Meet color contrast minimums (WCAG Level AA, below); if not by default, at least provide a higher-contrast color scheme when Increase Contrast is on; check both appearances when supporting Dark Mode.
- Prefer system-defined colors — they include accessible variants that adapt to Increase Contrast and light/dark settings.
- Convey information with more than color alone: add shapes or icons (red-green and blue-orange pairings are problematic for color blindness); consider letting people customize color schemes.
- Describe your app's interface and content for VoiceOver.

**Hearing**
- Support text-based ways to enjoy audio and video, letting people customize visual presentation: captions (text equivalent of audible info, live-synced), subtitles (translated dialogue), audio descriptions (narration of visual-only info during pauses), transcripts (complete textual description of audible + visual info).
- Use haptics in addition to audio cues; in iOS/iPadOS, Music Haptics and audio graphs convey music and infographics through vibration and texture.
- Augment audio cues with visual cues, especially in games and spatial apps where content may be off screen.

**Mobility**
- Offer sufficiently sized controls (recommended minimums below).
- Treat spacing as important as size: about 12 pt of padding around elements with a bezel; about 24 pt around visible edges of bezel-less elements.
- Support simple gestures for frequent interactions — avoid custom multifinger and multihand gestures.
- Offer alternatives to gestures (e.g., an Edit + tap-to-delete button in addition to swipe-to-delete); core functionality must be reachable through more than one physical interaction.
- Let people use Voice Control (label elements appropriately) and Siri/Shortcuts (including the Action button and Home Screen shortcuts) to operate the app by voice.
- Support and test mobility-related assistive technologies: VoiceOver, AssistiveTouch, Full Keyboard Access, Pointer Control, Switch Control.

**Speech**
- Let people use the keyboard alone to navigate and interact (Full Keyboard Access); avoid overriding system-defined keyboard shortcuts.
- Support Switch Control (control via separate hardware, game controllers, or sounds like a click or pop).

**Cognitive**
- Keep actions simple and intuitive: prefer system gestures and behaviors people already know.
- Minimize time-boxed interface elements (auto-dismissing views); prefer explicit dismiss actions.
- Consider difficulty accommodations in games: adjustable completion criteria, reaction time, control assistance.
- Let people control audio and video playback: don't autoplay without discoverable start/stop controls; consider a global opt-out.
- Allow opting out of flashing lights in video playback (respond to the Dim Flashing Lights setting).
- Be cautious with fast-moving and blinking animations (dizziness, epileptic episodes): respond to Reduce Motion by reducing automatic/repetitive animations — tighten animation springs to reduce bounce, track animations directly with gestures, avoid animating depth changes in z-axis layers, replace x/y/z transitions with fades, avoid animating into and out of blurs.
- Optimize for Assistive Access (iOS/iPadOS): identify core functionality and remove noncritical workflows and UI; break multistep workflows into one interaction per screen; ask for confirmation twice before hard-to-recover actions.

### Specifications

| Platform | Default text size | Minimum text size |
|---|---|---|
| iOS, iPadOS | 17 pt | 11 pt |
| macOS | 13 pt | 10 pt |
| tvOS | 29 pt | 23 pt |
| visionOS | 17 pt | 12 pt |
| watchOS | 16 pt | 12 pt |

| Text size | Text weight | Minimum contrast ratio |
|---|---|---|
| Up to 17 pts | All | 4.5:1 |
| 18 pts | All | 3:1 |
| All | Bold | 3:1 |

| Platform | Default control size | Minimum control size |
|---|---|---|
| iOS, iPadOS | 44x44 pt | 28x28 pt |
| macOS | 28x28 pt | 20x20 pt |
| tvOS | 66x66 pt | 56x56 pt |
| visionOS | 60x60 pt | 28x28 pt |
| watchOS | 44x44 pt | 28x28 pt |

### Platform considerations
- visionOS: offers head and hand Pointer Control and Zoom. Prioritize comfort — immersive interfaces raise the risk of motion sickness: keep interface elements within the field of view; prefer horizontal layouts over vertical ones (neck strain); avoid demanding attention in different locations in quick succession; reduce speed and intensity of animated objects, especially in peripheral vision; be gentle with camera and video motion; avoid anchoring content to the wearer's head (conflicts with Pointer Control); minimize large, repetitive gestures.

### Resources
Accessibility Inspector, Accessibility framework, Accessibility Nutrition Labels, VoiceOver, Dynamic Type, Music Haptics

## Inclusion
Inclusive apps and games put people first by prioritizing respectful communication and presenting content and functionality in ways that everyone can access and understand.

### Best practices
**Inclusive by design**
- Investigate people's goals and perspectives before designing; use empathy to find where a word or image is incomprehensible or means something unintended.
- Remember perspectives arise from shared human characteristics: age, gender and gender identity, race and ethnicity, sexuality, physical and cognitive attributes, permanent/temporary/situational disabilities, language and culture, religion, education, opinions, social and economic context.
- Don't frame inclusion as merely avoiding offense — aim for a welcoming experience everyone can enjoy.

**Welcoming language**
- Consider your tone from different perspectives: be clear, direct, and respectful (an academic tone can feel exclusionary).
- Address people directly with "you"/"your"; avoid "the user"/"the player"; reserve "we"/"our" for your software or company.
- Define specialized or technical terms (or avoid them) — plain language is easier to read and translate.
- Replace colloquial expressions with plain language (culture-specific, hard to translate, sometimes exclusionary).
- Include humor carefully: subjective, hard to translate, can confuse, irritate, or insult.

**Being approachable**
- Present a clear, straightforward interface consistent with platform conventions.
- Build in ways to learn: an onboarding flow with step-by-step help that experienced people can skip.

**Gender identity**
- Avoid unnecessary references to specific genders (e.g., "Subscribers can post recipes" instead of "his or her recipes"); this also aids localization into gendered languages.
- Avoid referencing gender in avatars, emoji, glyphs, and game characters; give people customization tools; use nongendered human images for generic people (SF Symbols offers many, e.g., person.crop.circle, person.3.fill, figure.wave).
- If gender info is required (health or legal reasons), provide inclusive options (nonbinary, self-identify, decline to state) and let people specify pronouns.

**People and settings**
- Portray a range of human characteristics and activities (races, body types, ages, abilities); avoid stereotypical depictions of occupations or behaviors.
- Prefer places, homes, activities, and items familiar and relatable to most people over shows of high affluence.

**Avoiding stereotypes**
- Surface unconscious biases and generalizations (e.g., don't assume family = woman, man, and biological children).
- Avoid context-specific prompts like "your first car" or "favorite subject in college" in security questions; prefer universal experiences.

**Accessibility**
- Support Apple accessibility features (VoiceOver, Display Accommodations, closed captioning, Switch Control, Speak Screen) and never assume a disability means someone doesn't want your experience.
- Remember each disability is a spectrum and everyone can experience disabilities (temporary, e.g., short-term hearing loss; situational, e.g., a noisy train).
- Avoid images and language that exclude people with disabilities; take a people-first approach when writing about disabilities; find out how a person or community self-identifies.
- Prioritize simplicity and perceivability — familiar, consistent interactions perceivable via sight, hearing, or touch.

**Languages**
- Internationalize first, then localize; plain language, no unnecessary gender references, diverse representation, and no stereotypes also prepare you for localization.
- Use SF Symbols (includes LTR and RTL glyphs) to streamline localization.
- Check color meanings per locale (e.g., white = death in some cultures, purity in others) so colors communicate the same thing in every version.

### Resources
Localization (Xcode), SF Symbols, VoiceOver
