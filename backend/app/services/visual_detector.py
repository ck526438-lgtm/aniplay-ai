"""Détection locale par motifs visuels récurrents (OpenCV).

Utile quand l'audio change d'un épisode à l'autre (doublage différent,
musique remixée) mais que l'animation du générique reste identique.

Chaque image échantillonnée (1/s) est réduite à un hash perceptuel « dHash »
de 64 bits, converti en vecteur ±1 : la similarité cosinus entre deux vecteurs
vaut alors 1 − 2·(distance de Hamming / 64). On réutilise ensuite exactement
le même algorithme de diagonale que pour l'audio.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

from app.services.audio_detector import DetectedInterval
from app.services.matching import find_common_segment, normalize
from app.services.media import MediaError

FPS_SAMPLE = 1.0
HASH_SIZE = 8


def _dhash(gray: np.ndarray) -> np.ndarray:
    import cv2

    small = cv2.resize(gray, (HASH_SIZE + 1, HASH_SIZE), interpolation=cv2.INTER_AREA)
    bits = small[:, 1:] > small[:, :-1]
    return np.where(bits.flatten(), 1.0, -1.0).astype(np.float32)


def visual_fingerprint(path: Path, offset: float, duration: float) -> np.ndarray:
    import cv2

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise MediaError(f"OpenCV ne peut pas ouvrir {path.name}")
    try:
        cap.set(cv2.CAP_PROP_POS_MSEC, offset * 1000)
        hashes: list[np.ndarray] = []
        next_t = offset
        end_t = offset + duration
        while True:
            if not cap.grab():
                break
            t = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000
            if t > end_t:
                break
            if t + 1e-3 < next_t:
                continue  # on ne décode que les images utiles (grab est peu coûteux)
            ok, frame = cap.retrieve()
            if not ok:
                break
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            hashes.append(_dhash(gray))
            next_t += 1.0 / FPS_SAMPLE
    finally:
        cap.release()

    if len(hashes) < 10:
        raise MediaError(f"Trop peu d'images exploitables dans {path.name}")
    return np.stack(hashes)


def detect_in_window(
    target: Path,
    reference: Path,
    window: tuple[float, float],
    ref_window: tuple[float, float],
    min_seconds: float = 45.0,
    max_seconds: float = 140.0,
    threshold: float = 0.75,
) -> DetectedInterval | None:
    # Pas de centrage : les hash ±1 sont déjà équilibrés
    fa = normalize(visual_fingerprint(target, *window), center=False)
    fb = normalize(visual_fingerprint(reference, *ref_window), center=False)
    match = find_common_segment(
        fa, fb, threshold=threshold, min_length=int(min_seconds * FPS_SAMPLE), max_gap=3
    )
    if match is None:
        return None
    duration = match.length / FPS_SAMPLE
    if duration > max_seconds * 1.15:
        return None
    start = window[0] + match.start_a / FPS_SAMPLE
    return DetectedInterval(start=start, end=start + duration, score=match.score)
