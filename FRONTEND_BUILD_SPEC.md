# FRONTEND BUILD SPEC — Marauder's Monument Guide (iOS / SwiftUI)
**Audience: the Swift developer AND any AI coding agent they feed this to.**
**Status of the other half: the backend is BUILT, DEPLOYED, and VERIFIED. This
doc is the contract your app builds against. Nothing here is aspirational.**

---

## 0. How to read this file
- Sections marked **[CONTRACT]** are exact and must not be changed — they mirror
  a running backend. Field names, types, endpoints: copy them verbatim.
- Sections marked **[BEHAVIOR]** specify what the app must *do*; implement idiomatically.
- Sections marked **[RATIONALE]** explain *why* (for the human; an AI can skip).
- Each component ends with **Acceptance:** — a checkable definition of done.
- Build order and priorities are in §10. If time is short, cut from the bottom up.

---

## 1. What you are building (one paragraph)
An offline-first AR + voice guided tour. The user taps their (mocked) District
ticket → the app downloads ONE package for a monument → after that the core tour
needs zero network. Three screens: a Marauder's-Map of checkpoints, an AR camera
that recognises physical targets and plays audio "nuggets," and an info screen.
One live online feature: ask a spoken question, get a spoken grounded answer.

---

## 2. Backend contract [CONTRACT]

**Base URL** — make this a single config constant, two presets:
```
enum API {
    // DEMO: run the backend on a Mac, phone on same hotspot. Primary path.
    static let base = URL(string: "http://<MAC-LAN-IP>:8000")!
    // Fallback / "it's live on Azure" pitch. Higher latency from India (~6-9s).
    // static let base = URL(string: "https://marauders-backend.azurewebsites.net")!
    static let appKey = "<APP_KEY from backend/.env — hand-carried, do not hardcode in git>"
}
```
Auth: send header `X-App-Key: <appKey>` on `/ask` (and `/admin/*`).
`/packages/*` and `/health` are open (no header).

**Endpoints you call:**

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET | `/packages/{monumentId}.zip` | download the offline package (once) | none |
| POST | `/ask` | live voice Q&A (online only) | X-App-Key |
| GET | `/health` | connectivity check | none |

**POST /ask** — request body (send `text` OR `audioBase64`, not both):
```json
{ "monumentId": "taj_mahal", "checkpointId": "cp_main_platform",
  "lang": "en",            // "en" | "hi"
  "text": "why does the marble glow?",   // OR:
  "audioBase64": "<base64 m4a/wav/mp3 from the mic>" }
```
response:
```json
{ "question": "why does the marble glow?",
  "text": "Because Makrana marble is translucent…",
  "audioBase64": "<base64 mp3 — decode and play>" }
```
Latency budget: ~4–5s on LAN. Show a listening/thinking state; never block the UI.

---

## 3. Package & data model [CONTRACT]

`GET /packages/taj_mahal.zip` → unzip to app support dir. Contents:
```
tour.json            # the whole tour: checkpoints, nuggets, text, audio paths, gps
audio/*.mp3          # every nugget + checkpoint-intro, pre-rendered EN + HI
targets/*.jpg        # AR reference images (also the print masters)
```
After unzip, resolve `audio/...` and `targets/...` paths against the unzip dir.
**The core tour reads only local files. Do not call the network to play a nugget.**

### tour.json shape — exact Codable structs (use verbatim):
```swift
// A localized/paths map: {"en": "...", "hi": "..."}. 5-language-ready.
typealias LangMap = [String: String]
extension LangMap { func v(_ lang: String) -> String { self[lang] ?? self["en"] ?? "" } }

struct TourPackage: Codable {
    let schemaVersion: Int
    let monument: Monument
    let routes: Routes?                 // may be nil on older packages
    let checkpoints: [Checkpoint]
}
struct Monument: Codable {
    let id: String
    let name: LangMap
    let languages: [String]             // e.g. ["en","hi"]
    let overview: LangMap
}
struct Routes: Codable { let monument: Route?; let venue: Route? }
struct Route: Codable { let start: String; let end: String }   // checkpoint ids

struct Checkpoint: Codable, Identifiable {
    let id: String
    let order: Int                      // trail order for the map (0-based)
    let name: LangMap
    let mapPosition: MapPosition        // 0..1 relative coords on the map art
    let gps: GPS?                        // nil = indoor; arrival by AR-scan/tap
    let venue: Bool                      // true = Act-1 venue checkpoint
    let intro: LangMap
    let introAudio: LangMap             // {"en":"audio/<id>_intro_en.mp3", ...}
    let nuggets: [Nugget]
}
struct MapPosition: Codable { let x: Double; let y: Double }
struct GPS: Codable { let lat: Double; let lng: Double; let radius: Double } // metres

struct Nugget: Codable, Identifiable {
    let id: String
    let title: LangMap
    let targetImageId: String          // matches a file targets/<id>.jpg
    let exclusive: Bool                 // true = "guide-exclusive secret" ★
    let text: LangMap
    let audio: LangMap                 // {"en":"audio/<id>_en.mp3", "hi":"..."}
}
```
**Acceptance:** decode the shipped tour.json into `TourPackage` with no errors;
`checkpoints.count` and per-checkpoint `nuggets.count` are non-zero; every
`audio` path and `targets/<targetImageId>.jpg` resolves to a real file on disk.

