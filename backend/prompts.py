"""Grounding guardrail prompt for the /ask endpoint.

The anti-hallucination stance is a PITCH FEATURE — say it to judges:
answers come only from the curated content pack; the model refuses
to invent history.
"""

SYSTEM_PROMPT_TEMPLATE = """You are the in-app voice guide for {monument_name}, \
speaking to a visitor who is physically standing at the checkpoint "{checkpoint_name}".

STRICT GROUNDING RULES:
1. Answer ONLY from the CONTENT PACK below. It is your entire knowledge of this monument.
2. If the answer is not in the content pack, say you don't have that in this tour yet, \
and redirect to the nearest relevant nugget from the pack. NEVER invent historical facts, \
dates, names, or measurements.
3. Reply in {language_name}. The visitor is listening, not reading: spoken style, \
warm, vivid, maximum 80 words. No lists, no markdown.
4. If asked something unrelated to the monument or the tour, decline in one friendly \
sentence and return to the tour.

CONTENT PACK
============
{facts_section}Monument overview:
{overview}

Current checkpoint: {checkpoint_name}
{checkpoint_intro}

Nuggets at this checkpoint:
{nuggets_block}

Other checkpoints on this tour (for redirecting only):
{other_checkpoints}
"""

LANGUAGE_NAMES = {"en": "English", "hi": "Hindi (Devanagari, natural spoken Hindi)"}


def build_system_prompt(monument: dict, checkpoint: dict, all_checkpoints: list, lang: str) -> str:
    def loc(d):
        if isinstance(d, dict):
            return d.get(lang) or d.get("en") or ""
        return d or ""

    nuggets_block = "\n".join(
        f"- {loc(n['title'])} ({'app-exclusive' if n.get('exclusive') else 'standard'}): {loc(n['text'])}"
        for n in checkpoint.get("nuggets", [])
    )
    other = ", ".join(
        loc(c["name"]) for c in all_checkpoints if c["id"] != checkpoint["id"]
    )

    # Curated fact corpus (verified EN facts, shared with the on-device model so
    # server + on-device answers agree). When present, these are the AUTHORITATIVE
    # grounding the model must answer from; the nugget/intro content below stays as
    # supporting context. When absent, facts_section is "" and the prompt is byte-
    # identical to the pre-corpus behavior.
    ai_context = checkpoint.get("aiContext")
    facts = ai_context.get("facts") if isinstance(ai_context, dict) else None
    if facts:
        facts_lines = "\n".join(f"- {f}" for f in facts)
        facts_section = (
            "VERIFIED FACTS (authoritative — these are your primary source of "
            "truth for this checkpoint; answer from them first):\n"
            f"{facts_lines}\n\n"
        )
    else:
        facts_section = ""

    return SYSTEM_PROMPT_TEMPLATE.format(
        monument_name=loc(monument["name"]),
        checkpoint_name=loc(checkpoint["name"]),
        language_name=LANGUAGE_NAMES.get(lang, "English"),
        facts_section=facts_section,
        overview=loc(monument.get("overview", "")),
        checkpoint_intro=loc(checkpoint.get("intro", "")),
        nuggets_block=nuggets_block or "(none)",
        other_checkpoints=other or "(none)",
    )
