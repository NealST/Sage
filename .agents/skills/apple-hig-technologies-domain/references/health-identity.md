> Source: https://developer.apple.com/design/human-interface-guidelines/healthkit
> Source: https://developer.apple.com/design/human-interface-guidelines/researchkit
> Source: https://developer.apple.com/design/human-interface-guidelines/carekit
> Source: https://developer.apple.com/design/human-interface-guidelines/id-verifier

# Health, research, care & identity technologies

## HealthKit
HealthKit is the central repository for health and fitness data in iOS, iPadOS, and watchOS; supporting it lets your app ask permission to access and update people's health information.

If your app doesn't provide health and fitness functionality, don't request access to people's private health data.

### Best practices
- Request permission to access data and take all necessary steps to protect it; after receiving permission, maintain trust by clearly showing how you use the data.
- Provide a coherent privacy policy: you must supply a URL to a clearly stated policy during app submission (viewable from your App Store page).
- Request access to health data only when you need it — e.g., when people log their weight, not immediately after launch; context-related requests help people understand your intent, and since permissions can change, request every time access is needed.
- Clarify intent by adding descriptive messages to the standard permission screen: a few succinct sentences on why you need the information and how people benefit; don't build custom screens that replicate the system permission screen.
- Manage health data sharing solely through the system's privacy settings (Settings > Privacy); don't build in-app screens that affect the flow of health data.
- Activity rings: use the Activity ring element only for Move, Exercise, and Stand information — never replicate or modify rings for other data, and never show Move/Exercise/Stand progress in another ring-like element.
- Use Activity rings for a single person's progress only, and make it obvious whose progress is shown (label, photo, or avatar).
- Don't use Activity rings for ornamentation (never in labels or background graphics) or branding (never in your app icon or marketing materials).
- Maintain ring and background colors exactly — no filters, color changes, or opacity changes; design the surrounding interface to blend with the rings (e.g., enclose them in a circle) and scale them appropriately.
- Maintain ring margins: the element needs a minimum outer margin no less than the distance between rings; never let other elements crop, obstruct, or encroach on the margin or rings; to display rings in a circle, adjust the enclosing view's corner radius rather than applying a circular mask.
- Differentiate other ring-like elements from Activity rings using padding, lines, labels, color, or scale — mixing ring styles creates visual confusion.
- Provide app-specific information only in Activity notifications: don't repeat system-provided Move/Exercise/Stand updates and never show an Activity ring element in notifications; referencing Activity progress uniquely is fine.
- Apple Health icon: use only the Apple-provided icon (download from Apple Design Resources) — never create or mimic your own; display the name "Apple Health" close to it; make it no smaller than other health-related app icons in a view.
- Don't use the Apple Health icon as a button (compatibility indication only); don't alter its appearance (no corner-radius masking, circular shapes, borders, color overlays, gradients, shadows, or other effects); maintain minimum clear space of 1/10 of its height; don't composite it onto another graphic.
- Don't use the Apple Health icon within text or as a replacement for the terms Health, Apple Health, or HealthKit; don't display Health app images or screenshots (copyrighted — use an Activity ring element instead).
- Editorial: refer to the app as "Apple Health" or "the Apple Health app"; don't use the term HealthKit (it's developer-facing — say your app "works with the Apple Health app" or "uses data from the Apple Health app").
- Capitalize as "Apple Health" (uppercase A and H); all-caps only to conform to an established all-caps typographic style; use the system-provided translation of "Health" to match the device.

### Platform considerations
- Not supported in macOS, tvOS, or visionOS. No additional considerations for iOS, iPadOS, or watchOS.

### Resources
- HealthKit; HKActivityRingView; requestAuthorization(toShare:read:completion:); Protecting user privacy; Works with Apple Health badge; Apple Design Resources.

## ResearchKit
A research app lets people everywhere participate in important medical research studies; the ResearchKit framework provides predesigned screens and transitions for building an engaging custom research app.

These guidelines are informational, not legal advice — consult an attorney about applicable laws for a research app.

