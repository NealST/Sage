> Source: https://developer.apple.com/design/human-interface-guidelines/apple-pay
> Source: https://developer.apple.com/design/human-interface-guidelines/apple-in-app-purchase
> Source: https://developer.apple.com/design/human-interface-guidelines/tap-to-pay-on-iphone
> Source: https://developer.apple.com/design/human-interface-guidelines/wallet

# Payments & Wallet technologies

## Apple Pay
Apple Pay is a secure, easy way to make payments for physical goods and services, donations, and subscriptions in apps and in any browser.

Use Apple In-App Purchase for virtual/digital goods; use Apple Pay for physical goods, services, and donations. The payment sheet shows cards, amounts (tax/fees), shipping options, and contact info; people authorize with Face ID, Touch ID, Optic ID, double-click on Apple Watch, or — in browsers — a nearby device or scanned code.

### Best practices
- Offer Apple Pay on all supported devices and browsers; if a device doesn't support it, don't present it as a payment option.
- Make Apple Pay the primary payment option when credentials are available. If you use Apple Pay APIs to detect an active card, Apple Pay must be primary (not necessarily sole) everywhere you use the APIs; don't separate it into a different step or flow (e.g., pre-select it among other options).
- Use Apple Pay buttons only to initiate payment or, when appropriate, Apple Pay setup. A custom payment button must not display "Apple Pay" or the Apple Pay logo — signal acceptance with the Apple Pay mark graphic or a text reference on the same page.
- Use the Apple Pay mark graphic only to communicate that you accept Apple Pay; never use it as or position it as a button.
- Don't hide an Apple Pay button or make it appear unavailable; if it can't be used yet (e.g., size or color unselected), gracefully point out the problem after the tap.
- Inform search engines that Apple Pay is accepted on your website via semantic markup.
- All websites offering Apple Pay must include a privacy statement and adhere to the Acceptable Use guidelines.
- Provide a cohesive checkout experience — your branding throughout, no new pages or windows (new windows suggest a handoff to a different website).
- If Apple Pay is available, assume people want it: show it first, larger, or visually separated from other options.
- Accelerate single-item purchases with Apple Pay buttons on product detail pages; such purchases are for an individual item only (excluding cart items; remove the item from the cart after purchase).
- Accelerate multi-item purchases with express checkout: payment sheet appears immediately; one shipping method and destination for the whole cart.
- Let people enter coupon/promotional codes on the payment sheet instead of a separate step (critical in express checkout).
- Collect required info (color, size) before people reach the Apple Pay button; when something is missing, highlight it and auto-navigate to the field.
- Collect optional info (gift messages, delivery instructions) before or after checkout — the payment sheet can't take it.
- Gather multiple shipping methods/destinations for an order before showing the sheet (the sheet allows only one of each per order).
- For in-store pickup, help people choose the location before the sheet; show its address on the sheet.
- Prefer checkout information from Apple Pay — assume it's complete and current; fetch the latest rather than reuse existing app data.
- Avoid requiring account creation before purchase; ask on the order confirmation page and prepopulate registration fields from checkout data.
- Report transaction results in the payment sheet; on failure (e.g., bad address), provide error messages with next steps.
- Display an order confirmation/thank-you page with shipping and status info; if you list Apple Pay there, show it after the last four digits ("1234 (Apple Pay)") or as a note ("Paid with Apple Pay").
- Present and request only essential information on the payment sheet (e.g., no shipping address for an electronically delivered gift card — it implies physical delivery).
- Display the active coupon code, or let people enter one, on the sheet.
- Let people choose the shipping method in the sheet: clear description, cost, and optionally estimated delivery/pickup dates; use the method's calendar and time-zone support for accuracy.
- For in-store pickup, consider letting people choose a pickup window (a date/time range via the shipping method).
- Use line items (label + cost; plus frequency for recurring payments) for additional charges, discounts, pending costs, add-on donations, and recurring/future payments — never for an itemized product list.
- Keep line items short, specific, and ideally on a single line.
- Provide a business name after "Pay" on the total line, matching the bank-statement name: `Pay [Business_Name]`.
- If you're an intermediary (marketplace), identify both businesses: `Pay [End_Merchant (via Your_Business)]`.
- When the total isn't known at checkout (distance-based fares, post-delivery tips) and local regulations allow, explain in the sheet and mark a subtotal "Amount Pending"; reflect preauthorized amounts accurately.
- Handle data entry and payment errors gracefully; defer to the payment sheet for progress/loading states (extra spinners confuse).
- Data validation errors: the system highlights invalid fields and shows a detail view — supply customized messages for it. Before authorization you can access only card type and a redacted shipping address, so validate what's available and report problems before authorization too.
- Don't force compliance with your business logic: ignore irrelevant data and infer missing data (accept Zip+4 when 5 digits are required; accept phone numbers with or without dashes/country codes).
- Report problems accurately to the system with a custom error message and the correct status code.
- Explain problems clearly: reference the field and the expectation ("Zip code doesn't match city," "Shipping not available for this state"); noun phrases, sentence-style capitalization, no ending punctuation, ≤128 characters.
- Handle interruptions: when the sheet dismisses (cancellation, timeout), cancel any in-progress payment; people restart by tapping the Apple Pay button again.
- Subscriptions: clarify billing frequency and terms before showing the sheet; include line items reiterating frequency, discounts, and upfront fees; if no payment is due at authorization, disclose when billing begins.
- For trials, use line items for the trial amount (including $0), the post-trial regular amount, and the date regular billing starts; clarify the current amount in the total line.
- Show the payment sheet only when a subscription change adds fees — not when cost decreases or stays the same.
- Treat the billing agreement field as a concise plain-language summary, not a substitute for formal terms; leave it blank when in doubt.
- Donations (approved nonprofits): identify with a line item (e.g., "Donation $50.00"); offer predefined amounts ($25/$50/$100) plus an Other Amount option.
- Always create Apple Pay buttons with the Apple-provided APIs (approved captions/fonts/colors/styles, proportional scaling, automatic localization, corner-radius customization, built-in VoiceOver alt text); never design custom buttons or replicate Apple's.
- Choose the button type matching the flow: plain, Check Out, Continue, Book, Donate, Subscribe, Reload, Add Money, Top Up, Order, Rent, Support, Contribute, Tip; the plain type suits smaller minimum widths or unstated calls to action (unsupported types fall back to it). The system may show the default card image on buttons.
- Show a Set Up Apple Pay button when the device supports Apple Pay but it isn't set up — in Settings, a profile, or an interstitial page.
- Button styles: automatic (follows system appearance); black on white/light high-contrast backgrounds (never black/dark); white with outline on low-contrast light backgrounds (never dark or saturated); white on dark high-contrast backgrounds.
- Display the button prominently — no smaller than other payment buttons, no scrolling to reach it; place it right of Add to Cart in a side-by-side layout, above Add to Cart when stacked; adjust corner radius to match other buttons.
- If a size can't fit the translated title, the system replaces the button with the plain Apple Pay button (no automatic replacement for Set Up Apple Pay).
- Apple Pay mark: use only Apple artwork, altering nothing but height; height equal to or larger than other payment marks; don't adjust width/corner radius/aspect ratio, add trademark symbols or content, remove the border, add effects (shadows, glows, reflections), or flip/rotate/animate.
- Keep minimum clear space around the mark of 1/10 of its height; never share its border with another graphic or button.
- Referring to Apple Pay: use "Apple Pay" exactly as in the Apple Trademark List — two words, uppercase A and P, never plural or possessive, never translated; all-caps only to conform to an established all-caps typographic style.
- In the US, use ® the first time Apple Pay appears in body text (not as a checkout selection option); never use the Apple logo to represent "Apple" in text; coordinate fonts with your app/website rather than mimicking Apple typography.
- In payment selection, use a text-only Apple Pay description only when every other payment option is also text-only; otherwise use the mark graphic.

