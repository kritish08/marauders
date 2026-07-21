# SEED + DEPLOY — hand this to Claude Code (run from backend/)
**Goal:** seed both properties (Taj fix + Zomato new), then push the whole S6
stack to Azure with the updated schema. Phase C is reviewed/approved — S6 is
complete and cleared to deploy. Additive-only discipline still applies; a task
with no pasted evidence in REPORT.md is not done. Append a dated "SESSION 6 —
SEED + DEPLOY" section.

Inputs already placed in the repo (do not recreate):
- `content/zomato_farmhouse.yaml` — the new property, en+hi, gps set, images[] referenced.
- `seed_zomato_media.py` — converts `../Zomato Farm/` photos → targets/ + nugget_images/.

## STEP 1 — Taj: resolve the last [FILL] in n_pietra_dura
Edit `content/taj_mahal.yaml`, nugget `n_pietra_dura`:
- **title.en:** `Flowers Made of 72 Stones`
- **title.hi:** `बहत्तर पत्थरों से बने फूल`
- **text.en:**
  > Each flower is parchin kari — dozens of slices of carnelian, jade, lapis and
  > turquoise, cut and inlaid into carved marble so precisely you can't feel the
  > joints. On the screen around the royal cenotaph, a single flower holds 72
  > separate stone pieces — and the stones travelled the world to get here:
  > carnelian from Arabia, turquoise from Tibet, malachite from Russia. Fifty
  > such flowers ring each tomb.
- **text.hi:**
  > हर फूल पच्चीकारी है — कार्नेलियन, जेड, लाजवर्द और फ़िरोज़ा के दर्जनों टुकड़े,
  > संगमरमर में इतनी बारीकी से जड़े कि जोड़ महसूस नहीं होते। शाही कब्र के चारों ओर
  > की जाली पर एक अकेले फूल में 72 अलग पत्थर के टुकड़े हैं — और ये पत्थर दुनिया भर
  > से आए: अरब से कार्नेलियन, तिब्बत से फ़िरोज़ा, रूस से मैलाकाइट। हर कब्र के चारों
  > ओर पचास ऐसे फूल हैं।
- **CRITICAL — clear the now-stale fr/es for this ONE nugget** (title.fr, title.es,
  text.fr, text.es → empty/remove) so `translate_content.py` regenerates them from
  the new EN. If you leave them, the script skips them (non-empty) and fr/es stay
  wrong. Every OTHER nugget's fr/es is unchanged — do not touch them.
- Evidence: show the nugget's 4-lang title+text before/after; confirm no other
  field in taj_mahal.yaml changed (git diff scoped to n_pietra_dura).

## STEP 2 — Zomato media (real venue photos → targets + WebP galleries)
```
.venv/bin/python seed_zomato_media.py
```
Evidence: the printed per-nugget lines; `ls targets/zf_*.jpg` (6) and
`ls nugget_images/n_parking_tree_*.webp …` counts matching the YAML
(tree 3, gwagon 3, farmhouse 1, garden 4, frontdesk 1, rockbench 2 = 14 webp).

## STEP 3 — Translate, THEN seed the DB (order matters — see the ⚠ below)
Do it in THIS order so the DB ends up carrying all 4 languages. `translate_content.py`
writes fr/es back into the YAML files, not the DB — so translate FIRST, then import
the translated YAML into the DB. If you import first and translate after, the DB has
only en/hi and any later `/admin/export` or `/admin/rebuild` will re-emit en/hi over
your translated YAML and DROP fr/es (the Phase A landmine again).

