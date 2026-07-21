# Marauders Backend

FastAPI service + content pipeline for the Marauders offline AR/voice tour
guide. One process serves grounded voice Q&A and hosts the offline package
zips the iOS app downloads once and plays back with no further network calls.

See the [workspace README](../README.md) for the full system architecture
diagram and how this fits together with the iOS app.

## What's in here

| File | Role |
|---|---|
| `ask_service.py` | FastAPI app: `POST /ask`, `GET /packages/*`, `GET /quiz/*`, `GET /health` |
| `admin_panel.py` + `admin.html` | Login-gated Content Studio — CRUD over checkpoints/nuggets, rebuild on demand |
| `package_builder.py` | Turns `content/*.yaml` into `dist/*.zip` (tour.json + TTS audio + AR targets + WebP images) |
| `content_db.py` | SQLite schema (authoritative content store) + YAML import/export |
| `tts.py` | Azure Speech / Azure OpenAI TTS backends |
| `prompts.py` | Grounded system-prompt builder (refuses off-pack questions) |
| `translate_content.py` | One-off translation pass (en → fr/es) via the same chat deployment |
| `bench_models.py` | Stopwatch bench across `CHAT_DEPLOYMENTS` to pick the fastest grounded model |
| `examples/` | Sample client code — see [`examples/README.md`](examples/README.md) |

## 1. Setup

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in keys — see table below
```

Azure AI Foundry deployments needed (names go in `.env`):
- A chat deployment (e.g. `gpt-4o` or newer) · `whisper` (STT) · optional TTS
  deployment (only if `TTS_PROVIDER=openai`)
- If `TTS_PROVIDER=speech` (recommended for Hindi): an **Azure Speech**
  resource — pick a region with the `hi-IN` neural voices you want.

### Environment variables

| Variable | Purpose |
|---|---|
| `AZURE_OPENAI_ENDPOINT` / `AZURE_OPENAI_API_KEY` | Chat + Whisper resource |
| `AZURE_OPENAI_API_VERSION` | API version pinned in `.env.example` |
| `AZURE_GPT_DEPLOYMENT` | Chat model — set from `bench_models.py`'s verdict |
| `AZURE_WHISPER_DEPLOYMENT` | Speech-to-text deployment name |
| `CHAT_DEPLOYMENTS` | Comma-separated candidates for the bench |
| `APP_KEY` | Shared secret required as `X-App-Key` on `/ask`, `/quiz`, `/admin/*`. Empty = open (local dev only) |
| `TTS_PROVIDER` | `speech` or `openai` |
| `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION` | If `TTS_PROVIDER=speech` |
| `SPEECH_VOICE_EN` / `_HI` / `_FR` / `_ES` | Per-language neural voice name |
| `AZURE_TTS_DEPLOYMENT` / `OPENAI_TTS_VOICE` | If `TTS_PROVIDER=openai` |

`.env` is gitignored — never commit real keys. Rotate `APP_KEY` immediately
if it's ever accidentally exposed (e.g. committed in a client config file).

## 2. Build a demo package (no keys needed)

```bash
brew install ffmpeg          # only for placeholder audio
python package_builder.py --content content/taj_mahal.yaml --no-tts
```

→ `dist/taj_mahal.zip` with a real `tour.json` and silent placeholder MP3s.
Hand this zip to a frontend dev immediately — the app integrates against the
real structure, and when real TTS runs later the filenames don't change, only
the audio does.

## 3. Full build (after keys + content are filled in)

```bash
python package_builder.py --content content/taj_mahal.yaml
```

| Flag | Effect |
|---|---|
| `--content <path>` | Required — the monument's YAML |
| `--no-tts` | Silent placeholder audio, no Azure calls |
| `--lang <code>` | Build a smaller single-language package (`tour.json` still lists all languages; only that lang's audio is bundled) |
| `--force-tts` | Ignore existing audio and regenerate everything (use after changing a voice) |
| `--out <dir>` | Output directory, default `dist/` |

Re-runs skip audio that already exists — delete a file to regenerate just
that one. Drop AR reference photos in `backend/targets/` first; filenames
must match `targetImageId` in the YAML.

## 4. Run the service

```bash
uvicorn ask_service:app --host 0.0.0.0 --port 8000
```

- Mac and phone on the same hotspot/WiFi for the LAN demo path:
  `ipconfig getifaddr en0` → app's base URL = `http://<that-ip>:8000`
- Cloud deploy (Azure App Service) is optional redundancy; same code, no
  changes needed.

```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/ask -H 'Content-Type: application/json' \
  -d '{"checkpointId":"cp_main_platform","lang":"hi","text":"संगमरमर क्यों चमकता है?"}'
```

Or run the full walkthrough: `./examples/ask_demo.sh` — see
[`examples/README.md`](examples/README.md).

## API contract

| Method | Path | Auth | Notes |
|---|---|---|---|
| `GET` | `/health` | — | Per-monument content version, for cache-busting on the client |
| `GET` | `/packages/{monumentId}.zip` | — | Full all-language package (frozen contract) |
| `GET` | `/packages/{monumentId}/{lang}.zip` | — | Language-scoped package |
| `POST` | `/ask` | `X-App-Key` | text / `audioBase64` / `imageBase64` in → `{question, text, audioBase64}` out |
| `GET` | `/quiz/{monumentId}` | `X-App-Key` | Multiple-choice quiz generated strictly from checkpoint facts |
| `POST` | `/admin/rebuild` | `X-App-Key` | Re-run the builder, refresh `/packages` |
| `/admin/*` | see `admin_panel.py` | `X-App-Key` | Full CRUD over monuments/checkpoints/nuggets |

`/ask` grounding is strict: answers come only from the checkpoint's curated
facts, and off-pack or jailbreak-style prompts get a refusal, never an
invented answer (verified transcript in `REPORT.md`).

## Admin panel

`GET /admin` serves a login-gated Content Studio (`admin.html`) for editing
tour content without touching code or redeploying:

1. Enter `APP_KEY` to unlock.
2. Pick a property, edit checkpoints/nuggets, upload flashcard images.
3. Hit rebuild — `package_builder.py` runs server-side and `/packages`
   refreshes immediately.

## Testing

```bash
python -m py_compile *.py
python -m unittest discover tests
```

## Deployment

See [`../SEED_AND_DEPLOY.md`](../SEED_AND_DEPLOY.md) for the full Azure App
Service runbook (region matching the Foundry deployment, app settings, GPS
seeding, redeploy checklist).

## More context

- [`../BUILD_BRIEF_district_tour_guide.md`](../BUILD_BRIEF_district_tour_guide.md) — original product brief
- [`CLAUDE.md`](CLAUDE.md) — full build-session history and the additive-only contract discipline this codebase was built under
- [`REPORT.md`](REPORT.md) — per-task evidence for every phase (latency numbers, grounding transcripts, deploy confirmations)