Website icon (used during payment authorization, Handoff, and Wallet subscription flows):

| Scale | Size |
|---|---|
| @2x | 60x60 pt (120x120 px) |
| @3x | 60x60 pt (180x180 px) |

| Button | Minimum width | Minimum height | Minimum margins |
|---|---|---|---|
| Apple Pay | 100 pt (100 px @1x, 200 px @2x) | 30 pt (30 px @1x, 60 px @2x) | 1/10 of button height |
| Book/Buy/Check Out/Donate/Set Up/Subscribe with Apple Pay | 140 pt (140 px @1x, 280 px @2x) | 30 pt (30 px @1x, 60 px @2x) | 1/10 of button height |

### Platform considerations
- Not supported in tvOS. No additional considerations for iOS, iPadOS, macOS, visionOS, or watchOS.

### Resources
- PassKit: PKPaymentAuthorizationController, PKPaymentButton (Type/Style), PKPaymentError, PKDateComponentsRange, paymentSummaryItems; WKInterfacePaymentButton (watchOS); Apple Pay on the Web; Apple Pay Marketing Guidelines.

## Apple In-App Purchase
People can use Apple In-App Purchase to pay for digital goods and services, like premium content and subscriptions, securely within your app; items can also be promoted through the App Store.

Four content types: consumable (depletes with use, repurchasable), non-consumable (never expires), auto-renewable subscriptions (renew each period until canceled), and non-renewing subscriptions (limited time, repurchased to extend). For exceptionally large, frequently updated multi-creator catalogs, or subscriptions with optional add-on content sold as one purchase, use the Advanced Commerce API.

