#!/usr/bin/env python3
"""Live voice Q&A service + package host. One process, one MacBook.

    POST /ask       text OR audioBase64 -> grounded GPT-4o answer -> TTS -> audioBase64
    GET  /packages  static zips built by package_builder.py (dist/)
    GET  /health    sanity check

Run:  uvicorn ask_service:app --host 0.0.0.0 --port 8000
iPhone hits http://<this-Mac's-LAN-IP>:8000 (same hotspot/WiFi — see README §5).
"""
import base64
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import yaml
from fastapi import Depends, FastAPI, Header, HTTPException, Response
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

from openai import AzureOpenAI

from admin_panel import admin_router
from prompts import build_system_prompt
from tts import get_tts

ROOT = Path(__file__).parent
CONTENT_DIR = Path(os.getenv("CONTENT_DIR", ROOT / "content"))
DIST_DIR = Path(os.getenv("DIST_DIR", ROOT / "dist"))
DIST_DIR.mkdir(exist_ok=True)

app = FastAPI(title="district-tour-guide backend")
app.include_router(admin_router)


# Per-language zip download. Registered BEFORE the /packages StaticFiles mount
# so the two-segment path is matched here first; the one-segment frozen route
# GET /packages/{monumentId}.zip does NOT match this and falls through to the
# mount (frozen behavior preserved). URL uses /{lang}.zip; the file on disk is
# {monument_id}_{lang}.zip (underscore).
@app.get("/packages/{monument_id}/{lang}.zip")
def package_lang(monument_id: str, lang: str):
    path = DIST_DIR / f"{monument_id}_{lang}.zip"
    if not path.is_file():
        raise HTTPException(404, f"no package for {monument_id} / {lang}")
    return FileResponse(str(path), media_type="application/zip")


app.mount("/packages", StaticFiles(directory=str(DIST_DIR)), name="packages")

client = AzureOpenAI(
    azure_endpoint=os.environ.get("AZURE_OPENAI_ENDPOINT", ""),
    api_key=os.environ.get("AZURE_OPENAI_API_KEY", ""),
    api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2025-04-01-preview"),
    max_retries=3,  # §B: backoff retries on 429/5xx (SDK-native)
)
GPT_DEPLOYMENT = os.getenv("AZURE_GPT_DEPLOYMENT", "gpt-4o")
WHISPER_DEPLOYMENT = os.getenv("AZURE_WHISPER_DEPLOYMENT", "whisper")
tts = None  # lazy — lets /health work before keys are set

# --- auth: /ask requires X-App-Key when APP_KEY env is set ---------------
# /health and /packages stay open. Unset APP_KEY = open (local dev only);
# ALWAYS set APP_KEY before public deploy.
APP_KEY = os.getenv("APP_KEY", "")


def require_app_key(x_app_key: str | None = Header(default=None, alias="X-App-Key")):
    if APP_KEY and x_app_key != APP_KEY:
        raise HTTPException(401, "missing or invalid X-App-Key")


def _load_content() -> dict:
    packs = {}
    for f in CONTENT_DIR.glob("*.yaml"):
        doc = yaml.safe_load(f.read_text(encoding="utf-8"))
        checkpoints = list(doc.get("checkpoints", [])) + list(
            doc.get("venue_checkpoints", []) or []
        )
        packs[doc["monument"]["id"]] = {
            "monument": doc["monument"],
            "checkpoints": {c["id"]: c for c in checkpoints},
        }
    return packs


PACKS = _load_content()


class AskRequest(BaseModel):
    monumentId: str = "taj_mahal"
    checkpointId: str
    lang: str = "en"  # "en" | "hi"
    text: str | None = None
    audioBase64: str | None = None  # m4a/wav/mp3 from the phone mic
    skipAudio: bool = False  # text-only chatbot fast path: skip TTS, audioBase64 = ""
    imageBase64: str | None = None  # optional JPEG camera frame for vision Q&A


class AskResponse(BaseModel):
    question: str
    text: str
    audioBase64: str  # mp3


class QuizQuestion(BaseModel):
    prompt: str
    choices: list[str]
    answerIndex: int
    checkpointId: str


class QuizResponse(BaseModel):
    questions: list[QuizQuestion]


_ver_cache: dict = {}


def _pkg_version(mid: str) -> int:
    """A stable integer that changes whenever the monument's full zip content
    changes — lets the installed app detect a new build and offer re-download.
    Cached by (mtime,size) so /health doesn't re-hash a 15 MB zip every call."""
    p = DIST_DIR / f"{mid}.zip"
    if not p.is_file():
        return 0
    st = p.stat()
    key = (str(p), st.st_mtime, st.st_size)
    if key not in _ver_cache:
        _ver_cache[key] = int(hashlib.sha256(p.read_bytes()).hexdigest()[:8], 16)
    return _ver_cache[key]


