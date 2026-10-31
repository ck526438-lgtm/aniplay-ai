"""Accès bas niveau aux fichiers médias via ffmpeg/ffprobe (robuste pour mkv, mp4, webm...)."""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import numpy as np


class MediaError(Exception):
    pass


def _require(binary: str) -> str:
    path = shutil.which(binary)
    if not path:
        raise MediaError(f"'{binary}' est introuvable : installez FFmpeg et ajoutez-le au PATH")
    return path


def probe_duration(path: Path) -> float:
    """Durée totale du média en secondes."""
    cmd = [
        _require("ffprobe"), "-v", "error", "-show_entries", "format=duration",
        "-of", "json", str(path),
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, check=True, timeout=30).stdout
        return float(json.loads(out)["format"]["duration"])
    except (subprocess.SubprocessError, KeyError, ValueError) as exc:
        raise MediaError(f"Impossible de lire la durée de {path.name}: {exc}") from exc


def load_audio(path: Path, offset: float, duration: float, sr: int = 11025) -> np.ndarray:
    """Décode une portion de piste audio en mono float32 à `sr` Hz."""
    cmd = [
        _require("ffmpeg"), "-nostdin", "-v", "error",
        "-ss", f"{max(0.0, offset):.3f}", "-t", f"{duration:.3f}", "-i", str(path),
        "-vn", "-ac", "1", "-ar", str(sr), "-f", "f32le", "-",
    ]
    try:
        raw = subprocess.run(cmd, capture_output=True, check=True, timeout=120).stdout
    except subprocess.SubprocessError as exc:
        raise MediaError(f"Décodage audio impossible pour {path.name}: {exc}") from exc
    audio = np.frombuffer(raw, dtype=np.float32)
    if audio.size < sr:  # moins d'une seconde exploitable
        raise MediaError(f"Piste audio vide ou trop courte dans {path.name}")
    return audio


def resolve_media(root: Path, relative: str) -> Path:
    """Résout un chemin utilisateur en l'empêchant de sortir de `root` (anti path traversal)."""
    root = root.resolve()
    candidate = (root / relative).resolve()
    if root != candidate and root not in candidate.parents:
        raise MediaError("Chemin refusé : en dehors du dossier média autorisé")
    if not candidate.is_file():
        raise MediaError(f"Fichier introuvable : {relative}")
    return candidate
