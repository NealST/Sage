> Source: https://developer.apple.com/design/human-interface-guidelines/generative-ai
> Source: https://developer.apple.com/design/human-interface-guidelines/machine-learning
> Source: https://developer.apple.com/design/human-interface-guidelines/siri
> Source: https://developer.apple.com/design/human-interface-guidelines/maps

## Generative AI
Generative AI empowers you to enhance your app or game with dynamic content and offer intelligent features that unlock new levels of creativity, connection, and productivity.

### Best practices
Responsibility and control:
- Design responsibly: consider the direct and indirect impacts of AI features on people, systems, and society. The same input can produce different outputs and you can't anticipate every request — orient the process around experiences that are inclusive, designed with care, and protect privacy.
- Keep people in control: honor in-scope requests when the expected output is clear, handle sensitive content carefully, let people dismiss unwanted content and revert or retry transformations, and clearly identify when and where you use AI.
- Ensure inclusivity: models trained on common data can replicate biases and stereotypes — ask people for the personal or cultural details a feature needs instead of inferring them, seek clarity before assuming (e.g., gender identities, relationship types), and test across a diverse set of people.
- Offer generative features only where they provide clear, specific value like time savings, improved communication, or enhanced creativity.
- Keep the experience great when generative features are unavailable or declined; offer a non-AI fallback when possible (Genmoji complements regular emoji; summarization complements reading notifications).

Transparency:
- Communicate where your app uses AI; never trick people into thinking they're interacting with or viewing human-authored content; align disclosure with regulations in every region you serve.
- Set clear expectations: offer a brief tutorial at introduction, curated starter suggestions for open-ended features, known limitations up front, guidance for getting good results, and explanations for why inferior results occur.

Privacy:
- Match the model type to the feature: on-device models keep information local, respond quickly, and work offline; server-based models offer more processing power and larger context. Process as much locally as possible, minimize what's shared, and be transparent about what's sent to servers, stored off-device, or used for training.
- Ask permission before using personal information or usage data; use the minimum needed, offer a clear opt-out, get explicit permission for storage or model improvement, vet third parties' privacy practices, and remember model outputs can contain sensitive information and kids' apps face stricter rules.
- Explain the benefits of sharing data concisely, specifically, and understandably, and state whether personal information is used for training and improvement.

Models and datasets:
- Evaluate model capabilities hands-on as early as possible; some models are unavailable depending on device compatibility, network access, or battery level (Foundation Models requires an Apple Intelligence-capable device).
- Choose or create datasets intentionally: diverse subject representations, known provenance, proper licenses for data you don't own, appropriate choices when using people's data, and time set aside to test for bias and misinformation.

Inputs:
- Guide people toward good results with diverse, predefined example inputs.
- Minimize hallucinations: scope generation requests carefully, avoid requesting factual information unless the model has verified, up-to-date sources, and avoid AI-generated content where a hallucination could misinform or harm; clearly communicate that AI-generated content may contain errors.
- Consider consequences and get permission before irreversible or problematic tasks; don't automate destructive actions (deleting photos) or hard-to-undo ones (purchases on someone's behalf); confirm significant actions; adhere to model usage policies and AI regulations in each locale.

Outputs:
- Make refining easy: surface Edit, Undo, Retry, and Adjust near generated content, and acknowledge when corrections take effect.
- Coach people past blocked or undesirable results with example requests (e.g., Image Playground: "Unable to use that description").
- Reduce harmful outcomes proactively: test out-of-scope, unrelated, poorly phrased, vague, ambiguous, personal, sensitive, controversial, and adversarial requests; use findings to improve the model, prevention, and responses.
- Strive to avoid replicating copyrighted content: build on models with protections, curate inputs (e.g., pre-approved prompts), and explicitly instruct the model to avoid mimicking certain content or styles.
- Factor latency into design: generative models are slower than non-generative ones (ARKit body tracking, Vision) — design a loading experience or generate in the background.
- Give specific, reassuring feedback during generation ("Finding substitutions for ingredients," not "Processing…"); on failure, describe what happened in plain language and offer a clear next step.
- Consider offering multiple meaningfully different results to choose among (as Image Playground does).

Continuous improvement:
- Improve the model over time: frequent small updates (e.g., blocked-word lists) independent of app releases; significant changes planned around app updates; fine-tuning, retesting, and prompt engineering when upgrading base models; retraining custom models with more data.
- Let people voluntarily share feedback on outputs — quick thumbs-up/thumbs-down plus a detailed option for complicated issues, placed clearly without interrupting the flow — and resolve issues quickly to build trust.
- Design flexible, adaptable features: separate the model from the user experience so models can be swapped as capabilities evolve.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources
- Foundation Models, Core AI, Apple Intelligence and machine learning

