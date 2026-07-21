# iOS 27 Feature Ideation — Marauders

*WWDC 2026 (June 8, 2026) feature integration plan for the offline AR monument tour app.*
*Current deployment target: iOS 18.0 — every idea below must be gated with `#available(iOS 27, *)` / `LanguageModelSession.isAvailable` so the app keeps running on older devices.*

---

## Why iOS 27 is unusually good for THIS app

Marauders' whole identity is **offline-first**: download a package once, then AR + audio + stories with zero network at the monument. iOS 27's headline developer story is **on-device intelligence** (Foundation Models got a bigger model, vision input, tool calling, 32k+ context, on-device fine-tuning). That means our single biggest online-only dependency — live Q&A through the Azure `/ask` endpoint — can finally move on-device and work in airplane mode, in four languages, standing in front of the actual monument. Everything else (Liquid Glass, Live Activities, landscape Dynamic Island) layers demo-visible polish on top.

The hook for judges: *"Ask the Taj Mahal anything — with no signal."*

---

## 1 · Foundation Models (the flagship)

The seam already exists: `AnswerEngine` is a protocol, and `FoundationModelsAnswerEngine`
(`Marauders/Core/Services/AnswerEngine.swift:87`) is a stub that currently throws
*"On-device Q&A requires the iOS 27 FoundationModels SDK."* We wrote our own abstraction before Apple shipped theirs — now we fill it in.

### 1a. Offline tour guide Q&A — implement `FoundationModelsAnswerEngine` ⭐ must-ship
- Create a `LanguageModelSession` per tour, with `instructions` built from the installed
  package's `tour.json`: monument overview, the current checkpoint's intro, nugget texts in the
  selected language (`InstalledTour` already exposes all of this — no new data needed).
- Register a **tool** (`Tool` protocol, new full tool-calling in iOS 27) that looks up any
  checkpoint/nugget content from `PackageStore` on demand, so the model can pull the *right*
  story instead of us stuffing the whole package into the prompt.
- Wire it as the first link in a graceful chain:
  **on-device model → Azure `/ask` with `skipAudio` → bundled fallback note** — `VoiceQuestionService`
  and `TajAIInsightStore` both already consume `AnswerEngine`, so this is one init change each.
- Speak the answer with `AVSpeechSynthesizer` (on-device TTS) to keep the voice experience offline.
- Availability: A17 Pro+ (iPhone 15 Pro and later). Check `LanguageModelSession.isAvailable`,
  fall through to Azure otherwise — the chain above gives every device the best it can do.

### 1b. Multimodal "What am I looking at?" ⭐ demo-wow
iOS 27's model accepts **images alongside text** and can call Vision framework tools (OCR!) on-device.
- In `ARCameraView`, add a "What's this?" button: snapshot the ARKit camera frame, send it to the
  session with the checkpoint context → the model identifies the detail ("that's pietra dura inlay…").
  This answers questions about things that *aren't* one of our AR targets — today those get silence.
- OCR tool + Taj Mahal = reading the Quranic calligraphy on the Great Gate and explaining it. That is
  a genuinely magical 10-second demo.

### 1c. `@Generable` structured generation — quiz & trip journal
- `@Generable struct QuizQuestion { var prompt: String; var choices: [String]; var answerIndex: Int }` —
  generate a 5-question quiz from the chapters the visitor actually completed
  (`TajTourProgressStore` knows which). Show it at tour end; ties into the existing progress ring.
- Generate a shareable **trip journal** paragraph from visited chapters + revealed nuggets
  (structured output → we control the format, no parsing).

### 1d. Dynamic Profiles + language
- Use iOS 27 **Dynamic Profiles** to swap instructions per checkpoint and per `AppLanguage`
  mid-session (hi/fr/es prompts) instead of rebuilding the session. Verify non-English quality in
  beta; if weak, keep non-English on the Azure path — the engine chain makes that free.