---

## 4. The three screens

### 4a. MAP (Marauder's Map) — the signature screen [BEHAVIOR]
- Render checkpoints on the hand-drawn map art at each `mapPosition` (x,y are 0..1).
- Draw the trail in `order`; `routes.monument.start`→`.end` is the direction.
- Checkpoint state: locked / current / visited. Visited derives from the progress
  store (§7). Animate the unlock when a checkpoint completes.
- A "current position" marker (see your mockups) tracks the active checkpoint.
- **Acceptance:** all checkpoints appear in trail order; marking a nugget visited
  updates its checkpoint's progress on this screen without a reload.

### 4b. CAMERA (AR) — the magic screen [BEHAVIOR]
- `ARImageTrackingConfiguration`; load `targets/*.jpg` as `ARReferenceImage`s.
- On a target recognised → resolve to its nugget via `targetImageId` → drive the
  audio state machine (§6) → show an overlay (glow + title + ★ if exclusive).
- The mic button here runs live Q&A (§8), grounded in the *current* checkpoint.
- **Acceptance:** pointing at a printed target reliably fires the correct nugget's
  audio within ~1s of a steady hold; panning away stops it cleanly (per §6).
- **P1 polish — "capture" reveal (spec closed, build this exactly, do not
  improvise the image source):**
  1. On recognition lock: freeze the CURRENT camera preview frame for ~150ms
     with a white shutter-flash overlay. This frozen frame is FEEDBACK ONLY —
     never stored, never shown again, purely "it saw something" theater.
  2. Crossfade from that flash into the card, whose hero image is the SAME
     bundled reference photo already used for AR matching — i.e. resolve
     `nugget.targetImageId` → `targets/<id>.jpg` from the downloaded package.
     **Do NOT crop/use live ARSession pixel-buffer capture as the card's
     persistent content** — quality is uncontrolled (motion blur, bad angle,
     glare) and it is a demo-day reliability risk for zero benefit; the
     curated 2400px asset is guaranteed-quality every time and needs no new
     capture/crop code (ARKit pixel-buffer → UIImage plumbing is real work
     you don't need).
  3. Camera view minimizes to a corner thumbnail; the card takes over full-screen.
  4. Optional (cheap, thematically on-brand — "light reveals secrets"): an
     animated gold light-sweep gradient across the card image on reveal.
  This is UI polish on top of 4c'/4c's existing card view — no new data path,
  no schema change. Cut first if Sunday tightens; the plain overlay (P0) works
  without it.

### 4c'. BROWSE MODE — the AR-risk mitigation, made concrete [BEHAVIOR] (P0)
[RATIONALE] AR tracking is this project's one unverified risk (accepted, see
EXECUTION_PLAN). This is not a nice-to-have — it's the actual mitigation, and
it's stronger than "record a fallback video" because the app stays live and
interactive with zero camera dependency.

- Trigger: camera permission denied, AR unavailable/fails to init, OR the user
  taps "Browse" from the map/checkpoint (always available, not just a fallback).
- UI: the current checkpoint's nuggets as a tappable card list — SAME `Nugget`
  data as AR uses (title, text, exclusive ★, audio). Zero new data model.
- Tapping a card = identical effect to AR-recognizing its target: fires the §6
  audio state machine, opens the info-card view, and marks visited ON ENGAGEMENT
  (tap or AR-trigger) — never merely on appearing in the list. [Consistency rule:
  if listing counted as visited, "N of M secrets found" would be meaningless the
  instant the list opens — both paths must use the same visited semantics.]
- **Build order:** implement this BEFORE wiring AR. It's pure SwiftUI, no ARKit
  dependency, testable without a single printed target, and unblocks progress
  on day one. When AR recognition fires, it opens this same card — AR becomes
  an accelerant on a working backbone, not a single point of failure.
