# FINAL LOCKED PLAN — District Interactive Monument Guide
**SwiftDidLoad (Eternal) · Locked Sat ~5:15 PM IST · Team: 1 Swift dev + Kritish + 1 (backend/AI/content)**
**Scope is FROZEN. Changes after this doc require naming what gets killed to make room.**

---

## 0. The one-line pitch

District gets you the ticket. We built what happens after you walk in: an offline-first, AR + voice guided tour in your own language, with secrets even the on-site guides don't tell you.

---

## 1. Locked decisions (no re-opening)

| Decision | Call | Why |
|---|---|---|
| Idea | District monument guide; health app dead | Eternal-centrality literal; employee-seeded |
| AI vendor | **Azure AI Foundry for everything** (STT + LLM + TTS) | Near-unlimited tokens, one vendor/auth/SDK. ElevenLabs NOT purchased. |
| Voice pipeline | Whisper/gpt-4o-transcribe → GPT-4o (grounded) → Azure Speech neural (hi-IN-Swara/Madhur, en-IN) | Known-good, single-vendor. 10-min Hindi listen test tonight = only remaining check. |
| Content delivery | Offline-first monument packages (plain zip over HTTPS, static hosting). Encryption = pitch line only. | Connectivity inside monuments is bad → offline-first is the honest product decision. |
| FoundationModels | **Tour Recap only** (P2-slack, 90-min Sun timebox, after P0s). Full FM Q&A stays out. | Bounded, off critical path, collects Apple Intelligence points. |
| Demo format | Two acts: venue-as-monument (live walk) + Taj package (prints) | Physical Marauder's Map demo + real product showcase |
| Demo devices | Primary: iPhone 17 / iOS 27 beta. **Backup: teammate's stable-iOS iPhone, same build, cloud path only.** | Betas pick demo day to act up. 5-min insurance. |
| Dev tooling | Xcode 27 agentic coding (Anthropic models built in) for Swift; Claude for backend/scripts. Single app target, no modularization. | AI writes, human integrates; keep drop-in friction near zero. |
| Model training | **None. Ever, this weekend.** Grounding = system prompt over content pack. | — |

---

## 2. Architecture

```
DEVICE — SwiftUI, iOS 27 SDK, Liquid Glass
├─ Screen 1  MAP     Marauder's-style map · checkpoints · progress unlocks
├─ Screen 2  CAMERA  ARKit ARImageTracking → anchored overlays → audio nuggets
│                    + mic button → live Q&A (AnswerEngine)
├─ Screen 3  INFO    contextual detail for current checkpoint/nugget
├─ District entry mock (F4): "your booking" → ticket → triggers package download
├─ PackageStore: GET /packages/{id}.zip → unzip → tour.json + audio/ + targets/
│                → core tour needs ZERO network after download
├─ AnswerEngine (protocol)
│   ├─ AzureEngine            PRIMARY — calls POST /ask
│   └─ FoundationModelsEngine Tour Recap only (on-device summary of visited nuggets)
└─ AVAudioPlayer for all nugget audio (bundled, pre-rendered)

BACKEND — all Azure
├─ Static hosting (Blob Storage / Static Web Apps):  /packages/{monumentId}.zip
├─ package_builder.py (Stream B, tonight):
│     content.yaml ──→ tour.json
│                  └─→ batch Azure Speech TTS (EN + HI, neural voices) → audio/*.m4a
│                  └─→ zip with AR target images
├─ POST /ask (Azure Function or tiny FastAPI):
│     audio/text + lang + checkpointId
│     → STT → GPT-4o [system prompt = that checkpoint's content pack;
│                      refuses/redirects outside it — anti-hallucination guardrail]
│     → Azure TTS → { text, audioURL }
└─ Azure AI Foundry deployments: gpt-4o · whisper/gpt-4o-transcribe · neural TTS
```

**API contract (frozen):**
```
GET  /packages/{monumentId}     → zip { tour.json, audio/*.m4a, targets/* }
tour.json: { monument, checkpoints: [ { id, name, mapPosition, nuggets: [
             { id, title, targetImageId, exclusive, text:{en,hi}, audio:{en,hi} } ] } ] }
POST /ask  { text|audioBase64, lang: "en"|"hi", checkpointId } → { text, audioURL }
```
Swift dev works from a bundled sample package from hour 1 — never blocked on backend.

---

## 3. Feature list — final

