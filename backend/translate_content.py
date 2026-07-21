#!/usr/bin/env python3
"""One-off idempotent translator for the content pack.

Reads content/taj_mahal.yaml and, for every localized ("LangMap") field that
has a real English (en) value, fills in French (fr) and Spanish (es) using the
existing Azure chat deployment. Writes the YAML back in place.

ADDITIVE ONLY — never touches existing en/hi values, never translates [FILL
placeholders, and skips any target language that is already present & non-empty
(so it is safe to re-run). Frozen-content codebase: this only appends fr/es keys.

Run:  python translate_content.py --content content/taj_mahal.yaml --langs fr,es
"""
import argparse
import os

import yaml

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

from openai import AzureOpenAI

client = AzureOpenAI(
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    api_key=os.environ["AZURE_OPENAI_API_KEY"],
    api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2025-04-01-preview"),
)
MODEL = os.getenv("AZURE_GPT_DEPLOYMENT", "gpt-5.4-mini")

# target lang code -> human-readable language name for the prompt
LANGUAGE_NAMES = {
    "fr": "French",
    "es": "Spanish",
}


def _chat(messages):
    # gpt-5.x deployments reject `max_tokens` (400) and require
    # `max_completion_tokens`; older ones reject the new name. Try the current
    # param first, fall back on the legacy one only for that specific error.
    try:
        return client.chat.completions.create(
            model=MODEL, messages=messages, max_completion_tokens=600
        )
    except Exception as e:
        if "max_completion_tokens" not in str(e):
            raise
        return client.chat.completions.create(
            model=MODEL, messages=messages, max_tokens=600, temperature=0.2
        )


def translate(text: str, lang: str) -> str:
    language = LANGUAGE_NAMES[lang]
    system = (
        f"You translate museum-guide copy to {language}. Preserve tone and "
        f"meaning. Do NOT add, embellish, or invent facts. Return only the "
        f"translation, with no quotes, labels, or preamble."
    )
    chat = _chat(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": text},
        ]
    )
    out = (chat.choices[0].message.content or "").strip()
    if not out:
        raise RuntimeError(f"empty translation returned for {lang!r}")
    return out


def _is_placeholder(en: str) -> bool:
    """True when the en value is empty/missing or a [FILL...] placeholder."""
    if not en or not en.strip():
        return True
    return en.lstrip().startswith("[FILL")


def _needs(langmap: dict, lang: str) -> bool:
    """True when this LangMap is missing a non-empty value for `lang`."""
    v = langmap.get(lang)
    return not (isinstance(v, str) and v.strip())


def process_langmap(langmap, label, langs, stats):
    """Fill missing fr/es on a single LangMap dict, in `langs` order.

    Preserves key order: en/hi already lead; new keys are appended fr then es
    (dict insertion order). Non-dict or no-en values are left untouched.
    """
    if not isinstance(langmap, dict):
        return
    en = langmap.get("en")
    if not isinstance(en, str) or _is_placeholder(en):
        return
    for lang in langs:
        if not _needs(langmap, lang):
            stats["skipped"] += 1
            continue
        try:
            langmap[lang] = translate(en, lang)
            stats["translated"] += 1
            print(f"[{lang}] {label}")
        except Exception as e:  # noqa: BLE001 — report and continue
            stats["failed"] += 1
            print(f"[{lang}] {label} FAILED: {e}")


def process_checkpoints(checkpoints, group, langs, stats):
    for cp in checkpoints or []:
        cid = cp.get("id", "?")
        process_langmap(cp.get("name"), f"{group}:{cid}.name", langs, stats)
        process_langmap(cp.get("intro"), f"{group}:{cid}.intro", langs, stats)
        for nug in cp.get("nuggets", []) or []:
            nid = nug.get("id", "?")
            process_langmap(
                nug.get("title"), f"{group}:{cid}.{nid}.title", langs, stats
            )
            process_langmap(
                nug.get("text"), f"{group}:{cid}.{nid}.text", langs, stats
            )


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--content", default="content/taj_mahal.yaml")
    ap.add_argument("--langs", default="fr,es")
    args = ap.parse_args()

    langs = [l.strip() for l in args.langs.split(",") if l.strip()]
    unknown = [l for l in langs if l not in LANGUAGE_NAMES]
    if unknown:
        raise SystemExit(f"unsupported --langs {unknown}; known: {list(LANGUAGE_NAMES)}")

    with open(args.content, encoding="utf-8") as f:
        doc = yaml.safe_load(f)

    stats = {"translated": 0, "skipped": 0, "failed": 0}

    monument = doc.get("monument") or {}
    process_langmap(monument.get("name"), "monument.name", langs, stats)
    process_langmap(monument.get("overview"), "monument.overview", langs, stats)

    process_checkpoints(doc.get("checkpoints"), "cp", langs, stats)
    process_checkpoints(doc.get("venue_checkpoints"), "venue", langs, stats)

    with open(args.content, "w", encoding="utf-8") as f:
        yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False)

    print(
        f"\nDone: translated {stats['translated']}, skipped {stats['skipped']}"
        + (f", failed {stats['failed']}" if stats["failed"] else "")
        + f" -> {args.content}"
    )


if __name__ == "__main__":
    main()