### Best practices
- Always show onboarding screens in this order: 1) Introduction, 2) Eligibility, 3) Informed consent, 4) Data permission. The screens aren't typically revisited, so clarity is essential.
- Introduction: clearly describe the subject and purpose of the study with a call to action; let existing participants log in quickly and continue an in-progress study.
- Determine eligibility as soon as possible (ineligible people shouldn't reach consent); present only requirements necessary for the study, in simple, straightforward language with easy information entry.
- Get informed consent: make sure participants understand the study before consenting; comply with App Store Guidelines and any institutional review board or ethics review board requirements; the section typically explains how the study works, participants' responsibilities, and obtains consent.
- Break a long consent form into digestible sections (data gathering, data use, potential benefits, possible risks, time commitment, how to withdraw), each with a simple high-level overview and an optional Learn More for detail; participants must be able to view the entire form before agreeing.
- If it makes sense, provide a quiz testing understanding (for questions that would otherwise be asked when consenting in person).
- After agreeing, collect the participant's signature and, if appropriate, contact information; most research apps email a PDF of the consent form.
- Request permission to access the participant's device or data (location, Health, etc.) and to send notifications: explain why for each, and don't request data that isn't critical to the study.
- Surveys: tell participants how many questions there are and roughly how long the survey takes; use one screen per question; show progress; keep surveys as short as possible (several short surveys work better than one long one).
- For questions needing explanation, use the standard font for the question and a slightly smaller font for explanatory text; tell participants when the survey is complete.
- Active tasks (speaking into the microphone, tapping fingers, walking, memory tests): describe how to perform the task in clear, simple language; explain requirements (particular time or circumstances); make sure participants can tell when the task is complete.
- Use a profile screen to help participants manage study-related personal data (edit data that changes during the study like weight or sleep habits, remind them of upcoming activities, provide an easy way to leave the study, and surface the consent document and privacy policy).
- Use a dashboard to show progress and motivate continued participation (daily progress, weekly assessments, activity results, and optionally comparisons with aggregated results from other participants); keep both profile and dashboard accessible at all times.

### Platform considerations
- Not supported in macOS, tvOS, visionOS, or watchOS. No additional considerations for iOS or iPadOS.

### Resources
- ResearchKit (Research & Care); ResearchKit GitHub project; Protecting user privacy.

## CareKit
People can use CareKit apps to manage care plans related to a chronic illness like diabetes, recover from an injury or surgery, or achieve health and wellness goals.

CareKit 2.0 contains CareKit UI (prebuilt, customizable views) and CareKit Store (a database schema for patients, care plans, tasks, and contacts stored on the patient's device), with seamless synchronization keeping the care plan up to date.

### Best practices
- Provide a coherent privacy policy (URL required during app submission); get permission before accessing data through iOS features and capabilities, and protect all data — whether entered into your app or obtained from the device.
- HealthKit integration: request access to health data only when needed (contextual requests); add descriptive messages to the standard permission screen (no custom replicas); manage sharing solely through Settings > Privacy.
- Motion data: with permission, use device motion to determine whether people are standing still, walking, running, cycling, or driving (plus step count, pace, and flights of stairs); custom physical-therapy data (flexibility, range of motion, ambulatory capability) can come from ResearchKit tasks using device sensors.
- Photos: with permission, access the camera and photos so people can share treatment progress pictures with a care team (e.g., periodic photos of an injury).
- ResearchKit integration: incorporate surveys, tasks, and charts, and the informed consent module for permission to collect and share data.
- Use the three CareKit UI view categories for their intended purposes only: tasks (present prescribed actions like medication or physical therapy; log symptoms and other data), charts (graphical data showing treatment progress), and contacts (contact information with phone, message, and email communication plus a location map link).
- Each view has a header (text, optional symbol, disclosure indicator, optional bottom separator) with a vertical stack of content subviews below; CareKit UI handles layout constraints, so adding subviews won't break existing ones.

Task information:

| Information | Required | Description / example |
|---|---|---|
| Title | Yes | A word or short phrase introducing the task — "Ibuprofen" |
| Schedule | Yes | When the task must be completed — "Four times a day" |
| Instructions | No | Detailed instructions, recommendations, warnings — "Take 1 tablet every 4–6 hours (not to exceed 4 tablets daily)." |
| Group ID | No | Identifier for grouping similar tasks — a category like medication or exercise |

- Choose among the five task styles: simple (one-step task; header with title, subtitle, and a completion button — no content stack), instructions (simple task plus informative text like "Take on an empty stomach"), log (button to log events with automatic timestamps), checklist (multistep task as a list, each item with a description and done button, optional instructional text below), grid (multistep task as a compact button grid; the only style exposing its underlying collection view for custom UI).
- Consider color to reinforce meaning (one color for medications, another for physical activities) but never use color as the only way to convey information.
- Combine accuracy with simplicity when describing tasks: use a medication's marketing name rather than its chemical description, and minimize words when context already clarifies meaning.
- Consider supplementing multistep or complex tasks with videos or images to help people avoid mistakes.
- Charts (bar, scatter, and line styles, each with descriptive title, subtitle, axis markers, and a data set; current and historical data update automatically): highlight narratives and trends (e.g., correlation between medication taken and pain level) to encourage adherence.
- Label chart elements clearly and succinctly — short labels without repetition (use "BPM" in the axis label, not on every point); use distinct colors, not shades of the same color, with sufficient contrast; add a legend when colors aren't immediately clear.
- Clearly denote units of time (seconds through years — in value labels, an axis label, or elsewhere); consolidate large data sets for readability; offset or restructure data when small values would get lost among large ones.
- Contact views (simple and detailed styles): consider color to help people categorize care team members at a glance.
- Notifications (medication reminders, task reminders, badge for unread caregiver messages): minimize them — use them sparingly and coalesce multiple items into one — and consider a detail view that lets people act immediately (e.g., mark pending tasks complete) without opening the app.
- Symbols: prefer CareKit-provided symbols (phone, messaging, envelope, clock); in grid views, custom symbols (via SF Symbols) can represent unique content — design a symbol closely related to your app or health and wellness, never purely decorative or a corporate logo.
- Incorporate refined, unobtrusive branding (color, communication style); people don't want advertising distracting them from their care plan.

### Platform considerations
- Not supported in macOS, tvOS, visionOS, or watchOS. No additional considerations for iOS or iPadOS.

### Resources
- CareKit (CareKit UI, CareKit Store, Chart Interfaces); HealthKit; ResearchKit; Core Motion; UIImagePickerController; SF Symbols.

## ID Verifier
ID Verifier lets your iPhone app read mobile IDs in person without requiring external hardware; beginning in iOS 17, iPhone can read ISO18013-5 compliant mobile IDs for in-person verification (e.g., venue staff verifying customers' ages).

Customers present only the minimum data needed — without handing over their ID card or showing their device — while Apple provides the key components of certificate issuance, management, and validation.

### Best practices
- Choose the right request type: a Display Only request shows data (name or age alongside the photo portrait) in system-provided UI on the requester's iPhone for visual confirmation — the data stays in the system UI and isn't transmitted to your app; use a Data Transfer request only when you have a legal verification requirement and need to store or process information (requires an additional entitlement).
- Ask only for the data you need — people lose trust when asked for more (verify an age threshold rather than requesting current age or birth date).
- If your app qualifies, register for ID Verifier via Apple Business Register so your official organization name and logo appear on customers' devices during verification.
- Provide a button that initiates verification: "Verify Age" for a simple age check, "Verify Identity" for a detailed identity data request; avoid symbols that specify a communication type (NFC, QR codes) and never include the Apple logo.
- In a Display Only request, help the person using your app give feedback on the visual confirmation — e.g., "Matches Person" and "Doesn't Match Person" buttons that return an approved or rejected value in the response.

### Platform considerations
- Not supported in iPadOS, macOS, tvOS, visionOS, or watchOS. No additional considerations for iOS.

### Resources
- ProximityReader: Verifier API (MobileDriversLicenseDisplayRequest, MobileDriversLicenseDataRequest, MobileDriversLicenseRawDataRequest, ageAtLeast(_:)); Apple Business Register; IDs in Wallet; Get started with ID Verifier.
