> Source: https://developer.apple.com/design/human-interface-guidelines/privacy

## Privacy
Privacy is paramount: be transparent about the privacy-related data and resources you require, and protect the data people allow you to access.

You must provide privacy practice details for the App Store product page (managed in App Store Connect); people use these details to make informed download decisions.

### Best practices
- Request access only to data you actually need; make permission requests as specific as possible so people have precise control.
- Be transparent about how you collect and use data; respect system features like Hide My Email and Mail Privacy Protection; understand your app-tracking obligations.
- Process data on the device where possible (e.g., Apple Neural Engine, custom CreateML models) to avoid risky server round trips.
- Adopt system-defined privacy protections and security best practices (e.g., CloudKit encryption and key management for strings, numbers, dates in iOS 15+).

### Requesting permission
Permission is required for: personal data (location, health, financial, contacts); user-generated content (emails, messages, calendar, contacts, gameplay, Apple Music activity, HomeKit data, audio/video/photo); protected resources (Bluetooth peripherals, home automation, Wi-Fi, local networks); device capabilities (camera, microphone); ARKit data in a visionOS Full Space (hand tracking, plane estimation, image anchoring, world tracking); the advertising identifier.

- Request permission only when your app clearly needs the data or resource — ideally when people use the feature that requires it (e.g., the location button).
- Avoid launch-time requests unless the data is required to function (people accept a navigation app asking for location up front).
- Write a purpose string (usage description string) that's a brief, complete, straightforward, specific sentence: sentence case, active voice, ending with a period.

| Example purpose string | Notes |
|---|---|
| The app records during the night to detect snoring sounds. | Active sentence that clearly describes how and why data is collected. |
| Microphone access is needed for a better experience. | Passive sentence with a vague, undefined justification. |
| Turn on microphone access. | Imperative sentence with no justification. |

### Pre-alert screens, windows, or views
- Include only one button and make it clear it opens the system alert; title it "Continue" or "Next" — never "Allow" (too similar to the alert's allow button) — and don't add other buttons or actions (except legally required consent).
- Don't include options to cancel or close the view.

### Tracking requests
- If you perform app tracking at launch, you must display the system-provided alert before collecting any tracking data.
- Never precede the system alert with a custom screen that could confuse or mislead (people tap quickly to dismiss); prohibited designs that cause App Review rejection: offering incentives, imitation requests, images of the alert, annotating the screen behind the alert.
- Never offer compensation for granting permission or withhold functionality until people allow tracking. (A consent screen to comply with local privacy laws is allowed.)

### Location button
- In iOS, iPadOS, and watchOS, Core Location provides a button granting temporary (one-time) location authorization at the moment a task needs it; each authorization expires when people stop using the app, but understanding is confirmed only once.
- Consider it for lightweight, feature-specific sharing (attach location to a message, find a store, identify a landmark), especially when people often choose Allow Once.
- Customizable: system title ("Current Location" / "Share My Current Location"), filled or outlined glyph, background/title/glyph colors, corner radius. Other visual attributes can't be customized; the system warns about low contrast or excess translucency; you must ensure text fits without truncation at all accessibility text sizes and in all languages. Persistent problems mean the button stops granting location access.

### Protecting data
- Avoid relying solely on passwords: prefer passkeys; if using passwords, require two-factor authentication; use biometric identification (Face ID, Optic ID, Touch ID) for apps that stay logged in.
- Store sensitive information in the keychain; never store passwords or secure content in plain-text files.
- Avoid inventing custom authentication schemes; prefer passkeys, Sign in with Apple, or Password AutoFill.

### Platform considerations
- macOS: Sign your app with a valid Developer ID for outside-the-store distribution; use app sandboxing (required for the Mac App Store); don't make assumptions about who is signed in (fast user switching).
- visionOS: ARKit algorithms (persistence, world mapping, segmentation, matting, environment lighting) always run but don't send data to apps in the Shared Space — accessing ARKit APIs requires opening a Full Space, and Plane Estimation, Scene Reconstruction, Image Anchoring, and Hand Tracking require permission. User input is private by design (system-drawn hover effects don't expose where people are looking). The back camera provides blank input (compatibility only); the front camera feeds spatial Personas only with permission — replace iOS camera features with import options.

### Resources
App Tracking Transparency, LocationButton (SwiftUI), CLLocationButton, Keychain services, Local Authentication, CloudKit, CreateML, App privacy details on the App Store