| # | Feature | Verdict |
|---|---------|---------|
| F1 | AR camera: image-tracked overlays + audio nuggets | **P0** |
| F2 | Marauder's Map: checkpoints, progress, unlock animations | **P0** |
| F3 | Live voice Q&A EN+HI via /ask | **P0** |
| F4 | District ticket mock → package download trigger | **P0** |
| F5 | Content: Taj pack (4–5 checkpoints, 12–15 nuggets) + 3–4 playful venue nuggets | **P0** (Stream B, tonight) |
| F6 | Info screen | **P1** |
| F7 | FM Tour Recap (on-device, iPhone 17) | **P2-slack** — Sun AM, 90-min box, after all P0s |
| F8 | Liquid Glass pass (largely automatic on iOS 27 SDK) | **P1** |
| F9/F10 | More languages / LiDAR occlusion | **Pitch slides only** |
| — | Chatbot screen, badges, encryption, model training | **CUT — final** |

**Kill order if anything slips >90 min: F7 → F8 → F6.**

---

## 4. Timeline (IST)

**NOW → 7:00 PM — SPIKE / GATE** *(slipped once from 6:30; does not slip again)*
- Swift dev: ARImageTracking → overlay → audio, on the iPhone 17, tested against a venue-feature photo AND a Taj image.
- Kritish: voice round-trip on Azure (Hindi in → Whisper → GPT-4o → hi-IN neural voice out) **< 5s**. Includes the 10-min Hindi listen test.
- Third: photograph venue AR-target features **in demo-time lighting**; start Taj content pack.
- **7:00 PM: both pass → committed for good. Either fails → revert to health pivot (viable at 7, not at midnight).**

**7:00 PM → 1:00 AM — Core build**
- Swift: F2 map screen → F1 wired to bundled sample package → F4 District mock.
- Backend: package_builder.py, full Taj + venue content into content.yaml, batch TTS all nugget audio EN+HI, host package, stand up /ask.
- **1:00 AM: sleep. Protected. Tired AR debugging on Sunday is how demos die.**

**Sun 7:00 AM → 12:00 PM — Integration**
- F3 voice Q&A into camera screen · F6 info screen · F8 Liquid Glass pass · real package download replacing bundled sample · venue walk test with registered targets.
- F7 Tour Recap ONLY if all P0s are integrated (90-min box).
- Install build on backup stable-iOS phone.

**12:00 → 2:00 PM — Freeze & harden**
- Feature freeze. 3 full end-to-end runs. **Record fallback demo video while everything works.**

**2:00 → 5:00 PM — Pitch**
- Deck ≤6 slides (§6). 3 rehearsals with physical targets under venue lighting. Bench setup, prints mounted, hotspot tested, 5 canned Q&As rehearsed.

---

## 5. Risks & mitigations

1. **Live AR failure** → printed foam-board targets, venue-lighting rehearsal, fallback video from Phase 4. Flaky at rehearsal → demo leads with map + voice, AR shown on video.
2. **Network dies** → core tour is offline by architecture; live Q&A degrades to 5 rehearsed canned Q&As; phone hotspot primary.
3. **iOS 27 beta misbehaves on demo day** → backup stable-iOS phone with same build, cloud path.
4. **Hallucinated monument facts** (judges WILL poke) → nuggets curated + sourced; GPT-4o grounded in pack and refuses outside it. Say it proactively — converts weakness to credibility.
5. **Single Swift dev bottleneck** → ~16h native work vs ~17 remaining. No native scope additions, period. Stream B absorbs everything non-native.
6. **Scope re-opening** — three renegotiations happened before 5 PM. This doc ends them. Any change now names its casualty first.

---

## 6. Pitch anchors (≤6 slides)

1. **Open with District, not AR:** "District gets you the ticket. We built what happens after you walk in."
2. **The Aha:** torch-on-the-marble — camera on print → glow + audio secret. Rehearse until boring.
3. **Guide-exclusive nuggets** = curated content moat.
4. **Honest AI:** grounded, curated, refuses to invent history — judges have seen a hundred hallucinating wrappers this weekend.
5. **Apple-native:** iOS 27 SDK, Liquid Glass, ARKit, on-device FoundationModels recap (if F7 shipped), Swift 6.4, built with Xcode 27 agentic coding. Do NOT claim WWDC26 ARKit/LiDAR news — there wasn't any.
6. **Roadmap:** every District-ticketed venue — forts, museums, galleries. More languages. LiDAR occlusion. On-device Q&A as a drop-in AnswerEngine swap. ~10M annual Taj visitors alone.

---

*Gate at 7:00 PM decides everything. Until then: three tracks, heads down.*
