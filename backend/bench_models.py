#!/usr/bin/env python3
"""Model debate, settled by stopwatch.

Times every chat deployment listed in CHAT_DEPLOYMENTS (comma-separated, .env)
on a grounded Hindi question + one TTS call, then prints the verdict.

Qualification rule (from the build brief): a model qualifies if the answer is
grounded (mentions marble/light, no invented facts) AND estimated total voice
round-trip (STT ~1.0s fixed + chat + TTS) stays under 5.0s. Among qualifiers,
pick the fastest; set AZURE_GPT_DEPLOYMENT in .env to the winner.

    python bench_models.py
"""
import os
import time

from dotenv import load_dotenv

load_dotenv()

import yaml  # noqa: E402
from openai import AzureOpenAI  # noqa: E402

from prompts import build_system_prompt  # noqa: E402
from tts import get_tts  # noqa: E402

STT_ESTIMATE_S = 1.0
QUESTION = "संगमरमर पर टॉर्च की रोशनी डालने से क्या होता है?"

client = AzureOpenAI(
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    api_key=os.environ["AZURE_OPENAI_API_KEY"],
    api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2025-04-01-preview"),
)

doc = yaml.safe_load(open("content/taj_mahal.yaml", encoding="utf-8"))
cps = list(doc["checkpoints"])
cp = next(c for c in cps if c["id"] == "cp_main_platform")
system = build_system_prompt(doc["monument"], cp, cps, "hi")

deployments = [
    d.strip()
    for d in os.getenv("CHAT_DEPLOYMENTS", os.getenv("AZURE_GPT_DEPLOYMENT", "gpt-4o")).split(",")
    if d.strip()
]

print(f"question: {QUESTION}\n")

# one TTS timing (same for every model)
tts = get_tts()
t0 = time.perf_counter()
tts.synthesize("संगमरमर पारभासी है, इसलिए रोशनी अंदर जाकर सुनहरी चमक बनकर लौटती है।", "hi")
tts_s = time.perf_counter() - t0
print(f"TTS ({os.getenv('TTS_PROVIDER','speech')}): {tts_s:.2f}s\n")

def _chat(dep):
    msgs = [
        {"role": "system", "content": system},
        {"role": "user", "content": QUESTION},
    ]
    try:
        return client.chat.completions.create(
            model=dep, messages=msgs, max_tokens=220, temperature=0.4
        )
    except Exception as e:
        if "max_tokens" not in str(e):
            raise
        # reasoning models (gpt-5.x): max_completion_tokens, roomy enough
        # that reasoning tokens don't starve the visible answer
        return client.chat.completions.create(
            model=dep, messages=msgs, max_completion_tokens=1000
        )


results = []
for dep in deployments:
    try:
        t0 = time.perf_counter()
        r = _chat(dep)
        chat_s = time.perf_counter() - t0
        answer = r.choices[0].message.content.strip()
        total = STT_ESTIMATE_S + chat_s + tts_s
        results.append((dep, chat_s, total, answer))
        print(f"[{dep}] chat={chat_s:.2f}s  est-total={total:.2f}s")
        print(f"    {answer[:160]}\n")
    except Exception as e:
        print(f"[{dep}] FAILED: {e}\n")

qualified = [r for r in results if r[2] < 5.0]
if qualified:
    win = min(qualified, key=lambda r: r[1])
    print(f"VERDICT: set AZURE_GPT_DEPLOYMENT={win[0]}  (est total {win[2]:.2f}s)")
    print("Confirm the answer above is grounded (marble/light, nothing invented) before locking.")
else:
    print("VERDICT: nothing under 5.0s — use the fastest and shorten max_tokens, or check region co-location.")
