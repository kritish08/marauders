# AR + AUDIO BEHAVIOR SPEC — Swift side (build against this)
**Answers: which nugget fires, what if it misreads, how audio behaves. Backend is done; this is frontend contract.**

## 1. Nugget selection — the disambiguation ladder
Resolve in this order; stop at the first that applies per checkpoint:

1. **Distinct object / printed target → AR image tracking.**
   `ARImageTrackingConfiguration`, reference images = the `targetImageId` set.
   Deterministic feature matching, on-device, NOT probabilistic. This is the default.
2. **Identical objects, distinct labels → Vision text recognition.**
   `VNRecognizeTextRequest` / Live Text on the placard/number/caption.
   You identify the LABEL ("VII"), not the object. Museums label everything.
3. **No distinguishing marks → tap to select** from the checkpoint's nugget list.
   Fallback only; not a positioning system.

FoundationModels does NOT appear here. It cannot manufacture distinguishing
information that isn't in the image. Perception = vision; FM = content layer.

## 2. Recognition → audio state machine (the anti-stutter core) — P0
Never bind audio directly to raw recognition events. Debounce:

- target held continuously **≥ 0.3 s**  → ENTER: fade nugget audio in (0.4 s ramp)
- target lost continuously **≥ 1.5 s**  → EXIT: fade out (0.6 s ramp), mark visited
- target re-acquired during the 1.5 s window → stay playing (hysteresis; ignore flicker)
- new target enters while one is playing → crossfade (old out / new in, 0.5 s)

Tune the two thresholds; they are the entire fix for "what if it misreads and
the audio stutters." Flicker below threshold never reaches the audio layer.

## 3. Immersive audio — split by priority
- **P0**: the state machine above + single nugget player. Clean fades = premium feel.
- **P2 (Sunday slack, frontend, on the loaded Swift dev — cut first if tight)**:
  ambient music bed (AVAudioEngine: musicNode + voiceNode → mixer; duck music
  to ~20% under voice, restore on exit). Use a CC0/royalty-free ambient loop —
  licensing matters if judges ask. Layer music at RUNTIME (one bed, many nuggets)
  not baked into each mp3 — cheaper storage, flexible.
- **"Realistic human voice"** = the pending TTS ear-test, not a new build. If
  Azure neural isn't premium enough for the nugget bed, ElevenLabs at BUILD TIME
  for nuggets only = zero runtime latency cost. Decide tonight; re-render is
  cheap now, expensive Sunday noon.

## 3b. Audio PRIORITY / interruption model — answers "jump 1→15 + a question mid-play"
Think of it as TWO channels, not a pile of mp3s:

- **Channel MUSIC** (optional): `monument.ambientTrack`, continuous, low (~15-20%),
  never stops. Ducks to ~8% while a voice plays, restores after.
- **Channel VOICE**: plays EXACTLY ONE thing at a time — either a nugget mp3 OR a
  live answer. They are mutually exclusive. There is never "two nuggets at once."

Rules:
1. **Rapid target switching (artifact 1 → 15):** the §6 debounce means only a
   target HELD ≥0.3 s fires. Panning past 14 artifacts fires NOTHING; you get the
   one nugget the user settles on. A genuine switch crossfades old→new. So "jumping"
   is a non-problem by construction — you never trigger a stampede of mp3s.
2. **Question mid-nugget:** mic press ALWAYS wins. Pause/fade the current nugget →
   record → POST /ask → play the answer on Channel VOICE → then either resume the
   nugget from start or leave it stopped (design choice; resume-from-start is safer
   than resume-mid-sentence). Music keeps playing under both, ducked.
3. **Target lost while answering:** ignore target changes until the answer finishes;
   the answer is not interruptible by the camera (only by another mic press).
4. **Question asked, then user WALKS AWAY before the answer returns (real scenario —
   /ask is 4-5s, a person doesn't stand still that long):** the question is bound to
   the checkpoint it was asked at, NOT to "whatever's in frame right now." When the
   answer arrives, play it regardless of current camera target — a question always
   gets its answer. Camera-driven nugget triggering stays suppressed until the answer
   finishes; on finish, resume normally and pick up whatever's in frame THEN (no
   queue of missed nuggets, no replay — just resume live).
5. **Two+ targets visible at once** (e.g. two swords in frame): highest-confidence
   match wins. If scores are within a close margin, prefer whichever has been held
   longer (sticky) — do not flicker between near-tied targets.

[RATIONALE] One voice channel + a debounce is the whole trick. The fear ("it
misreads and stutters", "jumps fire 15 files", "a question collides with a nugget")
all reduce to: one voice at a time, questions preempt, camera flicker is debounced away.

## 3c. Ambient music [BEHAVIOR] (P2)
- `monument.ambientTrack` (may be null) → path inside the package, e.g. `music/x.mp3`.
- **2-4 min clean loop, NOT a long file.** `AVAudioPlayer.numberOfLoops = -1` makes
  a short loop indistinguishable from an hour of music, at a fraction of the
  download size and loop-seam risk. Starts when the map/tour screen appears,
  plays continuously through the whole session, ducks under voice (§3b), never
  stops on its own.
- Backend auto-bundles anything dropped in `backend/music/`. Files owned by the
  team (CC0 — Pixabay "no attribution" is safest). Mixing is AVAudioEngine, P2 slack.

## 4. Progress
Local SwiftData set: VisitedNugget(id, checkpointId, monumentId, timestamp).
Drives: map fill, "N of M secrets" counter, Tour Recap input. Source of truth.
Remote sync = optional fire-and-forget POST, off critical path, gated on a real
demo reason (e.g. analytics tile). Not built by default.

## 5. Whisper / live Q&A
Affects ONLY spoken-question path. Miss = user re-asks (graceful), never breaks
playback or localization. Mitigate: gpt-4o-transcribe > raw Whisper; on-device
SpeechTranscriber fallback; demo Qs rehearsed. Not a system risk.

## What I need before scaffolding Swift
The current frontend code. I'll check it against §1–§4: arrival wired to
geofence-or-tap, nugget-fire wired to image recognition (+ text-recognition
fallback where labels disambiguate), a visited-set model exists, recap reads
that set, and audio goes through the debounced state machine — not raw events.
