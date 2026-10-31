"""Langues prises en charge et correspondance des codes.

Whisper détecte la langue parlée en code ISO 639-1 (« ja », « en »…),
NLLB-200 attend des codes FLORES-200 (« jpn_Jpan », « fra_Latn »…).
"""
from __future__ import annotations

# code ISO → (code NLLB, nom affiché)
LANGUAGES: dict[str, tuple[str, str]] = {
    "fr": ("fra_Latn", "Français"),
    "en": ("eng_Latn", "Anglais"),
    "ja": ("jpn_Jpan", "Japonais"),
    "ko": ("kor_Hang", "Coréen"),
    "zh": ("zho_Hans", "Chinois (simplifié)"),
    "es": ("spa_Latn", "Espagnol"),
    "pt": ("por_Latn", "Portugais"),
    "de": ("deu_Latn", "Allemand"),
    "it": ("ita_Latn", "Italien"),
    "ru": ("rus_Cyrl", "Russe"),
    "ar": ("arb_Arab", "Arabe"),
    "tr": ("tur_Latn", "Turc"),
    "hi": ("hin_Deva", "Hindi"),
    "id": ("ind_Latn", "Indonésien"),
    "th": ("tha_Thai", "Thaï"),
    "vi": ("vie_Latn", "Vietnamien"),
    "pl": ("pol_Latn", "Polonais"),
    "nl": ("nld_Latn", "Néerlandais"),
    "uk": ("ukr_Cyrl", "Ukrainien"),
    # Langues africaines (qualité de traduction plus variable)
    "sw": ("swh_Latn", "Swahili"),
    "ha": ("hau_Latn", "Haoussa"),
    "yo": ("yor_Latn", "Yoruba"),
    "ln": ("lin_Latn", "Lingala"),
    "wo": ("wol_Latn", "Wolof"),
    "bm": ("bam_Latn", "Bambara"),
    "dyu": ("dyu_Latn", "Dioula"),
    "am": ("amh_Ethi", "Amharique"),
}

DEFAULT_TARGET = "fr"


def nllb_code(iso: str) -> str:
    try:
        return LANGUAGES[iso][0]
    except KeyError as exc:
        raise ValueError(f"Langue non prise en charge : {iso}") from exc


def is_supported(iso: str) -> bool:
    return iso in LANGUAGES


def catalog() -> list[dict[str, str]]:
    return [{"code": k, "name": v[1]} for k, v in LANGUAGES.items()]