@app.get("/health")
def health():
    return {
        "ok": True,
        "monuments": {mid: len(p["checkpoints"]) for mid, p in PACKS.items()},
        "packages": [f.name for f in DIST_DIR.glob("*.zip")],
        # per-monument content version (Task 5): app compares to detect changes
        "packageVersions": {mid: _pkg_version(mid) for mid in PACKS},
    }


@app.post("/ask", response_model=AskResponse, dependencies=[Depends(require_app_key)])
def ask(req: AskRequest, response: Response):
    t_start = time.perf_counter()
    global tts
    pack = PACKS.get(req.monumentId)
    if not pack:
        raise HTTPException(404, f"unknown monument {req.monumentId}")
    checkpoint = pack["checkpoints"].get(req.checkpointId)
    if not checkpoint:
        raise HTTPException(404, f"unknown checkpoint {req.checkpointId}")

    # 1. STT if audio came in
    question = (req.text or "").strip()
    if not question and req.audioBase64:
        audio = base64.b64decode(req.audioBase64)
        buf = io.BytesIO(audio)
        buf.name = "question.m4a"
        tr = client.audio.transcriptions.create(
            model=WHISPER_DEPLOYMENT,
            file=buf,
            language=req.lang,
        )
        question = tr.text.strip()
    if not question and not req.imageBase64:
        raise HTTPException(400, "need text, audioBase64, or imageBase64")
    if not question:  # image-only query — the photo IS the question
        question = "What am I looking at here? Identify it and tell me about it."

    # 2. Grounded answer (vision when an image frame is attached — Task 3)
    system = build_system_prompt(
        pack["monument"], checkpoint, list(pack["checkpoints"].values()), req.lang
    )
    if req.imageBase64:
        if len(req.imageBase64) > 2_800_000:  # ~2 MB decoded ceiling (spec: <=1 MB)
            raise HTTPException(400, "image too large (max ~1MB)")
        user_content = [
            {"type": "text", "text": question},
            {"type": "image_url",
             "image_url": {"url": f"data:image/jpeg;base64,{req.imageBase64}"}},
        ]
    else:
        user_content = question
    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": user_content},
    ]
    def _chat_call():
        # max_completion_tokens first: it's the current param and the only
        # one gpt-5.x accepts (roomy so reasoning tokens don't starve the
        # answer); fall back to legacy max_tokens where it's rejected
        try:
            return client.chat.completions.create(
                model=GPT_DEPLOYMENT, messages=messages, max_completion_tokens=140
            )
        except Exception as e:
            if "max_completion_tokens" not in str(e):
                raise
            return client.chat.completions.create(
                model=GPT_DEPLOYMENT, messages=messages, max_tokens=220, temperature=0.4
            )

    try:
        chat = _chat_call()
        answer = (chat.choices[0].message.content or "").strip()
    except Exception as e:
        # Azure content filter 400s on jailbreak-style prompts; a refusal is
        # the correct product behavior, never a 500. Empty content (reasoning
        # budget burned) gets the same refusal below.
        if "content_filter" not in str(e):
            raise
        answer = ""
    if not answer:
        answer = (
            "क्षमा कीजिए, यह इस टूर में शामिल नहीं है। चलिए, वापस स्मारक की कहानी पर चलते हैं।"
            if req.lang == "hi"
            else "Sorry, I don't have that in this tour. Let's get back to the monument."
        )

    # 3. TTS reply — skipped for the text-only chatbot fast path (no wasted
    # synthesis when the caller won't play audio). audioBase64 stays "" (valid).
    if req.skipAudio:
        audio_out = b""
    else:
        if tts is None:
            tts = get_tts()
        audio_out = tts.synthesize(answer, req.lang)

    elapsed_ms = int((time.perf_counter() - t_start) * 1000)
    print(
        f"[ask] {time.strftime('%Y-%m-%dT%H:%M:%S')} {req.checkpointId} "
        f"{req.lang} {elapsed_ms}ms",
        flush=True,
    )
    # Task 6: latency telemetry headers (body unchanged). Every /ask answer is
    # freshly generated by the model, so source is always "model".
    response.headers["X-Answer-Source"] = "model"
    response.headers["X-Answer-Ms"] = str(elapsed_ms)
    return AskResponse(
        question=question,
        text=answer,
        audioBase64=base64.b64encode(audio_out).decode(),
    )


_QUIZ_LANG = {"en": "English", "hi": "Hindi", "fr": "French", "es": "Spanish"}


