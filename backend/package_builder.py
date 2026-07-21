#!/usr/bin/env python3
"""Build an offline monument package from a content YAML.

    content/<id>.yaml  ->  dist/<id>/tour.json
                           dist/<id>/audio/<nuggetId>_<lang>.mp3
                           dist/<id>/targets/*   (copied from targets/)
                           dist/<id>.zip         (what the app downloads)

Usage:
    python package_builder.py --content content/taj_mahal.yaml            # full build (TTS)
    python package_builder.py --content content/taj_mahal.yaml --no-tts   # structure only:
        writes tour.json + 1s silent placeholder MP3s so the Swift dev can
        integrate NOW; re-run without --no-tts later — same filenames,
        audio just gets real. Requires ffmpeg for placeholders (brew install ffmpeg).

Nuggets audio = text[lang] read by premium neural TTS. Intros are also rendered
(<checkpointId>_intro_<lang>.mp3) so checkpoints can auto-narrate on arrival.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import yaml

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

ROOT = Path(__file__).parent
LANGS_DEFAULT = ["en", "hi"]


def loc(d, lang):
    if isinstance(d, dict):
        return d.get(lang) or d.get("en") or ""
    return d or ""


def target_image_ids(nugget: dict) -> list[str]:
    """Return the ordered, de-duplicated primary + alternate AR target IDs."""
    candidates = [nugget.get("targetImageId", ""), *(nugget.get("targetImageIds") or [])]
    values = list(dict.fromkeys(value for value in candidates if isinstance(value, str) and value))
    invalid = [value for value in values if not re.fullmatch(r"[A-Za-z0-9_-]+", value)]
    if invalid:
        raise ValueError(f"invalid target image IDs for {nugget.get('id', '<unknown>')}: {invalid}")
    return values


def build_tour_json(doc: dict) -> dict:
    monument = doc["monument"]
    checkpoints = list(doc.get("checkpoints", []))
    # Venue checkpoints (Act 1) ship in the same package under a flag the
    # app can filter on ("venueMode").
    for c in doc.get("venue_checkpoints", []) or []:
        c["venue"] = True
        checkpoints.append(c)

    out_cps = []
    for order, c in enumerate(checkpoints):
        out_cps.append(
            {
                "id": c["id"],
                "order": order,
                "name": c["name"],
                "mapPosition": c.get("mapPosition", {"x": 0.5, "y": 0.5}),
                "gps": c.get("gps"),  # {lat,lng,radius} or null — on-device geofence
                "venue": bool(c.get("venue", False)),
                "intro": c.get("intro", {}),
                "introAudio": {
                    lang: f"audio/{c['id']}_intro_{lang}.mp3"
                    for lang in monument.get("languages", LANGS_DEFAULT)
                },
                "nuggets": [
                    {
                        "id": n["id"],
                        "title": n["title"],
                        "targetImageId": n.get("targetImageId", ""),
                        "targetImageIds": target_image_ids(n),
                        "exclusive": bool(n.get("exclusive", False)),
                        "images": n.get("images") or [],
                        "text": n["text"],
                        "audio": {
                            lang: f"audio/{n['id']}_{lang}.mp3"
                            for lang in monument.get("languages", LANGS_DEFAULT)
                        },
                        **({"targetPhysicalWidthM": n["target_width_m"]} if n.get("target_width_m") else {}),
                    }
                    for n in c.get("nuggets", [])
                ],
                **({"aiContext": c["aiContext"]} if c.get("aiContext") else {}),
            }
        )
    def _route(cps):
        return {"start": cps[0]["id"], "end": cps[-1]["id"]} if cps else None

    monument_cps = [c for c in out_cps if not c["venue"]]
    venue_cps = [c for c in out_cps if c["venue"]]
    return {
        "schemaVersion": 1,
        "monument": {
            "id": monument["id"],
            "name": monument["name"],
            "languages": monument.get("languages", LANGS_DEFAULT),
            "overview": monument.get("overview", {}),
            # optional bg music, admin-settable; file bundled from backend/music/
            "ambientTrack": monument.get("ambientTrack"),
        },
        # Explicit trail direction for the map UI: first->last in order.
        "routes": {"monument": _route(monument_cps), "venue": _route(venue_cps)},
        "checkpoints": out_cps,
    }


def iter_audio_jobs(doc: dict, only_langs=None):
    """Yield (filename_stem, text, lang) for every audio file the package needs.

    If only_langs is provided (a set/list of lang codes), only jobs whose lang
    is in only_langs are yielded. When None (default), all monument languages
    are emitted — behavior unchanged.
    """
    monument = doc["monument"]
    langs = monument.get("languages", LANGS_DEFAULT)
    if only_langs is not None:
        langs = [l for l in langs if l in only_langs]
    checkpoints = list(doc.get("checkpoints", [])) + list(
        doc.get("venue_checkpoints", []) or []
    )
    for c in checkpoints:
        for lang in langs:
            intro = loc(c.get("intro", {}), lang)
            if intro and not intro.startswith("[FILL"):
                yield f"{c['id']}_intro_{lang}", intro, lang
        for n in c.get("nuggets", []):
            for lang in langs:
                text = loc(n["text"], lang)
                if text and not text.startswith("[FILL"):
                    yield f"{n['id']}_{lang}", text, lang


def make_silent_mp3(path: Path):
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
            "-t", "1", "-b:a", "48k", str(path),
        ],
        check=True,
    )


def copy_referenced_targets(filenames: set[str], source_dir: Path, destination_dir: Path) -> int:
    """Copy every declared AR target, failing instead of shipping a partial package."""
    copied = 0
    for filename in sorted(filenames):
        source = source_dir / filename
        if not source.is_file():
            raise FileNotFoundError(f"referenced AR target is missing: {source}")
        shutil.copy2(source, destination_dir / filename)
        copied += 1
    return copied


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", required=True)
    ap.add_argument("--no-tts", action="store_true", help="placeholder audio only")
    ap.add_argument("--out", default=str(ROOT / "dist"))
    ap.add_argument(
        "--lang",
        default=None,
        help="build a smaller single-language package (only that lang's audio "
        "mp3s are bundled; tour.json still lists all languages)",
    )
    ap.add_argument(
        "--force-tts",
        action="store_true",
        help="ignore existing audio files and regenerate everything with the "
        "current TTS_PROVIDER/voice config (use after changing a voice)",
    )
    args = ap.parse_args()

    doc = yaml.safe_load(Path(args.content).read_text(encoding="utf-8"))
    mid = doc["monument"]["id"]

    only_langs = None
    slug = mid
    if args.lang is not None:
        monument_langs = doc["monument"].get("languages", LANGS_DEFAULT)
        if args.lang not in monument_langs:
            sys.exit(
                f"[error] --lang {args.lang!r} is not one of the monument's "
                f"languages {monument_langs}"
            )
        only_langs = {args.lang}
        slug = f"{mid}_{args.lang}"

    out_dir = Path(args.out) / slug
    audio_dir = out_dir / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)

    # 1. tour.json
    tour = build_tour_json(doc)
    (out_dir / "tour.json").write_text(
        json.dumps(tour, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"[ok] tour.json  ({len(tour['checkpoints'])} checkpoints)")

    # 2. audio
    jobs = list(iter_audio_jobs(doc, only_langs=only_langs))
    # Per-language build: reuse audio already rendered in the full-build dir
    # (byte-identical) instead of paying to re-TTS it. Falls through to TTS for
    # anything not already present.
    if only_langs is not None and not args.no_tts and not args.force_tts:
        full_audio = Path(args.out) / mid / "audio"
        if full_audio.exists():
            for stem, _, _ in jobs:
                src, dst = full_audio / f"{stem}.mp3", audio_dir / f"{stem}.mp3"
                if src.exists() and not dst.exists():
                    shutil.copy2(src, dst)
    if args.no_tts:
        for stem, _, _ in jobs:
            make_silent_mp3(audio_dir / f"{stem}.mp3")
        print(f"[ok] {len(jobs)} placeholder (silent) mp3s — re-run without --no-tts for real audio")
    else:
        from tts import get_tts

        tts = get_tts()
        for i, (stem, text, lang) in enumerate(jobs, 1):
            target = audio_dir / f"{stem}.mp3"
            if target.exists() and target.stat().st_size > 2000 and not args.force_tts:
                print(f"[skip] {stem}.mp3 (exists)")
                continue
            target.write_bytes(tts.synthesize(text, lang))
            print(f"[tts {i}/{len(jobs)}] {stem}.mp3")

    # Collect ONLY the media this monument's tour.json references, so a package
    # carries its own targets/images and never another property's (per-property
    # download is the whole point of the DB->yaml->zip middleware).
    referenced_targets, referenced_images = set(), set()
    for c in list(doc.get("checkpoints", [])) + list(doc.get("venue_checkpoints", []) or []):
        for n in c.get("nuggets", []):
            for tid in target_image_ids(n):
                referenced_targets.add(f"{tid}.jpg")
            for img in n.get("images") or []:
                referenced_images.add(Path(img).name)  # "images/x.webp" -> "x.webp"

    # 3. AR target images — only this monument's referenced targets. Rebuilt clean
    # (rmtree first) so a prior all-targets build leaves no stale extras behind.
    targets_src = ROOT / "targets"
    targets_dst = out_dir / "targets"
    if targets_dst.exists():
        shutil.rmtree(targets_dst)
    targets_dst.mkdir(parents=True, exist_ok=True)
    n = copy_referenced_targets(referenced_targets, targets_src, targets_dst)
    print(f"[ok] {n}/{len(referenced_targets)} referenced target images copied")

    # 3a. nugget display images (WebP) — only this monument's referenced images.
    images_src = ROOT / "nugget_images"
    images_dst = out_dir / "images"
    if images_dst.exists():
        shutil.rmtree(images_dst)
    if referenced_images:
        images_dst.mkdir(parents=True, exist_ok=True)
        ni = 0
        for fn in sorted(referenced_images):
            if (images_src / fn).exists():
                shutil.copy2(images_src / fn, images_dst / fn)
                ni += 1
        print(f"[ok] {ni}/{len(referenced_images)} nugget images bundled")

    # 3b. ambient music (optional) — bundle backend/music/ into the package
    music_src = ROOT / "music"
    if music_src.exists() and any(music_src.iterdir()):
        shutil.copytree(music_src, out_dir / "music", dirs_exist_ok=True)
        print(f"[ok] ambient music bundled ({len(list((out_dir/'music').glob('*')))} tracks)")

    # 4. zip
    zip_path = Path(args.out) / f"{slug}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(out_dir.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(out_dir))
    print(f"[done] {zip_path}  ({zip_path.stat().st_size // 1024} KB)")
    print("Serve it: ask_service.py mounts dist/ at /packages "
          f"-> GET /packages/{slug}.zip")


if __name__ == "__main__":
    sys.exit(main())