## Machine learning
Machine learning enables apps and games to learn from data and usage patterns, letting you improve existing experiences and create engaging new ones.

### Best practices
Define the role machine learning plays in your app — it drives every other design decision:
- Critical vs complementary: complementary if the app still works without it (QuickType suggestions); critical if not (Face ID). The more central the feature, the more people expect accuracy and reliability.
- Private vs public: the more sensitive the data, the more serious an inaccurate result (a health app's wrong recommendation vs a music app's disliked artist); regardless of sensitivity, always protect privacy.
- Proactive vs reactive: proactive results arrive unrequested (Siri Suggestions), so tolerance for low quality is lower and more data may be needed; reactive results respond to people's actions (QuickType).
- Visible vs invisible: visible features let people judge reliability as they choose among results (Image Playground); invisible ones improve silently (News topic suggestions) but struggle to communicate reliability and gather feedback.
- Dynamic vs static: dynamic features improve through interaction and usually incorporate calibration and feedback; static features change only on app update.

Explicit feedback:
- Request explicit feedback only when necessary — people must act to provide it — and always keep it voluntary; prefer implicit feedback.
- Describe each option and its consequence in simple, direct language ("Suggest less pop music," "Mute politics for a week"); avoid imprecise terms like "dislike."
- Icons may clarify an option but never stand alone; consider multiple, progressively more specific options.
- Act immediately on explicit feedback and persist the change (hide unwanted content everywhere in the app); use it to fine-tune when and where results appear, not just what they are.