@app.get("/quiz/{monument_id}", response_model=QuizResponse,
         dependencies=[Depends(require_app_key)])
def quiz(monument_id: str, checkpoints: str = "", lang: str = "en", count: int = 5):
    """Task 4: structured multiple-choice quiz generated STRICTLY from the
    listed checkpoints' aiContext.facts. answerIndex is validated in bounds
    server-side; malformed questions are dropped, not returned."""
    pack = PACKS.get(monument_id)
    if not pack:
        raise HTTPException(404, f"unknown monument {monument_id}")
    ids = [c.strip() for c in checkpoints.split(",") if c.strip()] or list(
        pack["checkpoints"].keys()
    )
    corpus = {}
    for cid in ids:
        cp = pack["checkpoints"].get(cid)
        facts = (cp.get("aiContext") or {}).get("facts") if isinstance(cp, dict) else None
        if facts:
            corpus[cid] = facts
    if not corpus:
        raise HTTPException(400, "no aiContext.facts for the given checkpoints")
    count = max(1, min(int(count), 15))
    lang_name = _QUIZ_LANG.get(lang, "English")
    facts_block = "\n".join(f"[{cid}] {f}" for cid, fs in corpus.items() for f in fs)
    sys_prompt = (
        f"Write {count} multiple-choice quiz questions in {lang_name}, based ONLY "
        "on the facts below (each prefixed with its [checkpointId]). Each question "
        "has exactly 4 choices, exactly one correct (drawn from the facts); the 3 "
        "distractors must be plausible but clearly wrong per the facts. Invent "
        'nothing not in the facts. Return ONLY a JSON array of objects: '
        '{"prompt": str, "choices": [4 strings], "answerIndex": int 0-3, '
        '"checkpointId": str (one of the provided ids)}.'
    )
    msgs = [{"role": "system", "content": sys_prompt},
            {"role": "user", "content": facts_block}]
    try:
        raw_out = client.chat.completions.create(
            model=GPT_DEPLOYMENT, messages=msgs, max_completion_tokens=1600
        )
    except Exception as e:
        if "max_completion_tokens" not in str(e):
            raise
        raw_out = client.chat.completions.create(
            model=GPT_DEPLOYMENT, messages=msgs, max_tokens=1600, temperature=0.4
        )
    out = (raw_out.choices[0].message.content or "").strip()
    if out.startswith("```"):  # strip a stray markdown fence
        out = out.strip("`")
        out = out[4:].strip() if out[:4].lower() == "json" else out
    try:
        items = json.loads(out)
    except Exception:
        raise HTTPException(502, "quiz generation returned invalid JSON")
    valid_ids = set(corpus)
    questions = []
    for q in items if isinstance(items, list) else []:
        try:
            prompt = str(q["prompt"]).strip()
            choices = [str(c) for c in q["choices"]]
            ai = int(q["answerIndex"])
            cid = str(q.get("checkpointId", "")).strip()
        except (KeyError, TypeError, ValueError):
            continue
        # server-side validation: exactly 4 choices (frontend renders 4) and
        # answerIndex in bounds — drop anything malformed rather than return it
        if not prompt or len(choices) != 4 or not (0 <= ai < 4):
            continue
        if cid not in valid_ids:
            cid = next(iter(valid_ids))
        questions.append(QuizQuestion(prompt=prompt, choices=choices,
                                      answerIndex=ai, checkpointId=cid))
    return QuizResponse(questions=questions)


@app.post("/admin/rebuild", dependencies=[Depends(require_app_key)])
def rebuild(lang: str | None = None, monument: str | None = None):
    """§B: re-run the package builder server-side and refresh /packages —
    lets content edits go live without a redeploy. Optional ?lang builds only
    the per-language zip dist/<id>_<lang>.zip; optional ?monument builds a
    non-primary property's package (content/<id>.yaml -> dist/<id>.zip);
    both omitted = full multi-lang rebuild of the primary taj_mahal package."""
    global PACKS
    if monument and not re.fullmatch(r"[a-z0-9_]+", monument):
        raise HTTPException(400, "bad monument id")
    content = f"content/{monument}.yaml" if monument else "content/taj_mahal.yaml"
    args = [sys.executable, "package_builder.py", "--content", content]
    if lang:
        args += ["--lang", lang]
    r = subprocess.run(
        args,
        capture_output=True, text=True, cwd=ROOT, timeout=600,
    )
    if r.returncode != 0:
        raise HTTPException(500, (r.stderr or r.stdout)[-500:])
    PACKS = _load_content()
    return {"ok": True, "log": r.stdout[-800:]}
