"""Test de bout en bout du détecteur audio sur des épisodes synthétiques.

On fabrique un « opening » musical de 60 s, inséré à des positions différentes
dans deux épisodes dont le reste est du contenu aléatoire (dialogues simulés).
"""
import shutil

import numpy as np
import pytest

pytest.importorskip("librosa")
sf = pytest.importorskip("soundfile")
pytestmark = pytest.mark.skipif(not shutil.which("ffmpeg"), reason="ffmpeg requis")

from app.services.audio_detector import SAMPLE_RATE, detect_in_window

SR = SAMPLE_RATE


def _melody(seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    notes = rng.choice([220, 247, 262, 294, 330, 349, 392, 440, 494, 523], size=int(seconds * 4))
    t = np.arange(int(SR / 4)) / SR
    env = np.exp(-3 * t)
    return np.concatenate(
        [(np.sin(2 * np.pi * f * t) + 0.5 * np.sin(4 * np.pi * f * t)) * env for f in notes]
    ).astype(np.float32)


def _noise(seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    base = _melody(seconds, seed + 100) * 0.3
    return (base + 0.2 * rng.normal(size=base.size)).astype(np.float32)


def test_detects_opening_between_two_episodes(tmp_path):
    opening = _melody(60, seed=42)
    ep1 = np.concatenate([_noise(30, 1), opening, _noise(90, 2)])
    ep2 = np.concatenate([_noise(12, 3), opening * 0.8, _noise(108, 4)])  # volume différent
    p1, p2 = tmp_path / "ep1.wav", tmp_path / "ep2.wav"
    sf.write(p1, ep1, SR)
    sf.write(p2, ep2, SR)

    hit = detect_in_window(p1, p2, (0, 180), (0, 180), min_seconds=40, max_seconds=100)
    assert hit is not None
    assert hit.start == pytest.approx(30, abs=2.0)
    assert hit.end == pytest.approx(90, abs=2.0)
