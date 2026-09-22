---
name: apple-hig-technologies-domain
description: "Apple HIG distilled reference for Technologies domain topics: Apple Pay, Apple In-App Purchase, Tap to Pay on iPhone, Wallet, HealthKit, ResearchKit, CareKit, ID Verifier, HomeKit, CarPlay, Game Center, SharePlay, ShazamKit, Sign in with Apple, augmented reality. Use when designing payments or checkout flows, passes and order tracking, identity verification, health/research/care apps, smart-home accessories, CarPlay apps, social gaming, shared activities, audio recognition, or AR; also for Apple brand-asset rules (Apple Pay button and mark, Activity rings, HomeKit and Apple Health icons, AR badges) and numeric specs (button minimums, pass image sizes, artwork resolutions). Do not use for: design foundations (apple-hig-foundations), UX flow patterns (apple-hig-patterns), input methods (apple-hig-inputs), UI components (apple-hig-components-*), system tech like Siri/ML/AirPlay/iCloud (apple-hig-technologies-system). 中文触发词: 苹果设计规范, HIG, Apple Pay, 内购, 钱包, 健康, HomeKit, 车载, AR, Game Center, Sign in with Apple"
---

# Apple HIG — Technologies: Domain & Media

Distilled from https://developer.apple.com/design/human-interface-guidelines/ — Technologies section, scraped 2026-09-22. 15 technologies across 3 reference files; best practices, per-platform differences (including "Not supported in X" statements), and numeric specifications are preserved from the source pages.

## Topic index

| Technology | Highlights | Reference |
|---|---|---|
| Apple Pay | Physical goods/services/donations in apps and browsers; payment-sheet customization, error handling, subscriptions, donations; button types/styles, 100–140 pt minimum sizes, mark and trademark rules | [payments-wallet.md](./references/payments-wallet.md) |
| Apple In-App Purchase | Digital goods and subscriptions; four content types; Family Sharing, refunds, effortless signup, offer codes, subscription management; watchOS signup guidance | [payments-wallet.md](./references/payments-wallet.md) |
| Tap to Pay on iPhone | Contactless payments on iPhone with no external hardware; merchant enablement/education, checkout flow, result display, loyalty-card reads; iOS only | [payments-wallet.md](./references/payments-wallet.md) |
| Wallet | Cards, IDs, transit, tickets, keys; pass styles, field anatomy, image size tables, order tracking (Wallet Orders schema), Verify with Wallet identity buttons | [payments-wallet.md](./references/payments-wallet.md) |
| HealthKit | Central health/fitness repository; privacy and permission practices; Activity rings rules; Apple Health icon and editorial guidelines | [health-identity.md](./references/health-identity.md) |
| ResearchKit | Medical research studies; onboarding order (introduction, eligibility, consent, permissions), surveys, active tasks, profile and dashboard | [health-identity.md](./references/health-identity.md) |
| CareKit | Care-plan apps; CareKit UI/Store; task styles, charts, contacts, notifications; motion data, photos, HealthKit/ResearchKit integration | [health-identity.md](./references/health-identity.md) |
| ID Verifier | In-person mobile ID reading (iOS 17+); Display Only vs Data Transfer requests; Verify Age/Verify Identity buttons; Apple Business Register | [health-identity.md](./references/health-identity.md) |
| HomeKit | Smart-home accessory apps; object model and terminology, setup flow, naming rules, Siri interactions, custom functionality, cameras; HomeKit icon and naming guidelines | [home-media-ar.md](./references/home-media-ar.md) |
| CarPlay | Driving-optimized apps via system templates; iPhone interaction rules, audio behavior, layout/color, icon specs; errors reported in CarPlay only | [home-media-ar.md](./references/home-media-ar.md) |
| Game Center | Social gaming network; access point and overlay/dashboard, achievements and leaderboards (image spec tables), challenges, party-code multiplayer; tvOS/watchOS differences | [home-media-ar.md](./references/home-media-ar.md) |
| SharePlay | Shared real-time activities with FaceTime/Messages; join friction, terminology, visionOS Personas and spatial/custom templates (5 seats, 1 m apart) | [home-media-ar.md](./references/home-media-ar.md) |
| ShazamKit | Audio recognition against the Shazam or a custom catalog; microphone permission, stop recording ASAP, opt-in iCloud storage | [home-media-ar.md](./references/home-media-ar.md) |
| Sign in with Apple | Private authentication with Apple Account; sign-in timing, data minimization, relay addresses; system and custom button specs (140x30 pt minimums, 43% title ratio) | [home-media-ar.md](./references/home-media-ar.md) |
| Augmented reality | ARKit blending virtual objects with the real world; 60 fps rendering, coaching and relocalization, object placement and gestures, reference-image limits (≤100), AR icon and badges | [home-media-ar.md](./references/home-media-ar.md) |

## How to use

- Find the technology in the index, open its reference file, and apply the "Best practices" bullets (imperative do/don't guidance condensed from the source pages).
- Check each technology's "Platform considerations" section before committing to a design — several technologies are iOS-only (Tap to Pay on iPhone, ID Verifier) or unsupported on specific platforms (Apple Pay and Wallet on tvOS, SharePlay on watchOS, HealthKit on macOS/tvOS/visionOS).
- Preserve numeric specifications exactly as tabulated: payment and sign-in button minimums, Wallet pass image dimensions and order-tracking image sizes, Game Center artwork resolutions, and CarPlay display sizes.
- Respect Apple brand-asset rules verbatim (Apple Pay mark, Activity rings, Apple Health and HomeKit icons, AR glyph/badges, Sign in with Apple logo artwork) — these are trademark requirements, not stylistic suggestions.
- For topics outside this skill, see the sibling skills listed in the description's "Do not use for" clause (foundations, patterns, inputs, components, system technologies).
