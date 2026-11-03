"""Moteurs IA : transcription (Whisper) et traduction (OPUS-MT ou NLLB-200).

Les deux sont 100 % locaux et open-source : aucune clé d'API, aucun envoi de
données. Les modèles sont téléchargés automatiquement au premier usage
(~150 Mo pour Whisper « base », ~300 Mo par paire OPUS-MT, ~1,1 Go pour NLLB
600M) puis mis en cache.

Les imports lourds sont paresseux : le backend démarre même si ces
dépendances optionnelles (requirements-subtitles.txt) ne sont pas installées.
"""
from __future__ import annotations

import logging
import threading
from collections.abc import Callable, Iterator
from typing import Protocol

import numpy as np

from app.services.subtitles.formats import Cue
from app.services.subtitles.languages import nllb_code, opus_model

log = logging.getLogger(__name__)

ProgressFn = Callable[[float], None]


class EngineUnavailable(RuntimeError):
    """Dépendance IA manquante : message clair pour l'utilisateur."""


# ---------------------------------------------------------------- Protocoles
class Transcriber(Protocol):
    def transcribe(
        self, audio: np.ndarray, language: str | None, on_progress: ProgressFn
    ) -> tuple[list[Cue], str]:
        """Retourne (cues dans la langue parlée, code ISO de la langue détectée)."""
        ...


class Translator(Protocol):
    def translate(
        self, texts: list[str], source: str, target: str, on_progress: ProgressFn
    ) -> list[str]: ...


# ------------------------------------------------------------- Whisper
class WhisperTranscriber:
    """faster-whisper (CTranslate2) : 4× plus rapide que Whisper d'OpenAI, même précision."""

    def __init__(self, model_size: str = "small", device: str = "auto", compute_type: str = "auto"):
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self._model = None
        self._lock = threading.Lock()

    def _load(self):
        with self._lock:
            if self._model is None:
                try:
                    from faster_whisper import WhisperModel
                except ImportError as exc:
                    raise EngineUnavailable(
                        "faster-whisper n'est pas installé : pip install -r requirements-subtitles.txt"
                    ) from exc
                log.info("Chargement de Whisper « %s »…", self.model_size)
                self._model = WhisperModel(
                    self.model_size, device=self.device, compute_type=self.compute_type
                )
        return self._model

    def transcribe(
        self, audio: np.ndarray, language: str | None, on_progress: ProgressFn
    ) -> tuple[list[Cue], str]:
        model = self._load()
        segments, info = model.transcribe(
            audio,
            language=language,
            task="transcribe",
            vad_filter=True,  # ignore musique/silences : moins d'hallucinations
            vad_parameters={"min_silence_duration_ms": 400},
            beam_size=5,
            condition_on_previous_text=False,  # évite les boucles de répétition
        )
        duration = max(float(info.duration), 1e-6)
        cues: list[Cue] = []
        for seg in segments:  # générateur : la transcription avance ici
            text = seg.text.strip()
            if text:
                cues.append(Cue(float(seg.start), float(seg.end), text))
            on_progress(min(1.0, float(seg.end) / duration))
        log.info("Langue détectée : %s (%.0f %%)", info.language, 100 * info.language_probability)
        return cues, info.language


# ------------------------------------------------------------- OPUS-MT
class OpusMtTranslator:
    """OPUS-MT (Marian) : ~300 Mo par paire de langues, pensé pour le CPU.

    Seule la paire en cours reste en mémoire : changer de langue décharge le
    modèle précédent, ce qui tient sur un PC de 8 Go.
    """

    def __init__(self, batch_size: int = 16):
        self.batch_size = batch_size
        self._pair: tuple[str, str] | None = None
        self._tok = None
        self._model = None
        self._lock = threading.Lock()

    def _load(self, source: str, target: str):
        with self._lock:
            if self._pair == (source, target):
                return self._tok, self._model
            try:
                from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
            except ImportError as exc:
                raise EngineUnavailable(
                    "transformers/torch ne sont pas installés : "
                    "pip install -r requirements-subtitles.txt"
                ) from exc
            name = opus_model(source, target)
            log.info("Chargement de %s…", name)
            try:
                tok = AutoTokenizer.from_pretrained(name)
                model = AutoModelForSeq2SeqLM.from_pretrained(name)
            except Exception as exc:
                raise ValueError(
                    f"OPUS-MT ne publie pas de modèle « {source} → {target} ». "
                    "Passe ANIPLAY_TRANSLATOR=nllb pour cette paire."
                ) from exc
            self._tok, self._model, self._pair = tok, model.eval(), (source, target)
        return self._tok, self._model

    def translate(
        self, texts: list[str], source: str, target: str, on_progress: ProgressFn
    ) -> list[str]:
        if not texts:
            return []
        import torch

        tok, model = self._load(source, target)
        out: list[str] = []
        for batch in _batches(texts, self.batch_size):
            enc = tok(batch, return_tensors="pt", padding=True, truncation=True, max_length=256)
            with torch.inference_mode():
                gen = model.generate(**enc, max_new_tokens=200)
            out.extend(tok.batch_decode(gen, skip_special_tokens=True))
            on_progress(len(out) / len(texts))
        return out


# ------------------------------------------------------------- NLLB-200
class NllbTranslator:
    """Meta NLLB-200 : un seul modèle pour traduire entre 200 langues."""

    def __init__(
        self,
        model_name: str = "facebook/nllb-200-distilled-600M",
        batch_size: int = 16,
        num_beams: int = 2,
    ):
        self.model_name = model_name
        self.batch_size = batch_size
        self.num_beams = num_beams
        self._tok = None
        self._model = None
        self._lock = threading.Lock()

    def _load(self):
        with self._lock:
            if self._model is None:
                try:
                    import torch
                    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
                except ImportError as exc:
                    raise EngineUnavailable(
                        "transformers/torch ne sont pas installés : "
                        "pip install -r requirements-subtitles.txt"
                    ) from exc
                log.info("Chargement de %s…", self.model_name)
                self._tok = AutoTokenizer.from_pretrained(self.model_name)
                # bfloat16 : 1,2 Go de RAM au lieu de 2,4 Go en fp32, précision équivalente.
                # Indispensable pour tourner sur un PC de bureau sans GPU.
                self._model = AutoModelForSeq2SeqLM.from_pretrained(
                    self.model_name, dtype=torch.bfloat16
                )
                self._model.to("cuda" if torch.cuda.is_available() else "cpu").eval()
        return self._tok, self._model

    def translate(
        self, texts: list[str], source: str, target: str, on_progress: ProgressFn
    ) -> list[str]:
        if not texts:
            return []
        import torch

        tok, model = self._load()
        tok.src_lang = nllb_code(source)
        forced_bos = tok.convert_tokens_to_ids(nllb_code(target))
        out: list[str] = []
        for batch in _batches(texts, self.batch_size):
            enc = tok(batch, return_tensors="pt", padding=True, truncation=True, max_length=256)
            enc = {k: v.to(model.device) for k, v in enc.items()}
            with torch.inference_mode():
                gen = model.generate(
                    **enc, forced_bos_token_id=forced_bos,
                    max_new_tokens=200, num_beams=self.num_beams,
                )
            out.extend(tok.batch_decode(gen, skip_special_tokens=True))
            on_progress(len(out) / len(texts))
        return out


def _batches(items: list[str], size: int) -> Iterator[list[str]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]
