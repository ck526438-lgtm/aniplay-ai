"""Recherche de la plus longue séquence commune entre deux suites de descripteurs.

Principe (identique pour l'audio et le visuel) :
1. Chaque épisode est réduit à une suite de vecteurs (1 vecteur = un pas de temps).
2. On calcule la matrice de similarité cosinus S[i, j] entre l'épisode A et B.
3. Un opening commun apparaît comme une DIAGONALE de fortes similarités :
   le même contenu, à la même vitesse, décalé d'un offset constant.
4. On cherche la plus longue diagonale au-dessus d'un seuil, en tolérant de
   petits trous (glitchs d'encodage, logo de chaîne, etc.).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(slots=True)
class Match:
    start_a: int  # index de début dans la séquence A
    start_b: int  # index de début dans la séquence B
    length: int  # longueur en nombre de pas
    score: float  # similarité moyenne sur la diagonale retenue


def normalize(features: np.ndarray, center: bool = True) -> np.ndarray:
    """Centre (optionnel) puis normalise chaque vecteur en L2.

    Le centrage retire la « couleur » moyenne de l'épisode, ce qui augmente
    fortement le contraste entre contenu commun et contenu différent.
    """
    x = np.asarray(features, dtype=np.float32)
    if x.ndim != 2 or x.shape[0] == 0:
        raise ValueError("features doit être une matrice (temps, dimensions) non vide")
    if center:
        x = x - x.mean(axis=0, keepdims=True)
    norms = np.linalg.norm(x, axis=1, keepdims=True)
    return x / np.maximum(norms, 1e-8)


def _fill_gaps(mask: np.ndarray, max_gap: int) -> np.ndarray:
    """Comble les trous de longueur <= max_gap entre deux zones vraies."""
    if max_gap <= 0 or not mask.any():
        return mask
    out = mask.copy()
    idx = np.flatnonzero(mask)
    gaps = np.diff(idx) - 1
    for k in np.flatnonzero((gaps > 0) & (gaps <= max_gap)):
        out[idx[k] + 1 : idx[k + 1]] = True
    return out


def _longest_run(mask: np.ndarray) -> tuple[int, int]:
    """Renvoie (début, longueur) de la plus longue suite de True."""
    if not mask.any():
        return 0, 0
    padded = np.concatenate(([False], mask, [False])).astype(np.int8)
    edges = np.diff(padded)
    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)
    lengths = ends - starts
    k = int(np.argmax(lengths))
    return int(starts[k]), int(lengths[k])


def find_common_segment(
    a: np.ndarray,
    b: np.ndarray,
    threshold: float = 0.6,
    min_length: int = 30,
    max_gap: int = 3,
    adaptive_quantile: float | None = 0.99,
    max_threshold: float = 0.93,
) -> Match | None:
    """Trouve la plus longue séquence commune entre A et B (déjà normalisées).

    :param threshold: similarité cosinus minimale (plancher) pour qu'un pas soit « identique »
    :param min_length: longueur minimale (en pas) pour accepter un résultat
    :param max_gap: nombre de pas non concordants tolérés à l'intérieur d'un segment
    :param adaptive_quantile: si défini, le seuil est relevé au quantile correspondant
        de toute la matrice. Un vrai générique n'occupe qu'une diagonale (< 1 % des
        cellules) : on ne garde donc que l'élite des similarités, ce qui rend la
        détection robuste aux séries dont toute la bande-son « se ressemble ».
    :param max_threshold: plafond du seuil adaptatif (évite de tout rejeter)
    """
    sim = a @ b.T  # (n, m)
    n, m = sim.shape
    if adaptive_quantile is not None:
        threshold = min(max(threshold, float(np.quantile(sim, adaptive_quantile))), max_threshold)
    best: Match | None = None

    # Diagonale k : S[i, i + k]. k < 0 → l'opening est plus tard dans A que dans B.
    for k in range(-(n - min_length), m - min_length + 1):
        diag = np.diagonal(sim, offset=k)
        if diag.size < min_length:
            continue
        mask = _fill_gaps(diag >= threshold, max_gap)
        start, length = _longest_run(mask)
        if length < min_length:
            continue
        score = float(diag[start : start + length].mean())
        if best is None or (length, score) > (best.length, best.score):
            i0 = start + max(0, -k)
            j0 = start + max(0, k)
            best = Match(start_a=i0, start_b=j0, length=length, score=score)
    return best
