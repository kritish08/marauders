#!/usr/bin/env python3
"""Build the hand-curated WagonR, Cabin, and Rock Bench media refresh."""

from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "Zomato Farm"

TARGETS = {
    "zf_gwagon": "Parking Area (CP)/G WagonR (NUGGET)/NU/IMG_7063.jpeg",
    "zf_gwagon_0": "Parking Area (CP)/G WagonR (NUGGET)/NU/IMG_7048.jpeg",
    "zf_gwagon_1": "Parking Area (CP)/G WagonR (NUGGET)/NU/IMG_7058.jpeg",
    "zf_gwagon_2": "Parking Area (CP)/G WagonR (NUGGET)/NU/IMG_7067.jpeg",
    "zf_gwagon_3": "Parking Area (CP)/G WagonR (NUGGET)/NU/IMG_7072.jpeg",
    "zf_gwagon_4": "Parking Area (CP)/G WagonR (NUGGET)/NU/IMG_7073.jpeg",
    "zf_cabin": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7090.jpeg",
    "zf_cabin_0": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7079.jpeg",
    "zf_cabin_1": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7095.jpeg",
    "zf_cabin_2": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7100.jpeg",
    "zf_cabin_3": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7103.jpeg",
    "zf_rockbench": "Office Building (CP)/Rock Bench (NUGGET)/NU/IMG_7112.jpeg",
    "zf_rockbench_0": "Office Building (CP)/Rock Bench (NUGGET)/NU/IMG_7110.jpeg",
    "zf_rockbench_1": "Office Building (CP)/Rock Bench (NUGGET)/NU/IMG_7111.jpeg",
    "zf_rockbench_2": "Office Building (CP)/Rock Bench (NUGGET)/NU/IMG_7113.jpeg",
    "zf_rockbench_3": "Office Building (CP)/Rock Bench (NUGGET)/NU/IMG_7115.jpeg",
    "zf_rockbench_4": "Office Building (CP)/Rock Bench (NUGGET)/NU/IMG_7116.jpeg",
}

GALLERY = {
    "n_parking_cabin_0": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7079.jpeg",
    "n_parking_cabin_1": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7095.jpeg",
    "n_parking_cabin_2": "Parking Area (CP)/The Cabin (NUGGET)/IMG_7108.jpeg",
}


def load(relative_path: str) -> Image.Image:
    source = SOURCE / relative_path
    if not source.is_file():
        raise FileNotFoundError(source)
    return ImageOps.exif_transpose(Image.open(source)).convert("RGB")


def main() -> None:
    targets_dir = ROOT / "targets"
    gallery_dir = ROOT / "nugget_images"
    targets_dir.mkdir(exist_ok=True)
    gallery_dir.mkdir(exist_ok=True)

    for target_id, source in TARGETS.items():
        image = load(source)
        image.thumbnail((2000, 2000))
        output = targets_dir / f"{target_id}.jpg"
        image.save(output, "JPEG", quality=88, optimize=True)
        print(f"[target] {target_id}: {source} -> {image.width}x{image.height}, {output.stat().st_size} bytes")

    for image_id, source in GALLERY.items():
        image = load(source)
        image.thumbnail((1600, 1600))
        output = gallery_dir / f"{image_id}.webp"
        image.save(output, "WEBP", quality=82)
        print(f"[gallery] {image_id}: {source} -> {image.width}x{image.height}, {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
