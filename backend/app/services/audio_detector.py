"""Détection locale des openings/endings par empreinte audio (librosa).

Idée : l'opening d'une série est la MÊME musique d'un épisode à l'autre.
On extrait des descripteurs harmoniques robustes (Chroma CENS : insensibles au
volume et au timbre, stables face aux légères variations d'encodage), puis on
cherche la plus longue séquence commune entre l'épisode cible et des épisodes
de référence (voir matching.py).
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from app.services import media
from app.services.matching import find_common_segment, normalize

log = logging.getLogger(__name__)

SAMPLE_RATE = 11025
HOP_LENGTH = 512  # ≈ 21,5 trames/s avant ré-échantillonnage
STEPS_PER_SECOND = 2  # résolution finale : 0,5 s


@dataclass(slots=True)
class DetectedInterval:
    start: float  # secondes, dans l'épisode cible
    end: float
    score: float  # similarité moyenne [−1, 1]


def audio_fingerprint(audio: np.ndarray, sr: int = SAMPLE_RATE) -> np.ndarray:
    """Calcule une suite de descripteurs (temps, 12 + 12) à STEPS_PER_SECOND pas/seconde."""
    import librosa  # import paresseux : l'API démarre même sans librosa installé

    # Harmonie (mélodie/accords) : cœur de l'empreinte
    chroma = librosa.feature.chroma_cens(y=audio, sr=sr, hop_length=HOP_LENGTH)  # (12, T)
    # Timbre (voix/instruments) : MFCC 1..12, le coefficient 0 (volume) est ignoré
    mfcc = librosa.feature.mfcc(y=audio, sr=sr, hop_length=HOP_LENGTH, n_mfcc=13)[1:]  # (12, T)

    t = min(chroma.shape[1], mfcc.shape[1])
    if t == 0:
        raise ValueError("Signal audio trop court pour une empreinte")
    chroma, mfcc = _zscore(chroma[:, :t].T), _zscore(mfcc[:, :t].T)
    feats = np.hstack([chroma, 0.5 * mfcc])  # (T, 24) — le chroma pèse davantage

    # Ré-échantillonnage EXACT sur l'axe du temps → STEPS_PER_SECOND pas/seconde.
    # (Un regroupement par blocs entiers ferait dériver l'horloge de ~2 %.)
    step_idx = np.floor(np.arange(t) * HOP_LENGTH / sr * STEPS_PER_SECOND).astype(int)
    n_steps = step_idx[-1] + 1
    out = np.zeros((n_steps, feats.shape[1]), dtype=np.float64)
    np.add.at(out, step_idx, feats)
    counts = np.bincount(step_idx, minlength=n_steps)[:, None]
    return (out / np.maximum(counts, 1)).astype(np.float32)


def _zscore(x: np.ndarray) -> np.ndarray:
    """Standardise chaque dimension : aucune famille de descripteurs n'écrase l'autre."""
    return (x - x.mean(axis=0)) / (x.std(axis=0) + 1e-6)


def detect_in_window(
    target: Path,
    reference: Path,
    window: tuple[float, float],
    ref_window: tuple[float, float],
    min_seconds: float = 45.0,
    max_seconds: float = 140.0,
    threshold: float = 0.55,
) -> DetectedInterval | None:
    """Cherche une séquence audio commune entre deux fenêtres temporelles.

    :param window: (offset, durée) dans l'épisode cible
    :param ref_window: (offset, durée) dans l'épisode de référence
    """
    fa = normalize(audio_fingerprint(media.load_audio(target, *window, sr=SAMPLE_RATE)))
    fb = normalize(audio_fingerprint(media.load_audio(reference, *ref_window, sr=SAMPLE_RATE)))

    match = find_common_segment(
        fa, fb, threshold=threshold, min_length=int(min_seconds * STEPS_PER_SECOND), max_gap=4
    )
    if match is None:
        return None

    duration = match.length / STEPS_PER_SECOND
    if duration > max_seconds * 1.15:
        # Trop long pour un générique : sûrement deux épisodes quasi identiques
        # (recap, doublon). On refuse plutôt que de sauter du contenu.
        log.info("Segment commun de %.0fs rejeté (trop long)", duration)
        return None

    start = window[0] + match.start_a / STEPS_PER_SECOND
    return DetectedInterval(start=start, end=start + duration, score=match.score)