- **Acceptance:** with camera permission denied (or Airplane-Mode-style AR-off
  toggle for testing), every nugget in the current checkpoint is reachable,
  playable, and correctly marks visited — full tour completable with zero AR.

### 4c. INFO [BEHAVIOR]
- Shows the current checkpoint / active nugget: title, full `text.v(lang)`,
  exclusive badge, replay button. Read-only.
- **Acceptance:** reflects the active nugget; replay re-plays local audio.

---

## 5. Localization funnel — which checkpoint, which nugget [BEHAVIOR]
Two questions, two sensors. Resolve in this order:

**Q1 "which checkpoint am I in?" (coarse, ~10–40 m)**
- If `checkpoint.gps != nil` (outdoor): `CLLocationManager`, on-device distance
  to each gps; within `radius` → that checkpoint becomes current. No server call.
- If `gps == nil` (indoor / all venue checkpoints): current checkpoint is set by
  AR-scan or a map tap. GPS is useless indoors (±10–50 m) — do not use it there.

**Q2 "which object am I facing?" (sub-metre) → AR, not GPS**
- Primary: image tracking. Recognising `targetImageId` IS the nugget selection.
- Fallback for visually-identical objects with distinct labels: on-device text
  recognition (`VNRecognizeTextRequest` / Live Text) on the placard. (Not needed
  for the demo — printed targets are distinct — build only if a real venue needs it.)

[RATIONALE] Image tracking is deterministic feature-matching, not a guessing model.
The 15-identical-swords problem is solved by reading their *labels*, never by a
bigger AI. FoundationModels does no perception here.

**Acceptance:** outdoors, walking into a gps radius sets the checkpoint; indoors,
scanning a target sets both checkpoint and nugget.

---

## 6. Audio state machine — the anti-stutter core [BEHAVIOR] (P0)
Never bind audio to raw recognition events — they flicker. Debounce:
```swift
enum NuggetAudio { case idle, entering(Date), playing(String /*nuggetId*/), exiting(Date) }
enum AudioTiming {
    static let enterHold: TimeInterval = 0.3   // target held this long → start
    static let exitHold:  TimeInterval = 1.5   // target lost this long → stop
    static let fadeIn:    TimeInterval = 0.4
    static let fadeOut:   TimeInterval = 0.6
    static let crossfade: TimeInterval = 0.5   // when a new target replaces one
}
```
- target held ≥ enterHold → fade in that nugget's local mp3; on start, mark visited.
- target lost ≥ exitHold → fade out. Re-acquired within the window → keep playing.
- new target while playing → crossfade old→new.
- **Fades/crossfade polish and any ambient-music bed are P2 (Sunday slack), and
  are AVAudioEngine work. Ship the debounced start/stop first; smoothness later.**
- **Real-world edge cases (build these — cheap, prevent visibly janky demo moments):**
  - Question asked, user walks away before the ~4-5s /ask answer returns → answer
    is bound to the checkpoint it was asked at and plays when it arrives regardless
    of current camera target. Camera-driven triggering stays suppressed until the
    answer finishes, then resumes live (no queue, no replay of anything missed).
  - Two+ AR targets in frame at once → highest-confidence match wins; near-tied
    scores prefer whichever has been held longer (sticky, no flicker).
- **Acceptance:** a 200 ms occlusion (hand passes the target) does NOT cut audio;
  a genuine walk-away stops it within ~1.5 s; asking a question then walking to a
  new checkpoint still delivers the spoken answer when it arrives.

---

## 7. Progress — local first [BEHAVIOR]
- SwiftData model: `VisitedNugget(id, checkpointId, monumentId, timestamp)`.
- This set is the single source of truth for: map fill, the "N of M secrets found"
  counter, and the Tour Recap input (§9). Persist across launches.
- Remote sync is OPTIONAL and not built by default — if ever added it is a
  fire-and-forget POST, never on the playback path.
- **Acceptance:** visited nuggets survive an app relaunch and drive the map.

---

## 8. Live Q&A — AnswerEngine [CONTRACT + BEHAVIOR]
Abstract the answer source behind a protocol so cloud/on-device is a swap:
```swift
protocol AnswerEngine {
    func answer(text: String?, audioBase64: String?,
                checkpointId: String, monumentId: String, lang: String) async throws -> AskResponse
}
struct AskResponse: Codable { let question, text, audioBase64: String }
```
- `AzureAnswerEngine` (PRIMARY): POST `/ask` with `X-App-Key`. Record mic as
  16 kHz mono m4a → base64 → send; decode `audioBase64` reply → play.
- `FoundationModelsAnswerEngine` (roadmap/stub): on-device, offline; used for the
  Tour Recap now and offline Q&A later. See §9.
