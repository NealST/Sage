> Source: https://developer.apple.com/design/human-interface-guidelines/managing-accounts
> Source: https://developer.apple.com/design/human-interface-guidelines/settings
> Source: https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews

## Managing accounts

When it doesn't create an unnecessary barrier to your experience, an account can be a convenient way for people to access their content and track personal details.

### Best practices

- Ask people to create an account only if your core functionality requires it; otherwise let people enjoy the app without one. If required, consider Sign in with Apple.
- Explain the benefits of creating an account and how to sign up — a brief, friendly description in the sign-in view.
- Delay sign-in as long as possible; people abandon apps that force sign-in before anything useful happens (e.g., a shopping app requires sign-in only at purchase).
- If not using Sign in with Apple (iOS, iPadOS, macOS, visionOS), prefer passkeys — they eliminate passwords. If you must use passwords, augment security with two-factor authentication (iCloud Keychain verification codes).
- Always identify the authentication method you offer — title the button "Sign In with Face ID", not a generic "Sign In".
- Refer only to authentication methods available in the current context; check device capabilities (LABiometryType) and use appropriate terminology.
- Avoid an app-specific setting for opting in to biometric authentication — people turn it on at the system level; an in-app setting is redundant and confusing.
- Don't use the term "passcode" for account authentication — people associate it with unlocking their device or Apple services.
- Deleting accounts (if people can create an account in your app, you must help them delete it, not just deactivate it; comply with regional legal requirements, and clearly describe any legally mandated retention or process):
  - Provide a clear way to initiate deletion within the app; otherwise provide a direct link to the webpage where people can do it — make it easy to discover, not buried in Privacy Policy or Terms of Service.
  - Provide a consistent deletion experience in the app and on the website.
  - Consider letting people schedule deletion for the future (also offer immediate deletion).
  - Tell people when deletion will complete and notify them when it's finished.
  - Help people understand billing: auto-renewable subscriptions continue through Apple until cancelled regardless of account deletion; after deleting, people must cancel the subscription or request a refund; provide information on cancelling and managing purchases. Support account deletion even if purchases weren't made in your app.
  - If people used Sign in with Apple, revoke associated tokens when they delete their account.
- TV provider accounts:
  - Use TV Provider Authentication for the most efficient onboarding when sign-in is required.
  - Avoid a sign-out option when people are signed in at the system level; if you must include one, prompt people to sign out in Settings > TV Provider.
  - Never instruct people to sign out by adjusting privacy controls — Settings > Privacy TV provider controls manage which apps can access the account, not sign-out.

### Platform considerations

- tvOS: People use a remote, not a keyboard — ask for the minimum information necessary. Prefer letting people use another device to sign up or authenticate (associated domains can safely suggest credentials, including Sign in with Apple). When signed in to a shared account, avoid asking people to choose their profile every time (tvOS 16+ can share credentials across users while storing each person's profile and data separately; kSecUseUserIndependentKeychain, User Management Entitlement). Minimize data entry — for more than a small amount of information, direct people to a website from another device; for email, show the email keyboard screen with recently entered addresses.
- watchOS: Use iCloud synchronization to provide Keychain access — autofill user names and passwords, preserve app settings.

### Resources

- Supporting passkeys — Authentication Services
- Securing Logins with iCloud Keychain Verification Codes
- Sign in with Apple; Token revocation; Configuring an associated domain

## Settings

People expect apps and games to just work, but they also appreciate having ways to customize the experience to fit their needs.

### Best practices

- Aim for default settings that give the best experience to the largest number of people (e.g., auto-maximize game performance per device instead of asking players).
- Minimize the number of settings you offer — too many makes the experience less approachable and hard to navigate.
- Make settings available in expected ways: Command-Comma (,) opens an app's settings when a physical keyboard is connected; games often use the Esc key.
- Avoid using settings to ask for setup information you can get otherwise (auto-detect a connected controller; detect Dark Mode).
- Respect systemwide settings; don't include redundant custom versions of global options (accessibility, scrolling, authentication) — doing so implies your app ignores them.
- General settings: put general, infrequently changed options in your custom settings area (window configuration, game-saving behavior, keyboard mappings, account options).
- Task-specific options: let people modify them without going to the settings area — in the screens they affect, where they're discoverable (showing/hiding parts of a view, reordering items, filtering a list). In games, players adjust their approach during gameplay, not in settings.
- System settings: add only the most rarely changed options to the system-provided Settings app; consider a button in your interface that opens it directly.

### Platform considerations

- macOS (custom settings window opens from the Settings item in the App menu; typically a toolbar switching between panes):
  - Include a settings item in the App menu; avoid settings buttons in window toolbars (they take space from frequent commands); document-level options belong in the File menu.
  - Dim the settings window's minimize and maximize buttons.
  - Use a noncustomizable toolbar that stays visible and always indicates the active button; people rely on a stable settings interface.
  - Update the window's title to the visible pane; if there are no multiple panes, use the title "App Name Settings".
  - Restore the most recently viewed pane on open.
- watchOS: Apps don't add custom settings to the system Settings app; instead offer a small number of essential options at the bottom of the main view or a More menu for reconfiguring objects.

### Resources

- Settings — SwiftUI; UserDefaults — Foundation; Preference Panes

## Ratings and reviews

People often view the ratings and reviews for an app or game before they download it.

### Best practices

- Ask for a rating only after people demonstrate engagement (completing a game level or significant task); avoid asking on first launch or during onboarding — people haven't formed an opinion and may leave negative feedback.
- Avoid interrupting people during a task or game; look for natural breaks or stopping points.
- Avoid pestering: allow at least a week or two between requests, prompting again only after additional engagement.
- Prefer the system-provided prompt (iOS, iPadOS, macOS): the system checks for previous feedback and displays an in-app prompt for a rating and optional written review; people can supply feedback or dismiss with a single tap or click and can opt out of all such prompts. The system limits the prompt to three occurrences per app within a 365-day period (RequestReviewAction).
- Weigh the benefits of resetting your summary rating when releasing a new version against showing fewer ratings overall — fewer ratings can discourage downloads (Reset app summary rating).
- People can always rate your app within the App Store.

### Resources

- RequestReviewAction — StoreKit
- Reset app summary rating