### 1e. Stretch (flag, don't promise): on-device LoRA fine-tuning
iOS 27 can train adapters on-device (<10 min on A17 Pro, 50MB cap). A monument-corpus adapter is a
cool story but low ROI for judging week — note it in the pitch as roadmap, don't build.

---

## 2 · Cosmetic — Liquid Glass (iOS 27 refinements)

iOS 27 makes Liquid Glass adoption effectively mandatory (Xcode 27 disables the legacy deferral
flags) and adds a **system-wide glass opacity slider** — so adopting properly is both required and
free polish. Concrete targets in our UI:

- **`NuggetRevealCard`** → `.glassEffect()` card over the blurred AR viewfinder; the flashcard
  literally floats on glass above the monument. Best single cosmetic change we can make.
- **AR HUD chips** (`"LIVE AR"` label, secrets-progress pill, browse fallback panel in
  `ARCameraView`) → glass capsules instead of the current opacity-based fills, so they respect the
  user's system glass slider.
- **`GlassEffectContainer` + `.glassEffectID` morphing**: the shutter-flash → reveal-card transition,
  and the Taj map checkpoint pin → `TajCheckpointDetailView` sheet. Morphing IDs give us the
  "hundreds of lines for free" animation between pin and detail card.
- **`.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)`** in `BrowseModeView` and
  `ExploreView` — content-first scrolling.
- **`.prominent` tab role** for the tour/AR tab in `MainTabView` — the one action we want thumbs on.
- **`.swipeActions` on any view** (no longer List-only): swipe a nugget row in Browse Mode to
  replay audio / mark heard.
- **`.reorderable()`**: let users reorder their bookings list — small, native, satisfying.
- Housekeeping: our custom `Theme` fills must not fight the glass system — audit any
  hard-coded dark overlays for the new "improved background diffusion" contrast rules, and respect
  the existing `Motion`/reduce-motion work when adding morphs.

---

## 3 · Live Activities

Two natural activities, both of which work **fully offline** (ActivityKit local updates need no
push server — on-brand for us):

### 3a. "Tour in progress" Live Activity ⭐ must-ship
Started by `TourContainerView` when a tour begins, ended on exit:
- **Lock screen**: monument name, current chapter, progress ("2/6 chapters · 4 secrets found"),
  now-playing nugget title with an audio bar. Data sources already exist:
  `TajTourProgressStore` (chapter progress), `NuggetAudioPlayer` (playing state), `TourSession`
  (checkpoint). This is the screen visitors see every time they pocket the phone between checkpoints —
  which on a walking tour is *constantly*.
- **Apple Watch**: add `.supplementalActivityFamilies([.small])` and branch on `activityFamily` —
  chapter progress on the wrist while the phone stays in the pocket listening. (New emphasis in the
  WWDC26 "Live Activities essentials" session.)

### 3b. Package download Live Activity
`PackageStore.downloadProgress` already publishes progress for the ~15MB package download.
Mirror it into a Live Activity (progress bar, monument thumbnail, "Ready for offline" completion
state) so users can leave the app while their tour downloads at the hotel. Small build, real utility.

---

## 4 · Dynamic Island

The Dynamic Island presentations of the 3a activity — this is where the demo lives:

- **Compact**: monument glyph (leading) + live audio waveform / progress ring (trailing) while
  narration plays.
- **Expanded** (long-press): chapter name + progress ring + **Replay / Pause narration** buttons
  (drive `NuggetAudioPlayer` via App Intents) + current nugget thumbnail from
  `installed.displayURLs(for:)`.
- **Minimal**: tiny progress ring.
- **iOS 27 landscape support is *specifically* our scenario**: iOS 27 shows compact/minimal views
  in **landscape** for the first time, and AR camera mode is exactly where users hold the phone
  landscape. Handle the new width-constrained layout (`isDynamicIslandLimitedInWidth` environment
  value) so the waveform collapses to a dot when constrained. We'd be using an iOS 27 API in the
  precise situation it was designed for — worth saying out loud to judges.

---

## Bonus round (cheap, judge-visible extras)

