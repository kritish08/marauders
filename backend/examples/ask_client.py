#!/usr/bin/env python3
"""Minimal Python client for the Marauders /ask endpoint.

Shows the three supported input modes (text, recorded audio, camera frame)
and prints the grounded answer + writes the spoken reply to disk.

Usage:
    python examples/ask_client.py --text "Why does the marble glow?"
    python examples/ask_client.py --audio question.m4a --lang hi
    python examples/ask_client.py --image checkpoint.jpg --checkpoint cp_main_platform

Environment:
    BASE_URL   default http://localhost:8000
    APP_KEY    required if the server was started with APP_KEY set
"""
import argparse
import base64
import os
import sys

import requests

BASE_URL = os.environ.get("BASE_URL", "http://localhost:8000")
APP_KEY = os.environ.get("APP_KEY", "")


def ask(checkpoint_id: str, lang: str = "en", *, text: str | None = None,
        audio_path: str | None = None, image_path: str | None = None,
        skip_audio: bool = False) -> dict:
    payload = {"checkpointId": checkpoint_id, "lang": lang, "skipAudio": skip_audio}
    if text:
        payload["text"] = text
    if audio_path:
        payload["audioBase64"] = base64.b64encode(open(audio_path, "rb").read()).decode()
    if image_path:
        payload["imageBase64"] = base64.b64encode(open(image_path, "rb").read()).decode()

    headers = {"X-App-Key": APP_KEY} if APP_KEY else {}
    resp = requests.post(f"{BASE_URL}/ask", json=payload, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.json()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--checkpoint", default="cp_main_platform")
    p.add_argument("--lang", default="en", choices=["en", "hi", "fr", "es"])
    p.add_argument("--text", help="typed question")
    p.add_argument("--audio", help="path to a .m4a/.wav/.mp3 recording of the question")
    p.add_argument("--image", help="path to a JPEG camera frame (vision Q&A)")
    p.add_argument("--out", default="reply.mp3", help="where to save the spoken answer")
    p.add_argument("--skip-audio", action="store_true", help="text-only, skip TTS")
    args = p.parse_args()

    if not (args.text or args.audio or args.image):
        p.error("pass at least one of --text, --audio, --image")

    result = ask(
        args.checkpoint, args.lang,
        text=args.text, audio_path=args.audio, image_path=args.image,
        skip_audio=args.skip_audio,
    )

    print(f"Q: {result['question']}")
    print(f"A: {result['text']}")

    if result["audioBase64"]:
        with open(args.out, "wb") as f:
            f.write(base64.b64decode(result["audioBase64"]))
        print(f"[audio saved to {args.out}]")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        print(f"HTTP {e.response.status_code}: {e.response.text}", file=sys.stderr)
        sys.exit(1)
