> Source: https://developer.apple.com/design/human-interface-guidelines/apple-pencil-and-scribble
> Source: https://developer.apple.com/design/human-interface-guidelines/gyro-and-accelerometer
> Source: https://developer.apple.com/design/human-interface-guidelines/nearby-interactions

## Apple Pencil and Scribble

Apple Pencil helps make drawing, handwriting, and marking effortless and natural, in addition to performing well as a pointer and UI interaction tool. It offers pixel-level precision on iPad, and Scribble lets people use Apple Pencil to enter text in any text field through fast, private, on-device handwriting recognition.

### Best practices

- Support behaviors people intuitively expect from real-world marking instruments (e.g., people often want to write in the margins of documents or books).
- Let people choose when to switch between Apple Pencil and finger input: if your app supports Pencil for marking, make controls respond to Pencil too — a control that doesn't might seem unresponsive or low on battery (Scribble only supports Apple Pencil input).
- Let people make a mark the moment Apple Pencil touches the screen — don't require tapping a button or entering a special mode first.
- Respond to the way people use Apple Pencil: tilt (altitude), force (pressure), orientation (azimuth), and barrel roll can affect strokes (thickness, intensity). Keep pressure response simple and intuitive — continuous properties like ink opacity or brush size feel natural.
- Provide visual feedback indicating a direct connection with content: Pencil should appear to directly and immediately manipulate the content it touches, never initiate disconnected actions or affect content elsewhere on screen.
- Design a great left- and right-handed experience: avoid placing controls where either hand may obscure them; consider letting people reposition controls.
- Hover:
  - Use hover to help people predict what happens when Pencil touches the screen (preview the dimensions and color of the current tool's mark).
  - Avoid continuously modifying the preview as Pencil moves closer or farther — height-based changes rarely clarify and are distracting.
  - Don't use hover to initiate an action: hovering is imprecise, and people shouldn't inadvertently trigger — especially destructive — actions.
  - Prefer preview values near the middle of a dynamic range (maximum could occlude the marking area; minimum may be undetectable).
  - Consider hover for interactions close to where people are marking (e.g., a contextual menu of tool sizes revealed on squeeze or a modifier key), so they don't move their hands elsewhere.
  - Prefer showing hover previews for Apple Pencil only, not a pointing device — identical feedback for both is confusing.
- Double tap (supported Apple Pencil models; default toggles current tool and eraser; people can set it to toggle previous tool, show/hide the color picker, or do nothing):
  - Respect people's settings when they make sense in your app; if they don't, you can use the gesture to change interaction mode (e.g., toggle raise/lower in a mesh-editing tool).
  - If you offer custom double-tap behavior, provide a control that lets people choose it; make the current mode discoverable but not on by default.
  - Don't use double tap to modify content — accidental double taps happen; prefer easily undone actions and never destructive ones that could lose data.
- Squeeze (Apple Pencil Pro; works only while the paired iPad screen is on and Pencil isn't touching it, so people might miss the onscreen result; people may configure squeeze to run an App Shortcut instead):
  - Treat squeeze as a single, quick gesture performing a discrete (not continuous) action — holding or repeating squeezes is tiring; display the result promptly.
  - If squeeze reveals app UI (e.g., a contextual menu), display it close to Pencil Pro to strengthen the gesture-device connection.
  - Define nondestructive, easy-to-undo squeeze actions; avoid anything that could lose data.
- Barrel roll (Apple Pencil Pro, while marking — e.g., rotating the angle of a highlight):
  - Use barrel roll only to modify marking behavior, never for navigation or displaying controls.
- Scribble (integrated into iPadOS; available to all apps by default):
  - Make text entry fluid: Scribble works in all standard text components (text fields, text views, search fields, editable web-content fields) except password fields; in custom text fields, don't make people tap or select first.
  - Make Scribble available everywhere text entry seems natural, even blank space without a text field (e.g., writing a new reminder below the last item — `UIIndirectScribbleInteraction`).
  - Avoid distracting people while they write: no autocompletion text while writing; hide placeholder text the moment writing begins.
  - Keep the text field stationary while people write (a moving field feels like lost control); if movement is unavoidable, delay it until people pause.
  - Prevent autoscrolling while people write or edit — people avoid writing on top of text, and scrolling during selection can select the wrong range.
  - Give people enough space to write: increase text field size before writing begins or during a pause, never while writing (`UIScribbleInteraction`).
- Custom drawing (PencilKit — low-latency notes, annotation, drawing; custom canvas with tool picker and ink palette):
  - Help people draw on top of existing content: canvas colors dynamically adjust to Dark Mode by default; prevent that adjustment when marking over a PDF or photo so markup stays sharp and visible.
  - In a compact environment the tool picker lacks undo/redo buttons — display custom undo/redo buttons in a toolbar, and support the standard 3-finger undo/redo gesture in any environment.

### Platform considerations

iPadOS only. Not supported in iOS, macOS, tvOS, visionOS, or watchOS.

### Resources

- PencilKit; PaperKit; UIIndirectScribbleInteraction; UIScribbleInteraction; Adopting hover support for Apple Pencil

## Gyroscope and accelerometer

On-device gyroscopes and accelerometers can supply data about a device's movement in the physical world. Use the data for real-time, motion-based experiences in iOS, iPadOS, and watchOS apps and games; tvOS apps can use gyroscope data from the Siri Remote (Core Motion).

### Best practices

- Use motion data only to offer a tangible benefit (fitness feedback, enhanced gameplay); avoid gathering data simply to have it.
- If your experience needs motion data, you must provide copy explaining why — the system includes it in the first-run permission request, where people grant or deny access.
- Outside active gameplay, avoid using accelerometers or gyroscopes for direct manipulation of your interface: motion gestures are hard to replicate precisely, physically challenging for some people, and affect battery usage.

### Platform considerations

No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources

- Getting processed device-motion data — Core Motion

## Nearby interactions

Nearby interactions support on-device experiences that integrate the presence of people and objects in the nearby environment. They feel intuitive because they build on people's innate awareness of the world (e.g., bringing an iPhone close to a HomePod mini transfers audio output). Available on devices with Ultra Wideband; relies on the Nearby Interaction framework. People grant permission before participating, and the APIs preserve privacy via randomly generated device identifiers that last only for the interaction session.

### Best practices

- Find inspiration in the physical-world version of a task (bringing devices close together to transfer a song feels rooted in the real world).
- Use distance, direction, and context to inform the interaction — prioritize nearby, contextually relevant information (the share sheet suggests the closest contact the person is facing, using on-device knowledge plus U1-chip data).
- Consider how changes in physical distance can guide the interaction: people expect perception to sharpen as they approach (finding an AirTag transitions from a directional arrow to a pulsing circle).
- Provide continuous feedback that responds to people's movements (Find My gives uninterrupted direction and proximity updates).
- Consider multiple feedback types — visual, audible, haptic — transitioning fluidly: visual while people interact with the screen; audible and haptic while they interact with their environment.
- Avoid a nearby interaction as the only way to perform a task; always provide alternatives.

### Device usage

- Encourage portrait orientation: landscape can decrease accuracy and availability of distance and direction information. Prefer implicit visual feedback about how to hold the device; avoid explicitly telling people.
- Design for the device's directional field of view (similar to the Ultra Wide camera on iPhone 11 and later): a peer device outside the field of view may report distance but not relative direction.
- Help people understand that intervening people, animals, or large objects between devices decrease accuracy or availability — add advice to onboarding or tutorials.

### Platform considerations

No additional considerations for iPadOS. Not supported in macOS, tvOS, or visionOS.

- iOS: Nearby Interaction APIs provide a peer device's distance and direction.
- watchOS: APIs provide a peer device's distance only; all participating watchOS apps must be in the foreground.

### Resources

- Nearby Interaction framework
