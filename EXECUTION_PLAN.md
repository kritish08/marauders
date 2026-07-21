# EXECUTION PLAN — Final. Kritish = architect, Claude Code = hands.
**Issued Sat 6:25 PM IST. This supersedes discussion; it does not supersede the
BUILD_BRIEF's frozen scope. Nothing enters this plan without killing something.**

## Status ledger at issue time

DONE & VERIFIED: backend code (package_builder, /ask + grounding, TTS x2),
sample package `dist/taj_mahal.zip` (7 checkpoints, real Taj EN+HI content),
CLAUDE.md tasks 1–9, architecture locked (packages offline-first, Azure
everything, checkpoint-scoped grounding — NO Mongo, NO RAG, NO realtime API).

UNKNOWN (resolve at T0, no exceptions): AR tracking on iPhone 17 · Azure keys
· venue photos · venue nugget text · map screen state.

---

## T0 — NOW → 6:45 PM: 15-minute status sync (Kritish runs it)

Each item gets a binary answer out loud:
1. AR image tracking working on the iPhone? **If NO and not working by 7:00 PM,
   the revert decision happens AT 7:00** — this was the gate; it does not drift.
2. Azure keys available right now? (Blocks everything in Block A.)
3. Venue features photographed in demo lighting? If no → teammate 3 does it
   before dark, before anything else.
4. Map screen: blank / skeleton / working?

## BLOCK A — 7:00 → 9:30 PM: Backend live (Kritish + Claude Code)

Hand Claude Code: *"Read backend/CLAUDE.md. Execute tasks 1–9 in order. Report
evidence per task. Databases, RAG, embeddings, realtime APIs are out of scope."*

| By | Milestone | Acceptance |
|----|-----------|------------|
| 7:30 | Keys in, local /ask round-trip (Hindi) | curl output + latency ms |
| 7:45 | X-App-Key guard | 401 without header, 200 with |
| 8:45 | App Service deployed (+DNS/Actions ONLY via fast paths, inside box) | remote /health green |
| 9:00 | Remote authed /ask round-trip | **latency < 5000 ms — the number** |
| 9:15 | Swift dev has: base URL, APP_KEY, contract, working curl | his own curl succeeds |
| 9:30 | HARD STOP on infra. Whatever isn't green is frozen or reverted to LAN. | — |

## BLOCK B — 7:00 → 11:30 PM parallel: Content & audio (teammate 3 + Kritish's ears)

| By | Milestone |
|----|-----------|
| 8:00 | Venue photos in `backend/targets/`, filenames = targetImageId |
| 9:00 | All [FILL] venue nuggets written (playful, EN+HI); Taj [FILL]s closed |
| 9:15 | 10-min listen test → TTS_PROVIDER set, permanently |
| 10:30 | Full build (no --no-tts): every nugget + intro voiced EN+HI |
| 11:00 | Package re-uploaded; Swift dev pulls real-audio zip; spot-check 3 files by ear |
| 11:30 | Print masters for Taj targets queued/arranged for morning |

## BLOCK C — tonight: Swift (untouched by A/B; he owes by 1:00 AM)

Map v1 (checkpoints + progress from bundled tour.json) and AR camera firing
nugget audio on 2+ targets. Integration with live URL is SUNDAY MORNING work —
tonight he builds against the bundled package only. Nobody adds to his plate.

## 1:00 AM: SLEEP. Non-negotiable. 7:00 AM restart.

## SUNDAY
- 7:00–12:00 — Integrate: /ask voice in camera screen · package download via
  District ticket mock · info screen · Liquid Glass pass · **FM Tour Recap
  only in this window's slack, 90-min box, first to die**.
- 12:00–2:00 — FREEZE. 3 end-to-end runs. Record fallback video while green.
- 2:00–5:00 — Deck (≤6 slides, brief §7 + roadmap below) · 3 rehearsals with
  physical targets in venue light · bench setup · hotspot test · 5 canned Q&As.

---

## THE FLAUNT LIST (what "really good" looks like to judges — demo moments, not architecture)

1. **Torch-on-the-marble** — camera on print → glow overlay + audio secret.
2. **The physical walk** — judges follow the Marauder's Map through real venue
   checkpoints. No other team will have judges walking during their demo.
3. **The hallucination challenge** — hand a judge the phone: "ask it anything —
   try to make it invent history." It refuses off-pack questions. Confidence
   move; nobody else will dare it.
4. **Offline proof** — kill the network mid-demo; nugget tour keeps playing.
   (Pre-rendered package audio = this works by construction.)
5. **The three-stage roadmap** (technical depth on one slide, every stage real):
   *Today:* self-contained packages, checkpoint-scoped grounding — GPS is the
   retrieval. *Next:* same bundle feeds on-device FoundationModels with
   on-device embeddings — fully offline conversational guide. *At scale:*
   server-side vector retrieval across hundreds of District-ticketed venues.
6. **Apple-native list** — iOS 27 SDK, Liquid Glass, ARKit, FM recap (if F7
   shipped), Swift 6.4, built with Xcode 27 agentic coding.

## Failure branches (decide fast, no debate)

- AR dead at 7:00 PM → revert call per brief. At 6:24 PM this was still open;
  if you shipped past it silently, you accepted the risk — fallback video and
  map+voice-led demo become mandatory, rehearse that variant too.
- Azure deploy not green at 9:30 → LAN (README §5), zero further infra time.
- TTS Hindi disappointing in listen test → other provider; if both mediocre,
  ship anyway — content beats timbre.
- Sunday slack = zero → F7, F8, F6 die in that order, silently, per brief.
