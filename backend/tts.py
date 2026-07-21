"""TTS providers — both run on Azure, selected by env TTS_PROVIDER.

  speech  -> Azure Speech neural voices (RECOMMENDED for Hindi quality:
             hi-IN-SwaraNeural). Needs a Speech resource key+region.
  openai  -> Azure OpenAI TTS deployment (e.g. gpt-4o-mini-tts) through
             the same AI Foundry endpoint you already use for GPT-4o.

Run the 10-minute listen test tonight (README §4) and set TTS_PROVIDER once.
Output is MP3 in both cases (AVAudioPlayer plays MP3 natively).
"""
import os
import time

import requests

VOICES_SPEECH = {
    "en": os.getenv("SPEECH_VOICE_EN", "en-IN-NeerjaNeural"),
    "hi": os.getenv("SPEECH_VOICE_HI", "hi-IN-SwaraNeural"),
    "fr": os.getenv("SPEECH_VOICE_FR", "fr-FR-DeniseNeural"),
    "es": os.getenv("SPEECH_VOICE_ES", "es-ES-ElviraNeural"),
}
XML_LANG = {"en": "en-IN", "hi": "hi-IN", "fr": "fr-FR", "es": "es-ES"}
# Azure OpenAI TTS voices are multilingual; one voice handles both languages.
VOICE_OPENAI = os.getenv("OPENAI_TTS_VOICE", "alloy")


class AzureSpeechTTS:
    def __init__(self):
        self.key = os.environ["AZURE_SPEECH_KEY"]
        self.region = os.environ["AZURE_SPEECH_REGION"]
        self.url = (
            f"https://{self.region}.tts.speech.microsoft.com/cognitiveservices/v1"
        )

    def synthesize(self, text: str, lang: str) -> bytes:
        voice = VOICES_SPEECH.get(lang, VOICES_SPEECH["en"])
        xml_lang = XML_LANG.get(lang, "en-IN")
        ssml = (
            f"<speak version='1.0' xml:lang='{xml_lang}'>"
            f"<voice name='{voice}'>{_xml_escape(text)}</voice></speak>"
        )
        for attempt in range(3):  # §B: backoff retries on 429/5xx
            r = requests.post(
                self.url,
                headers={
                    "Ocp-Apim-Subscription-Key": self.key,
                    "Content-Type": "application/ssml+xml",
                    "X-Microsoft-OutputFormat": "audio-24khz-96kbitrate-mono-mp3",
                    "User-Agent": "district-tour-guide",
                },
                data=ssml.encode("utf-8"),
                timeout=30,
            )
            if r.status_code == 429 or r.status_code >= 500:
                if attempt < 2:
                    time.sleep(0.5 * 2 ** attempt)
                    continue
            r.raise_for_status()
            return r.content


class AzureOpenAITTS:
    def __init__(self):
        from openai import AzureOpenAI

        self.client = AzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_API_KEY"],
            api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2025-04-01-preview"),
        )
        self.deployment = os.environ["AZURE_TTS_DEPLOYMENT"]

    def synthesize(self, text: str, lang: str) -> bytes:
        resp = self.client.audio.speech.create(
            model=self.deployment,
            voice=VOICE_OPENAI,
            input=text,
            response_format="mp3",
        )
        return resp.content


def _xml_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )


def get_tts():
    provider = os.getenv("TTS_PROVIDER", "speech").lower()
    if provider == "openai":
        return AzureOpenAITTS()
    return AzureSpeechTTS()