- **Acceptance:** on LAN, a spoken Hindi question returns spoken grounded audio
  in ≤5 s; a network failure surfaces a friendly retry, never a crash.

---

## 8b. Language — SELECTION vs DOWNLOAD (do not conflate) [CONTRACT + BEHAVIOR]
Two separate things:
- **Language SELECTION (P1, build now):** a picker at tour start. The app uses the
  chosen lang everywhere via `LangMap.v(lang)` for text and audio paths. This works
  TODAY against the current package (which carries all languages) — no backend change.
- **Per-language DOWNLOAD (P2 / scaling, DO NOT build for the demo):** shipping a
  separate zip per language so only the chosen language's audio downloads. For 2
  languages at ~3 MB total this is a premature optimization; it matters at 5+ langs.
  Gate: build per-language packages only when languages > 3. For the demo, one
  package + selection is correct and simpler.

**Voice continuity [CONTRACT — already guaranteed]:** the pre-rendered nugget audio
and the live /ask answer use the SAME Azure voice per language (nugget build and the
/ask TTS both read the same voice config). So a spoken answer sounds like the same
narrator as the nuggets — the "talking to the same guide in real time" effect is
already true; the app does nothing special to get it. Keep the picker's `lang`
consistent across playback and /ask calls and it holds.

## 9. iOS 27 / FoundationModels / Liquid Glass [BEHAVIOR]
- **Build against the iOS 27 SDK** so standard components inherit **Liquid Glass**
  (cheap, high-value polish). Use it; don't fight it.
- **FoundationModels Tour Recap** (iPhone 15 Pro+ / this team's iPhone 17): at tour
  end, feed the visited nuggets' titles+text from local tour.json to a
  `LanguageModelSession`; ask for a warm 2-sentence personalized summary. It reads
  the VISITED SET, never the camera. ~5-line API. This is P2 slack, first to cut.
- FM does NOT do localization or object ID. Keep it on the content layer only.
- Pitch line (zero build): "AnswerEngine is a protocol — swapping cloud GPT for
  on-device FoundationModels Q&A is a drop-in engine change."

---

## 10. Build order — do in this sequence, cut from the bottom [CONTRACT for priorities]
**P0 (demo cannot exist without these):**
1. PackageStore: download zip (or side-load a bundled copy), unzip, decode TourPackage.
2. Map screen from tour.json (order, mapPosition, visited state).
3. Browse Mode (§4c') — card list per checkpoint, no ARKit dependency. Build
   this BEFORE step 4; it's the resilient backbone AR sits on top of.
4. AR camera: image tracking → nugget → audio via the §6 state machine (local mp3).
5. District ticket mock → triggers the package download.
6. Info screen.

**P1 (strongly wanted):**
7. Live Q&A (AzureAnswerEngine) wired into the camera screen.
8. GPS geofencing for outdoor checkpoints.
9. Liquid Glass pass.
10. "Capture" reveal animation on AR recognition (§4b).

**P2 (slack only — first to die, in this order): FM recap → audio fades/music bed → remote progress sync.**

Ship against a **bundled copy of the package** from hour one (drop taj_mahal.zip
in the app bundle); switching to the live download is a one-line source change.
Never block your build waiting on the network.

---

## 10b. Demo script update — Browse Mode changes the pitch, in a good way
Judges can now be shown BOTH paths deliberately: "here's the AR magic" (camera
on a print → glow → audio), then "and here's the same tour with the camera
turned off" (tap Browse, same content, same voice, same progress). That's not
a fallback confession — it's a resilience flex. Consider making it an explicit
demo beat rather than a hidden safety net.

## 11. Demo-critical rules (do / don't)
- DO make the core tour work fully offline (airplane mode = still plays nuggets).
- DO default the base URL to LAN for the demo; warm `/ask` once before going on stage.
- DON'T call `/ask` or any network to play a nugget — nuggets are local mp3s.
- DON'T add a database, a positioning server, or realtime/WebSocket APIs — the
  backend is deliberately a static package + one `/ask` endpoint.
- DON'T register identical undistinguished targets and expect AR to tell them
  apart — use distinct printed targets (the demo does) or read labels (§5).

## 12. Owned by the other side (do not block on, but know it exists)
- Backend team: package hosting, `/ask`, the SQLite-backed admin/content panel,
  GPS coordinates seeded per checkpoint, TTS voice choice.
- Content: venue checkpoint text + venue AR photos in `targets/`.
- You get: the base URL, the APP_KEY, and a ready `taj_mahal.zip` to bundle.

**When you have a running skeleton, send it back for a review against §2–§9.**
