#!/usr/bin/env python3
"""Convert the real Zomato Farmhouse photos into AR targets + WebP flashcard
galleries, named exactly as content/zomato_farmhouse.yaml references them.

Run from backend/ with the venv that has Pillow (Phase C added it):
    .venv/bin/python seed_zomato_media.py

Source photos: ../Zomato Farm/<Area (CP)>/<Thing (NUGGET)>/*.jpeg
Outputs:
    targets/<targetImageId>.jpg          (AR reference, first photo, <=2000px, q88)
    nugget_images/<nuggetId>_<n>.webp    (gallery, every photo, <=1600px, q82)

Idempotent: overwrites its own outputs, touches nothing else. Applies EXIF
orientation so sideways phone photos come out upright.
"""
import sys
from pathlib import Path
from PIL import Image, ImageOps

BACKEND = Path(__file__).resolve().parent
SRC = BACKEND.parent / "Zomato Farm"          # ../Zomato Farm
TARGETS = BACKEND / "targets"
GALLERY = BACKEND / "nugget_images"

# (nugget_id, targetImageId, source subfolder)
MAP = [
    ("n_parking_tree",       "zf_parking_tree", "Parking Area (CP)/The Tree (NUGGET)"),
    ("n_parking_gwagon",     "zf_gwagon",       "Parking Area (CP)/G WagonR (NUGGET)"),
    ("n_farmhouse_building", "zf_farmhouse",    "Farm House Area (CP)/Farm House (NUGGET)"),
    ("n_farmhouse_garden",   "zf_garden",       "Farm House Area (CP)/Garden (NUGGET)"),
    ("n_office_frontdesk",   "zf_frontdesk",    "Office Building (CP)/Front Desk (NUGGET)"),
    ("n_office_rockbench",   "zf_rockbench",    "Office Building (CP)/Rock Bench (NUGGET)"),
]
EXTS = {".jpeg", ".jpg", ".png", ".heic"}


def load(p: Path) -> Image.Image:
    im = Image.open(p)
    im = ImageOps.exif_transpose(im)          # respect phone rotation
    return im.convert("RGB")


def main() -> int:
    if not SRC.exists():
        print(f"[FATAL] source folder not found: {SRC}", file=sys.stderr)
        return 1
    TARGETS.mkdir(exist_ok=True)
    GALLERY.mkdir(exist_ok=True)

    total_gallery = total_targets = 0
    for nid, tid, sub in MAP:
        folder = SRC / sub
        if not folder.exists():
            print(f"[WARN] missing {folder} — skipping {nid}")
            continue
        photos = sorted(p for p in folder.iterdir() if p.suffix.lower() in EXTS)
        if not photos:
            print(f"[WARN] no photos in {folder} — skipping {nid}")
            continue

        # AR target = first photo, <=2000px, JPEG
        t = load(photos[0]); t.thumbnail((2000, 2000))
        t.save(TARGETS / f"{tid}.jpg", "JPEG", quality=88, optimize=True)
        total_targets += 1

        # gallery = every photo, <=1600px, WebP
        for n, p in enumerate(photos):
            g = load(p); g.thumbnail((1600, 1600))
            g.save(GALLERY / f"{nid}_{n}.webp", "WEBP", quality=82)
            total_gallery += 1
        print(f"[ok] {nid}: target {tid}.jpg + {len(photos)} gallery webp")

    print(f"\n[done] {total_targets} targets -> targets/ , "
          f"{total_gallery} images -> nugget_images/")
    print("Now: import content/zomato_farmhouse.yaml, then rebuild "
          "(--monument zomato_farmhouse).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