Implicit feedback:
- Secure people's information — implicit feedback can capture sensitive behavior; tell people how your app gets and shares information and give them ways to restrict its flow.
- Don't let feedback shrink exploration: pure interest-matching discourages people from discovering new things.
- Combine multiple feedback signals to avoid misreading intent (a viewed, shared, album-added photo isn't necessarily liked).
- Withhold recommendations derived from private or sensitive implicit feedback — people share accounts and devices.
- Prioritize recent feedback (Face ID uses recent facial input), falling back to historical when recent isn't available.
- Update predictions at a cadence matching the person's mental model: typing suggestions immediately, song recommendations not continuously.
- Expect implicit feedback to shift when the UI changes, even trivially (button relocation); account for it when interpreting data.
- Beware confirmation bias: implicit feedback reflects only what people can see and do — don't rely on it alone.

Calibration (people provide the information a feature needs to function):
- Use calibration only when the feature can't work without it; collect the minimum and keep it secure.
- Explain why the information is needed, emphasizing what the feature does, not how it works.
- Calibrate once, early in the experience (exception: features that calibrate to objects, such as each new baseball field).
- Keep it quick and easy: prioritize a few important pieces of information and infer the rest; never ask for information people would have to look up or actions that are difficult to perform.
- Give an explicit goal and visible progress (Face ID's tick marks); provide immediate, blame-free assistance if progress stalls; confirm success; allow canceling at any time without judgment.
- Let people update or remove calibration information outside the calibration flow.

Mistakes:
- Anticipate mistakes, help people handle them, and learn from them when learning improves the app; the patterns that help are limitations, corrections, attribution, confidence, and feedback.
- Match corrective actions to the mistake's significance (an annoying keyboard suggestion vs a route that misses a flight).
- Make frequent or predictable mistakes easy to correct, and keep the feature current with evolving interests and domain knowledge (e.g., entertainment trends).
- Address mistakes without complicating the UI — a wrong attribution magnifies the original mistake.
- Be extra careful in proactive features, where people have less patience and feel less control; remember that improving one area can degrade another (dogs vs cats recognition).

Corrections:
- Provide familiar, easy correction paths and show the steps your app took so people can refine them (Photos highlights its auto-crop controls).
- Provide immediate value when corrected and persist the change; let people correct their corrections.
- Balance the feature's benefit against correction effort — people abandon automation that's harder than doing the task manually.
- Never rely on corrections to make up for low-quality results; learn from corrections only when they lead to higher-quality results.
- Prefer guided corrections (pick from alternative text completions) over freeform ones (manual crop adjustment); combining both is fine.

Multiple options (for suggestions, requests, and corrections):
- Offer diverse options (Maps' toll-free, scenic, and highway routes) but not too many — each adds cognitive load; keep them on one screen when possible.
- List the most likely option first, ranking by confidence or context (time of day, location); preselect it when that helps people act quickly.
- Make options easy to distinguish: brief descriptions that highlight differences; scannable categories when there are many.
- Learn from selections to refine future options.

Confidence:
- Verify that confidence values correspond to result quality (review thresholds, compare app versions) before conveying them; if unsure, don't convey confidence at all.
- Translate confidence into concepts people understand: "Because you listen to pop music" beats "97% match"; prefer ranking, semantic categories ("high chance"/"low chance"), or actionable suggestions ("This is a good time to buy") over raw numbers.
- Display statistical values only where people expect them (weather, sports statistics, polling).
- Adapt presentation to thresholds (Photos shows face matches directly at high confidence, asks for confirmation when lower) and suppress low-confidence results — especially in proactive features — below a set threshold.

Attribution:
- Use attributions to encourage behavior change, minimize mistakes' impact, build mental models, and promote trust; they help people distinguish among options ("New books by authors you've read").
- Balance specificity: overly specific attributions feel intrusive and add interpretation work; overly general ones feel generic and impersonal.
- Keep attributions factual and objective ("Because you've read nonfiction," not "Because you love nonfiction"); never imply judgment about emotions, preferences, or beliefs.
- Avoid technical and statistical jargon except when the result itself is statistical (weather, sports, polling, scientific data).

Limitations:
- A limitation becomes a defect when it mismatches expectations — set expectations before use (marketing or in-context descriptions for serious but rare limitations; attributions for mild ones).
- Demonstrate how to get good results: placeholder text (Photos' "Photos, People, Places…"), in-flow coaching (Memoji's lighting and distance tips), and alternative suggestions instead of empty results.
- Explain why poor results happen (Memoji doesn't work well in the dark), and consider telling people when a limitation is resolved so they can return to interactions they had avoided.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS.

### Resources
- Create ML, Core ML, Apple Intelligence and machine learning

## Siri
People use Siri — a personal assistant available throughout the system and in the apps they use — to help them with the things they need to find, know, or do every day.

Integration: apps expose actions (intents) and content (entities) to Apple Intelligence with the App Intents framework, making them available to Siri, Spotlight, and the Shortcuts app. Apps in common domains (email, music, photos) can adopt app schemas — preset templates the system already understands — for natural conversation and deeper contextual understanding. Siri AI, powered by Apple Intelligence, lets people start an app's actions from anywhere in the system, interact with onscreen content ("Add this photo to my Landscapes album"), and reach deep features by voice. Apps can also annotate views with app entities, donate entities to the Spotlight index, and donate actions as intents so Siri can anticipate and surface them at appropriate times.

### Best practices
- Identify your app's most popular actions and the contexts where they occur (hands-free use, particular devices) to prioritize what to expose as app intents and entities.
- Use familiar terms for content and actions (track, song, or podcast) so voice interaction feels natural.
- Offer relevant content — recent searches, favorites, bookmarks, wishlists — rather than your entire catalog (whole-catalog access is justified for email or messaging).
- Don't advertise: no ads, marketing, or in-app purchase sales pitches in content Siri delivers.
- Provide custom responses only when built-in responses don't meet your needs.

Dialogue for custom responses:
- Write clear, descriptive dialogue that conveys what happens when Siri performs the action; customize follow-up questions ("Which soup?" not "Which one?").
- Keep responses succinct: use conversation context to strip details, and avoid unnecessary words and humor, which irritate on repeat.
- Provide responses Siri can deliver both audibly and visually; the spoken version must stand alone without visual support.
- Design inclusive interactions: avoid unnecessary pronouns ("Who should I send it to?" not "What's his or her name?").
- When the full option list is too long to read, ask an open-ended question ("What kind of shoes are you interested in?").
- Keep responses device-independent; if you must reference a device, make sure it's accurate and makes sense in context.
- Omit your app's name from responses — the system already provides verbal and visual attribution.
- Use appropriate language, respect parental controls (rating-based restrictions), and remember Siri may speak responses aloud where others can hear.
- Make errors specific and helpful ("Sorry, we're out of chicken noodle soup," not "Sorry, we can't complete your order").

Editorial rules:
- Refer to Siri by name; never use pronouns like she, him, or her.
- Never impersonate Siri, reproduce its functionality, or provide responses that appear to come from Apple; don't use reserved phrases like "Call 911" or "Hey Siri."
- Localize only the word "Hey" in "Hey Siri" — Siri, as an Apple trademark, is never translated:

| Locale | "Hey Siri" | Locale | "Hey Siri" |
|---|---|---|---|
| ar_AE, ar_SA | يا Siri | it_CH, it_IT | Ehi Siri |
| da_DK, sv_SE | Hej Siri | ja_JP, de_AT, de_CH, de_DE, tr_TR | Hey Siri |
| en_AU, en_CA, en_GB, en_IE, en_IN, en_NZ, en_SG, en_US, en_ZA | Hey Siri | ko_KR | Siri야 |
| es_CL, es_ES, es_MX, es_US | Oye Siri | ms_MY | Hai Siri |
| fi_FI | Hei Siri | nb_NO, no_NO | Hei Siri |
| fr_BE, fr_CA, fr_CH, fr_FR | Dis Siri | nl_BE, nl_NL | Hé, Siri |
| | | pt_BR | E aí Siri |
| | | ru_RU | привет Siri |
| | | th_TH | หวัดดี Siri |
| | | zh_CN | 嘿Siri |
| | | zh_HK | 喂 Siri |
| | | zh_TW | 嘿 Siri |

### Resources
- App Intents, App schema domains, Apple Intelligence and Siri AI, App Shortcuts, Snippets

## Maps
A map displays outdoor or indoor geographical data in your app or on your website, supporting familiar interactions like zooming, panning, and rotation, plus annotations, overlays, and routing in standard, satellite, or hybrid views.

### Best practices
- Make your map interactive — people expect to zoom and pan; noninteractive elements that obscure the map fight those expectations.
- Pick an emphasis style: default (fully saturated; suits standard apps and keeps visual alignment with the Maps app) or muted (desaturated; makes information-rich custom content stand out).
- Help people find places with search plus category filters (a mall map filtering by clothing, electronics, jewelry, toys).
- Clearly identify selected elements with distinct styling such as an outline and color variation.
- Cluster overlapping points of interest into a single pin that progressively expands as people zoom in.
- Keep the Apple logo and legal link visible: temporary covering is fine, permanent covering is not. Use 7 points of padding on the sides and 10 points above and below; keep them fixed to the map rather than moving with your interface; if a custom element moves (a bottom card), position them 10 points above its lowest resting position. They aren't shown on maps smaller than 200x100 px.

Custom information:
- Match annotations to your app's visual style; the default marker is a red tint with a white pin icon, and the icon can be a string (keep it to two or three characters for readability) or an image like a logo.
- Make standard map features (points of interest, territories, physical features) independently selectable with custom appearance and information.
- Choose overlay levels deliberately: above roads (default — people still sense what's beneath) vs above labels (fully abstracts or hides the map below).
- Ensure enough contrast between custom controls and the map: use a thin stroke or light drop shadow, or blend modes on the map area.

Place cards:
- Present rich place information (hours, phone, address) in a place card when someone selects a place — directly in your map for the places you specify, or for system features like points of interest and territories to give context; on the web, embed a map that displays a place card for a single place by default.
- Styles: automatic (system decides based on map size); callout (popover next to the place — full for rich detail, compact to save space); caption (an "Open in Apple Maps" link); sheet. The full callout appears as a popover on iPadOS and macOS but as a sheet on iOS.
- Match the style to your map's context — a small map with many annotations suits the compact callout; ensure content stays viewable across devices and window sizes (set a minimum width for full callouts).
- Avoid duplicating information your app or website already shows — compact callout or caption may complement better.
- Keep the selected location visible when a place card is open by setting an offset for the card.
- Outside a map (search results, store locators): use location cues like place names and addresses with a "more details" button, or a map pin icon; if the place card isn't displayed within a map view, it must include a map.

Indoor maps (venues like shopping malls and stadiums):
- Adjust detail by zoom level: show rooms and buildings at every level, progressively adding detail (an airport shows terminals and gates when zoomed out; stores and restrooms when zoomed in).
- Differentiate features with color plus icons so people quickly find areas, stores, and services.
- Offer a floor picker for multi-level venues, with concise floor numbers (a list of numbers, not names).
- Include surrounding areas for context, dimmed and distinctly colored to read as supplemental; support routing to nearby transit (bus stops, train stations, parking) and consider a quick handoff to Apple Maps.
- Limit scrolling outside your venue so people don't get lost: keep at least part of the map onscreen and adjust scroll limits by zoom level.
- Make the indoor map feel like a natural extension of your app — don't replicate the appearance of Apple Maps.

### Platform considerations
- No additional considerations for iOS, iPadOS, macOS, tvOS, or visionOS.
- watchOS: maps are static snapshots placed at design time; the displayed region isn't interactive (tapping opens the Maps app). Fit the map element to the screen without scrolling, show the smallest region that encompasses the points of interest, and add no more than five annotations.

### Resources
- MapKit, MapKit JS, Indoor Mapping Data Format