- **Visual Intelligence via App Intents (iOS 27)**: register Marauders as an image-search provider —
  a user highlights any Taj Mahal photo anywhere in the OS and our tour appears as a result,
  deep-linking into `MonumentInfoView`. Discovery story for the pitch.
- **App Intents + Siri**: "Continue my Taj Mahal tour" / "How many secrets have I found?" —
  `TajTourProgressStore` answers in one line; the new App Intents Testing framework validates it
  without UI automation.
- **New systemwide dictation (iOS 27)** improves our text-question fallback for free — mention, no code.

---

## Suggested build order (hackathon-time honest)

| # | Item | Effort | Wow | Notes |
|---|------|--------|-----|-------|
| 1 | 1a on-device Q&A engine | ~½ day | ★★★ | Fills existing stub; offline story complete |
| 2 | 3a + 4 tour Live Activity + Island | ~½ day | ★★★ | New widget extension target; offline-safe |
| 3 | 2 glass pass on reveal card + HUD | ~2 h | ★★ | Pure SwiftUI modifiers |
| 4 | 1b multimodal "What's this?" | ~½ day | ★★★ | Needs A17 Pro test device |
| 5 | 3b download activity | ~2 h | ★ | Reuses `downloadProgress` |
| 6 | 1c quiz / journal | ~3 h | ★★ | Pure `@Generable`, no UI risk |
| 7 | Bonus intents | ~2 h | ★ | Pitch-line material |

**Device/runtime caveats**: Foundation Models needs A17 Pro+ hardware (not the simulator's strong
suit) and iOS 27 beta installed; everything must stay `#available`-gated so the iOS 18 build keeps
working for whichever phone is on the demo table. The current build machine has Xcode 27 beta
(27A5218g) but no iOS 27 simulator runtime or signing identity — plan to build items 1–4 on a
developer's machine with a beta device.

---

## Sources

- [Apple Newsroom — next generation of Apple Intelligence, Siri AI](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/)
- [Apple Newsroom — new intelligence frameworks and tools](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/)
- [Apple Developer — What's new in the Foundation Models framework (WWDC26 session 241)](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Apple Developer — Live Activities essentials (WWDC26 session 223)](https://developer.apple.com/videos/play/wwdc2026/223/)
- [Apple Developer — WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [ChatForest — Foundation Models iOS 27 builder guide (API surface, @Generable, tools, fine-tuning)](https://chatforest.com/builders-log/apple-foundation-models-ios-27-on-device-llm-api-builder-guide/)
- [DEV — Foundation Models opened to any LLM provider](https://dev.to/arshtechpro/wwdc-2026-apple-just-opened-the-foundation-models-framework-to-any-llm-provider-5ejn)
- [DEV — What's new in SwiftUI (WWDC26 breakdown)](https://dev.to/arshtechpro/wwdc26-whats-new-in-swiftui-a-developers-breakdown-1333)
- [byteiota — iOS 27 makes Liquid Glass mandatory](https://byteiota.com/ios-27-makes-liquid-glass-mandatory-act-before-april-2027/)
- [byteiota — Foundation Models multimodal + Python SDK](https://byteiota.com/apple-foundation-models-wwdc-2026-multimodal-python-sdk/)
- [The Swift Dev — Landscape Dynamic Island Live Activities](https://www.theswift.dev/posts/make-a-live-activity-fit-the-landscape-dynamic-island/)
- [Tom's Guide — iOS 27 everything announced](https://www.tomsguide.com/phones/iphones/ios-27-is-official-all-the-new-upgrades-and-features-announced-at-wwdc-2026)
- [TechCrunch — WWDC 2026 everything announced](https://techcrunch.com/2026/06/09/wwdc-2026-everything-announced-on-siri-ai-os-27-apple-intelligence-and-more/)
- [MacRumors — Platforms State of the Union AI & developer tools](https://www.macrumors.com/2026/06/09/apple-outlines-major-ai-and-developer-tool-updates/)