1. Translate BOTH files explicitly (the script defaults to taj — you MUST pass the
   Zomato path or Zomato silently ships en/hi only and fr/es fall back to English):
   ```
   .venv/bin/python translate_content.py --content content/taj_mahal.yaml --langs fr,es
   .venv/bin/python translate_content.py --content content/zomato_farmhouse.yaml --langs fr,es
   ```
   ⚠ The script does en→fr,es only, NOT hi. Zomato hi is already authored in the
   YAML; Taj hi (incl. STEP 1's n_pietra_dura fix) is hand-authored. Do not expect hi.
   ⚠ For Taj n_pietra_dura, STEP 1 must have CLEARED its old fr/es first, or the
   script skips them (non-empty) and they stay wrong.

2. Import BOTH translated YAMLs into the DB (now carrying 4 langs):
   ```
   .venv/bin/python content_db.py --import content/zomato_farmhouse.yaml
   .venv/bin/python content_db.py --import content/taj_mahal.yaml
   ```
   `--import` upserts the monument row, so this CREATES the `zomato_farmhouse`
   property (verify it appears in `/admin/monuments` with 3 checkpoints).

- Evidence: DB round-trip — `--export` both to temp files, confirm zomato has 4
  langs on every field (fr/es non-empty) and taj n_pietra_dura reads "72" in all 4.
  This proves DB == YAML, so BOTH build paths (package_builder --content AND
  /admin/rebuild) produce identical 4-language packages.

## STEP 4 — Rebuild BOTH packages (per-property, uses 6C.0)
```
.venv/bin/python package_builder.py --content content/taj_mahal.yaml
.venv/bin/python package_builder.py --content content/zomato_farmhouse.yaml
```
(or `POST /admin/rebuild?monument=taj_mahal` and `?monument=zomato_farmhouse`.)
Evidence per zip: `unzip -l` showing tour.json + audio (en/hi/fr/es) + targets +
`images/` (Zomato: the 14 webp; Taj: its test webp/empty is fine). Decode each
tour.json: `monument.languages == [en,hi,fr,es]`, every nugget `images` is a list,
Zomato gps present on 3 checkpoints (28.4791…, 77.1634…), Taj n_pietra_dura text
contains "72".

## STEP 5 — DEPLOY the S6 stack to Azure (code + schema + data together)
This is the first S6 deploy — everything so far was local. requirements.txt now
has Pillow + python-multipart (Phase C) — they must install on the host.
a. Commit + push (`git add -A && commit`), then `az webapp up` (same app
   `marauders-backend`, rg `marauders-rg`). Confirm the build installs Pillow +
   python-multipart (check the build log / a remote import).
b. **Schema + data update on the host:** upload the fully-seeded local `tour.db`
   (it already carries the new `images_json` column + fr/es columns + both
   properties) to the host via Kudu VFS PUT — this is the "update the schema
   altogether" step; the migrations are additive and the local DB is already
   migrated, so uploading it makes the host schema+data current in one move.
c. Ensure host has the media the packages need: upload `targets/` (incl. new
   `zf_*.jpg`) and `nugget_images/` (the new webp) to the host, OR rebuild on the
   host after the db upload: `POST /admin/rebuild?monument=taj_mahal` then
   `?monument=zomato_farmhouse` so the deployed `/packages/*.zip` regenerate from
   the uploaded db + media.
d. Restart / confirm Always On still set.

## STEP 6 — Verify on the DEPLOYED app (evidence, not assumptions)
```
GET  /health                              -> ok, lists taj_mahal AND zomato_farmhouse
GET  /packages/taj_mahal.zip              -> 200 (grew: pietra fix + images)
GET  /packages/zomato_farmhouse.zip       -> 200 (NEW — 3 cp, 6 nuggets, gps, 14 webp)
GET  /packages/taj_mahal/fr.zip           -> 200 (per-language still works)
POST /ask (zomato_farmhouse, cp_office, en) -> grounded playful answer + audio
POST /ask (taj_mahal, cp_inlay_detail, en, "how many stones in a flower?") -> "72"
GET  /admin (deployed)                    -> login page, property dropdown has both
```
Confirm FROZEN: en/hi Taj audio SHA unchanged except the intentionally-changed
n_pietra_dura; /ask contract shape unchanged; targetImageId/targets/ intact (plus
the 6 new zf_ targets).

## STEP 7 — REPORT.md
Append "SESSION 6 — SEED + DEPLOY" with the evidence above, the deployed URLs for
both packages, and the humans-still-owe list (real curated Taj gallery photos —
still my follow-up; fr/es quality review; physical AR target prints incl. the new
zf_ targets; the mislabeled `taj_great_gate.jpg` = mosque note still open).

## Hard rules
Additive only. Do not rewrite working content or audio. Do not touch any nugget's
fr/es EXCEPT taj n_pietra_dura (STEP 1). Keep the frozen `/ask` + full/per-language
package contracts. If import_yaml or per-property rebuild behaves unexpectedly for
the new property, STOP and report — do not force-overwrite taj_mahal.
