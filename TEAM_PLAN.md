# TEAM PLAN — Sat ~8:45 PM IST · for discussion, then execution
**App: District Monument Guide (Marauder's Map + AR + voice) · Demo: Sunday ~5 PM**

## Architecture as it stands (final — see diagram)

**Content:** SQLite DB (authoritative, admin panel CRUD) → exports YAML →
`package_builder.py` → offline package zip (tour.json + ALL audio pre-rendered
EN+HI + AR target images). Device downloads once at District ticket tap;
core tour then needs zero network.

**Live voice Q&A:** app → `POST /ask` (X-App-Key) → Whisper → **gpt-5.4-mini**
(grounded strictly in the checkpoint's nuggets, refuses off-pack — verified
6/6 incl. jailbreak) → Azure TTS → audio back. Deployed:
`marauders-backend.azurewebsites.net` (eastus, Always On pending S2).

**Demo network decision (locked by measurement):** LAN primary — service on
the Mac, phone on hotspot, 4.3–4.4s warm. Cloud URL = redundancy + "deployed
live on Azure" pitch line (8.7s full loop from India, so not the stage path).

**On-device AI:** FoundationModels Tour Recap only (iPhone 17), Sunday slack,
90-min box, first to die. Roadmap slide: same package feeds on-device FM with
on-device embeddings → fully offline guide; vector retrieval at 100-monument
scale. Say it, don't build it.

## Status board

| Workstream | State | Evidence |
|---|---|---|
| Backend + deploy | **GREEN — frozen** | REPORT.md: 10/10 tasks + extras |
| Model + grounding | **GREEN — locked** | bench table; 6/6 transcript |
| Admin panel (SQLite CRUD) | **GREEN, integrating** | CRUD verified; S2.2 in flight |
| Taj AR target images | Scripted, S2.1 running | 6 Commons images mapped |
| Package audio EN+HI | **GREEN** | 20/20 real files, 3.1 MB zip |
| TTS voice choice | **WAITING ON EARS** | test_speech.mp3 vs test_openai.mp3 |
| **Venue content** | **RED — the gap** | 16 [FILL]s, 0 venue photos |
| Swift: map screen | In progress (team) | — |
| Swift: AR tracking | **UNVERIFIED** | accepted risk — fallback video mandatory |
| Swift: /ask + download integration | Not started (Sunday AM) | URL + APP_KEY ready |

## Tonight (before 1 AM sleep — non-negotiable sleep)

1. **Venue content sprint (owner: teammate 3, ~90 min):** photograph 3–4
   feature-rich venue surfaces (ornament, not blank walls) in demo lighting →
   `targets/`; write the 16 [FILL] fields — straight into `/admin` once S2.2
   lands, or the YAML; rebuild → venue audio renders.
2. **Ears (owner: Kritish, 10 min):** pick TTS voice. Decision expires tonight.
3. **Swift dev:** map + AR against the bundled package only. Nobody adds scope.
4. Print run queued: 6 Taj targets + venue backups, A4 matte.

## Sunday

- **7–12** Integrate: package download via ticket mock · /ask voice in camera
  screen · info screen · Liquid Glass pass · FM recap ONLY in slack.
- **12–2** FREEZE. 3 end-to-end runs. Record fallback video while green.
  Rehearse the no-AR variant too (map + voice led) — AR is unverified.
- **2–5** Deck (≤6 slides) · 3 rehearsals with prints in venue light ·
  warm-up /ask before stage · 5 canned Q&As ready.

## The demo (two acts + three moves)

Act 1: judges physically walk the venue checkpoints on the Marauder's Map.
Act 2: Taj package on printed targets — torch-on-marble is the money beat.
Moves: hand a judge the phone ("try to make it invent history" — it refuses);
kill the network mid-tour (audio keeps playing — offline by construction);
live nugget: add one in /admin → rebuild → appears on the phone.

## Kill order if anything slips >90 min
FM recap → Liquid Glass pass → info screen. Content and rehearsal are never
the thing cut — they're the thing everything else is cut FOR.

## Risks (top 3)
1. AR tracking unverified → no-AR demo variant rehearsed + fallback video.
2. Venue WiFi/RF → LAN primary, hotspot, canned Q&As, offline core tour.
3. Single sponsorship subscription for all Azure quota → short answers
   (already trimmed to 140 tokens), no fallback keys — don't hammer /ask in
   rehearsal more than needed.