### Best practices
- Let people experience the app before purchasing; for auto-renewable subscriptions, consider limited free access.
- Design an integrated shopping experience that mirrors your app's style — browsing and purchasing should never feel like a different app.
- Use simple, succinct product names and descriptions that don't truncate or wrap.
- Display the total billing price for every in-app purchase, regardless of type.
- Display your store only when people can make payments (`canMakePayments`); otherwise hide it or explain why it's unavailable (e.g., parental restrictions).
- Use the default system confirmation sheet; don't modify or replicate it.
- Family Sharing (share subscriptions and non-consumables with up to five additional family members across devices): prominently mention it where people learn about your content ("Family"/"Shareable" in names, sign-up screens); customize messaging so it makes sense to purchasers and family members ("Your family subscription includes…").
- Provide help plus the system refund flow (`beginRefundRequest`): offer help before people request refunds (resolve missing purchases, FAQs, feedback, support contact); use a simple title like "Refund" or "Request a Refund"; help people find the purchase (product image, name, description, purchase date); consider alternatives (immediate fulfillment, conciliatory item) while making clear a refund is still possible; don't create barriers (no scrolling or extra screens before the refund button); don't characterize or speculate on Apple's refund policies.
- Auto-renewable subscriptions: call out benefits during onboarding with a strong call to action and clear terms summary; offer a range of choices, service levels, and durations; consider free sampling (freemium app, metered paywall, free trial); prompt at relevant times (e.g., nearing the monthly free-content limit); encourage a new subscription only for non-subscribers, with a sign-in option so multi-channel subscribers don't think they must pay again.
- Signup: provide clear, distinguishable options (short names, price and duration for each; introductory price plus offer duration plus the standard price after it ends); ask only for necessary information and defer the rest (lengthy signup lowers conversion).
- In tvOS, help people sign up or authenticate on another device using a code.
- The in-app sign-up screen must include: subscription name, duration, and content/services per period; correctly localized billing amounts; a way for existing subscribers to sign in or restore purchases.
- Clearly describe free trials — especially that payment auto-initiates when the trial ends (show trial duration and the post-trial billed amount).
- Include a sign-up opportunity in settings and account screens.
- Offer codes (iOS/iPadOS): one-time use codes (unique, from App Store Connect; redeemed via URL, in app, or in the App Store — for small or restricted distribution) and custom codes (e.g., NEWYEAR; redeemed via URL or in app — for mass campaigns).
- Custom codes use only alphanumeric ASCII characters — no special characters, including Chinese and Arabic; since people can't redeem them in App Store account settings, tell them where to redeem.
- Support in-app redemption with StoreKit (`presentOfferCodeRedeemSheet`) — your only custom UI is what starts the system flow (e.g., a "Redeem Code" button on the paywall, onboarding, or settings).
- Supply an engaging promotional image (otherwise the app icon is used); align the post-redemption experience with the subscriber's new status (welcome experience, feature tour) and onboard smoothly people who subscribed before ever opening your app.
- Subscription management: support in-app upgrade/downgrade/cancel; show summaries including the upcoming renewal date (`Product.SubscriptionInfo`); consider the system management UI (`showManageSubscriptions`); encourage retention (remind what they'd lose, suggest another plan, offer a discount; Retention Messaging API, Win-back offers); always make cancellation easy — buried or hard-to-recognize cancellation feels discouraging.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, or visionOS.
- watchOS: the sign-up screen must display the same required information as other versions of your app. Clearly describe differences between device versions (e.g., content subsets) without implying an identical experience. Consider a modal sheet for all required items (default Close button returns people to free content; a custom sign-up view needs a complete flow with Close/Cancel). Make options easy to compare on a small screen: one option per button (lock each button to its description) or one option per list row followed by a button whose title reflects the choice.

### Resources
- StoreKit: canMakePayments, beginRefundRequest, showManageSubscriptions, Product.SubscriptionInfo, presentOfferCodeRedeemSheet, offerCodeRedemption; Retention Messaging API; Win-back offers; Advanced Commerce API; App Review Guidelines.

## Tap to Pay on iPhone
Tap to Pay on iPhone lets merchants accept contactless payments using an app on their iPhone, without connecting external hardware; it works alongside existing payment-acceptance hardware and accessories.

Integration requires a supported payment service provider (PSP), the Tap to Pay entitlement, and ProximityReader APIs (directly or through the PSP's SDK).

### Best practices
- Merchants must accept the terms and conditions before initial device configuration — help them do so before customer-facing flows (e.g., buttons in onboarding or in-app messaging).
- Present the terms only to an administrative user; tell nonadministrators that administrator access is required (enterprise apps can let an admin accept via a web interface or another app — contact your PSP).
- If your PSP requires specific iOS versions, present the terms only after the merchant updates the device.
- Educate merchants with a tutorial covering supported payment types and how to accept each: via a Learn More option, automatically after terms acceptance, automatically for new users, or in a consistent place (help content/settings). Build it from Apple-approved assets or the ProximityReaderDiscovery API (kept up to date, localized).
- A custom tutorial must show how to launch checkout for each payment type, position a contactless card or digital wallet on the device, and handle PIN entry including accessibility mode; end with an opportunity to accept the terms.
- Checkout is time-sensitive: offer other payment options as needed, respond quickly if checkout starts before enabling, keep checkout usable while configuration is in progress, and present pre-payment actions that affect the total before checkout completes.
- Provide Tap to Pay as a checkout option whether or not it's enabled; on tap, present terms if necessary and show the Tap to Pay screen automatically when configuration completes.
- Avoid making merchants wait: prepare the feature at app start and on every transition to the foreground (`prepare(using:)`).
- Keep the option selectable during background configuration and then show a progress indicator — indeterminate normally, determinate when the API reports progress (`PaymentCardReader.Event.updateProgress`).
- Make the button easy to find without scrolling; if Tap to Pay is your only payment method, open it automatically when checkout begins.
- Make switching between Tap to Pay and hardware accessories easy: set up both at the same time; switch methods during checkout without visiting app settings.
- Button label: "Tap to Pay on iPhone," or "Tap to Pay" when space is constrained; if it's the only payment method, reuse existing Charge/Checkout buttons. With icons, use the `wave.3.right.circle`/`.fill` SF Symbols; never include the Apple logo; match your app's button color and shape. Use these labels only for payment actions.
- Determine the final amount before merchants initiate the experience and display it on the Tap to Pay screen; show pre-payment options (tipping, payment type selection) before the screen.
- Start processing as soon as possible — request the read result before the checkmark animation finishes (`returnReadResultImmediately`).
- Show a progress indicator while payment authorizes (after the screen's animation finishes; `PaymentCardReader.Event.readyForTap`) since authorization can take seconds.
- Clearly display the result, declined or successful (declines: insufficient funds, fraud suspicion, wrong PIN); offer customers digital receipts (QR code, text message).
- When a payment can't complete (unreadable card, unsupported network, amount not allowed, no online PIN): accept an alternate payment (e.g., cash), check out with another method (external hardware, payment link), or relaunch for another card.
- In Strong Customer Authentication (SCA) regions the issuing bank may request a PIN after the processing request — show the PIN entry screen instead of the result; in Offline PIN markets some PSPs support partial-data fallback to another method (contact your PSP for both).
- For system errors the merchant must address, describe the problem and recommend a resolution (e.g., update to the latest iOS); make in-app or web help and support contact easy to reach.
- For card reads with no transaction amount (looking up a past transaction, storing a card, refunds, verification), use a generic button label — "Look Up," "Store Card," "Verify," or "Refund" — never "Tap to Pay on iPhone" or "Tap to Pay."
- Loyalty, discount, and points cards in Wallet can be read alongside a payment card or independently; give loyalty transactions a separate, clearly labeled button and avoid payment-related terms in its label.

### Platform considerations
- Not supported in iPadOS, macOS, tvOS, visionOS, or watchOS. No additional considerations for iOS.

### Resources
- ProximityReader: Adding support for Tap to Pay on iPhone, prepare(using:), PaymentCardReader.Event (updateProgress, readyForTap), returnReadResultImmediately, ReadError; ProximityReaderDiscovery; Tap to Pay on iPhone marketing guidelines.

## Wallet
Wallet helps people securely store their credit and debit cards, driver's license or state ID, transit cards, event tickets, keys, and more on iPhone and Apple Watch; people use them for Apple Pay purchases, order tracking, identity confirmation, boarding, events, and discounts.

### Best practices
- Offer to add new passes to Wallet when an action creates one (system UI, one tap); for frequent, predictable actions like flight check-in, add in the background after one-time authorization; if people want to review first, show a custom view with an Add to Apple Wallet button.
- Suggest adding passes created outside your app (website, another device); if declined, don't ask again.
- Add related passes as a group (multi-connection boarding passes; bundled web-distributed tickets) so people don't add each individually.
- Display an Add to Apple Wallet button wherever pass information appears, for passes not already in Wallet (`PKAddPassButton`; a badge is available for emails and webpages).
- Let people jump from your app to a pass in Wallet ("View in Wallet") wherever you show its info.
- Tell the system when passes expire — set expiration date, relevant date, and voided correctly so Wallet hides expired passes.
- Always get permission before deleting passes (in-app setting for manual vs. automatic removal, or an alert).
- Help the system suggest passes when relevant: supply time and place relevance so passes surface on the Lock Screen; event tickets can also start a Live Activity.
- Keep passes up to date (e.g., boarding pass shows delays and gate changes); send change messages only for time-critical updates — never marketing — since they interrupt; change messages are per-field.
- Define pass content with pass fields plus semantic tags: semantic tags describe content to the system (enabling Lock Screen surfacing and featured actions) and are required for poster event and semantic boarding passes (they enable automatic layout), but include pass fields alongside for older iOS devices. The back of a pass holds rarely needed settings and legal text; supplemental info can go on sheets linked from the front.
- Field areas: logo/logo text and header fields stay visible when collapsed; primary field carries the most important information; secondary/auxiliary fields are useful but less critical; footer fields show supplemental info (e.g., "Annual"); back fields appear in pass details.
- Design a clean, simple pass that feels at home in Wallet instead of replicating its physical counterpart; use Pass Designer (templates or blank) to create and preview.
- Design for all devices: Apple Watch shows less information and fewer images — don't put essential information in elements unavailable on some devices; avoid padding images (watchOS crops white space).
- Keep the front uncluttered (essential info in the header, quick-access info on the front, rarely needed details on the additional-information sheet); make the pass instantly identifiable (brand colors, images, icons, full-art backgrounds); ensure sufficient text/background contrast (solid and image backgrounds); use language that works on any device ("Slide to view" is iPhone-only).
- Pass styles: boarding pass (all travel tickets; semantic tags for airline boarding passes, pass fields for other transit), coupon (special offers and discounts), event ticket (specific events or season tickets; supports full-art background; poster event passes use semantic tags, non-poster use standard fields with optional background and thumbnail), store card (loyalty/discount/points/gift cards; shows account balance), poster generic (full background image and distinct layout; flexible, use when no other style fits), generic (anything else, e.g., gym membership, coat-check ticket).
- Create pass images as PNG in @2x and @3x; reserve them for visual content — embedded text is inaccessible and may not display (use text fields and semantic tags; add barcodes via APIs, never embed them); keep file sizes small; always provide a pass icon (used on the Lock Screen, in Mail, and on passes).
- Avoid inner drop shadows on logo artwork; keep areas behind strip-image text uncluttered (never embed text in strip images); make thumbnails square with rounded corners as transparent PNG; for poster passes keep content within the safe area (a material strip covers the bottom edge) and account for any barcode in the background design.

| Image | Filename | Size (pt) | Pass styles |
|---|---|---|---|
| Logo | logo.png | 50–160 w x 50 h | Non-semantic airline boarding passes, other boarding styles, coupons, non-poster event tickets, generic, store cards |
| Primary logo | primaryLogo.png | 30–126 w x 30 h | Semantic airline boarding passes, poster event tickets, poster generic passes |
| Secondary logo | secondaryLogo.png | 12–135 w x 12 h | Poster event tickets |
| Icon | icon.png | 38 x 38 | All |
| Strip image | strip.png | 375 x 144 | Coupons, store cards |
| Thumbnail | thumbnail.png | 60–90 w x 90 h | Event tickets, generic passes |
| Background (blurred behind content) | background.png | 343 x 503 | Event tickets |
| Poster background (unblurred) | artwork.png | 358 x 448 | Poster event tickets, poster generic passes |
| Footer | footer.png | 268 x 15 | Airline boarding passes |

- Order tracking (iOS 17+): supply as much data as the Wallet Orders schema allows (product descriptions, order status, contacts, shipping/pickup details including arrival dates, addresses, tracking numbers, pickup instructions); Wallet shows a dashboard of active and completed orders in system-defined interfaces.
- Add orders to Wallet automatically after Apple Pay transactions (`PKPaymentOrderDetails` app / `ApplePayPaymentOrderDetails` web) or with `AddOrderToWalletButton` ("Track with Apple Wallet") in confirmation/status/tracking pages and emails; adding an already-added order opens Wallet and displays it.
- Make order information available immediately (people need confirmation even while payment/fulfillment is pending); if details aren't ready, provide what you have plus a status description like "Check back later for full order details."
- Provide fulfillment info as soon as available; the system maps your fulfillment status to values like Order Placed, Processing, Ready for Pickup, Picked Up, Out for Delivery, Delivered, Issue, or Canceled, updating the order and optionally notifying customers.
- Supply a high-resolution, nontransparent 300x300 px PNG or JPEG logo (shown in the dashboard and detail views) and distinct product images — straightforward depictions on solid nontransparent backgrounds (no lifestyle shots), 300x300 px PNG/JPEG.
- Keep text brief (the system truncates), use clear localized language, and show prices that match the confirmed final price.
- Provide a universal link to your order management area; describe each item clearly so people can verify contents (`LineItem` with price, name, image); attach PDF receipts to transactions when appropriate.
- Supply a prioritized list of your apps (the system links the highest-priority installed app, else the first in the list); avoid duplicate notifications by suppressing Wallet's order notifications when the customer has an associated app installed.
- Provide multiple contact methods (a website or landing page at minimum; optionally Messages for Business, phone, email, support page) so people can choose.
- For each fulfillment, supply enough to know where items are and when to expect them: a carrier website link (direct link in addition to the tracking number), a scannable barcode when pickup requires one, and clear pickup/delivery instructions; keep the fulfillment screen centered on tracking.
- Use shipping statuses that match your data: carrier name when known (otherwise leave the default "Track Shipment"); specific values (`onTheWay`, `outForDelivery`, `delivered`) when you have interim carrier detail, plain `shipped` when you don't; always include a tracking link when available.
- Write approachable, accurate status descriptions; be direct and thorough about Issue and Canceled statuses.
- Identity verification (iOS 16+): people can store an ID in Wallet and let your app or App Clip access it without leaving context; Apple doesn't create or see the documents, and your app receives only encrypted data.
- Present the Verify with Wallet button only on supported devices, and prepare a fallback verification view.
- Ask for identity information at the precise moment it's needed (not during account creation or before the process starts).
- Write a purpose string explaining why — a brief, complete sentence, direct and specific, sentence case, active voice, ending with a period (e.g., "Federal law requires this information to verify your identity and also to help [App Name] prevent fraud.").
- Ask only for data you actually need (an age threshold rather than current age or birth date); clearly indicate whether you'll keep the data and for how long (`PKIdentityIntentToStore`) — the system displays this in the verification sheet.
- Verification buttons use white letters on a black background (a `blackOutline` style adds contrast on dark backgrounds) with adjustable corner radius; multiline variants apply automatically when horizontal space is constrained.

| Button label | Use when |
|---|---|
| Verify Age | The transaction can complete after verifying age (e.g., making a car available to lease) |
| Verify Identity | The transaction can complete after verifying identity (e.g., car rental) |
| Continue | Part of a verification that also needs information Verify with Wallet doesn't provide (e.g., Social Security or phone number) |
| Custom label | The flow completes without additional steps but standard labels don't fit (e.g., government service signup) |

### Platform considerations
- Not supported in tvOS. No additional considerations for iOS, iPadOS, macOS, or visionOS.
- watchOS: passes appear in a scrolling card carousel (people can add passes even without a watch-specific app); tapping a pass reveals a scrolling details screen; information that doesn't fit the layout areas moves to the details screen. In every style, watchOS crops the strip image to the card's aspect ratio and may crop white space from other images.

### Resources
- PassKit: PKAddPassButton, PKAddPassesViewController, PKPassLibrary (backgroundAddPasses), PKIdentityButton, VerifyIdentityWithWalletButton, PKPaymentOrderDetails, PKIdentityIntentToStore; Pass; Wallet Passes; Wallet Orders; FinanceKit/FinanceKitUI; Pass Designer; Add to Apple Wallet guidelines.
