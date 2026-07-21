#!/usr/bin/env python3
"""Build the per-checkpoint aiContext grounding corpus from EXISTING vetted copy.

For each checkpoint, concatenates its already-authored intro + nugget text (EN,
human-verified) and asks the chat model to EXTRACT the discrete facts stated in
it — strictly, with no invention — plus a one-line fallbackNote. Writes
`aiContext: {facts: [...], fallbackNote: {en,hi,fr,es}}` onto each checkpoint.

This is the grounding the on-device model and /ask both answer from, so they
agree. It is derived from vetted content, never fabricated.

Idempotent: a checkpoint that already has non-empty aiContext.facts is skipped.

    python build_ai_context.py --content content/taj_mahal.yaml
"""
import argparse
import json
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

FACTS_SYS = (
    "You build the knowledge base for an AI museum guide. Below is curated, "
    "human-verified copy about ONE spot at a monument. Extract the discrete "
    "factual statements it contains. RULES: (1) Use ONLY information explicitly "
    "present in the text — do NOT add, infer, generalize, or embellish. "
    "(2) Each fact is one clear standalone sentence. (3) Produce 5-15 facts "
    "(fewer only if the text is genuinely short). (4) Return ONLY a JSON array "
    "of strings, no prose, no markdown fences."
)
NOTE_SYS = (
    "In ONE warm spoken sentence (max 25 words), tell a visitor what they can "
    "discover at this spot, using ONLY what the text below says. Add nothing new. "
    "Return just the sentence."
)


def _chat(messages):
    try:
        return client.chat.completions.create(
            model=MODEL, messages=messages, max_completion_tokens=900
        )
    except Exception as e:
        if "max_completion_tokens" not in str(e):
            raise
        return client.chat.completions.create(
            model=MODEL, messages=messages, max_tokens=900, temperature=0.2
        )


_LANG_NAME = {"hi": "Hindi", "fr": "French", "es": "Spanish"}


def _to_lang(text, lang):
    """Translate the short fallbackNote to hi/fr/es (the note is a derived
    summary, so machine hi translation is fine here — unlike core content)."""
    sys = (
        f"Translate to {_LANG_NAME[lang]}. Preserve meaning and tone. Return "
        "only the translation, no quotes or preamble."
    )
    out = _chat(
        [{"role": "system", "content": sys}, {"role": "user", "content": text}]
    ).choices[0].message.content or ""
    return out.strip().strip('"')


def _loc(d, lang):
    return (d or {}).get(lang, "") if isinstance(d, dict) else (d or "")


def _real(s):
    return isinstance(s, str) and s.strip() and not s.strip().startswith("[FILL")


def _source_text(cp):
    parts = []
    intro = _loc(cp.get("intro"), "en")
    if _real(intro):
        parts.append(intro)
    for n in cp.get("nuggets", []) or []:
        t = _loc(n.get("text"), "en")
        if _real(t):
            parts.append(t)
    return "\n\n".join(parts)


def _extract_facts(text):
    out = _chat(
        [{"role": "system", "content": FACTS_SYS}, {"role": "user", "content": text}]
    ).choices[0].message.content or ""
    out = out.strip()
    if out.startswith("```"):  # strip a stray markdown fence
        out = out.split("```")[1].lstrip("json").strip() if "```" in out[3:] else out.strip("`")
    facts = json.loads(out)
    if not isinstance(facts, list):
        raise ValueError("model did not return a JSON array")
    return [f.strip() for f in facts if isinstance(f, str) and f.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", required=True)
    args = ap.parse_args()

    doc = yaml.safe_load(open(args.content, encoding="utf-8"))
    checkpoints = list(doc.get("checkpoints", [])) + list(
        doc.get("venue_checkpoints", []) or []
    )
    built = skipped = failed = 0
    for cp in checkpoints:
        existing = cp.get("aiContext") or {}
        if existing.get("facts"):
            skipped += 1
            print(f"[skip] {cp['id']} (aiContext exists)")
            continue
        text = _source_text(cp)
        if not text:
            skipped += 1
            print(f"[skip] {cp['id']} (no source text — [FILL])")
            continue
        try:
            facts = _extract_facts(text)  # may raise on a malformed model reply
            note_en = (_chat(
                [{"role": "system", "content": NOTE_SYS}, {"role": "user", "content": text}]
            ).choices[0].message.content or "").strip().strip('"')
        except Exception as e:  # noqa: BLE001 — one bad reply must not torch the run
            failed += 1
            print(f"[fail] {cp['id']} (model reply unusable: {e}) — left untouched, re-run to retry")
            continue
        note = {"en": note_en}
        for lg in ("hi", "fr", "es"):
            try:
                note[lg] = _to_lang(note_en, lg)
            except Exception as e:  # noqa: BLE001
                print(f"    [warn] {cp['id']} fallbackNote {lg} failed: {e}")
        cp["aiContext"] = {"facts": facts, "fallbackNote": note}
        built += 1
        print(f"[ok] {cp['id']}: {len(facts)} facts + fallbackNote({','.join(note)})")

    yaml.safe_dump(doc, open(args.content, "w", encoding="utf-8"),
                   allow_unicode=True, sort_keys=False)
    print(f"\nDone: built {built}, skipped {skipped}"
          + (f", FAILED {failed} (re-run to retry)" if failed else "")
          + f" -> {args.content}")


if __name__ == "__main__":
    main()
