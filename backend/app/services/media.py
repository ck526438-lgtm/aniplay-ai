"""Accès bas niveau aux fichiers médias via ffmpeg/ffprobe (robuste pour mkv, mp4, webm...)."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

# Sous Windows, le backend de l'application tourne sans console : sans ce drapeau, chaque appel
# à ffmpeg/ffprobe ferait clignoter une fenêtre noire.
_NO_WINDOW = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0


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
        out = subprocess.run(
            cmd, capture_output=True, check=True, timeout=30, creationflags=_NO_WINDOW
        ).stdout
        return float(json.loads(out)["format"]["duration"])
    except (subprocess.SubprocessError, KeyError, ValueError) as exc:
        raise MediaError(f"Impossible de lire la durée de {path.name}: {exc}") from exc


def load_audio(
    path: Path | str,
    offset: float = 0.0,
    duration: float | None = None,
    sr: int = 11025,
    audio_track: int | None = None,
    timeout: float = 120,
) -> np.ndarray:
    """Décode une piste audio (ou une portion) en mono float32 à `sr` Hz.

    `path` peut être un fichier local ou une URL http(s)/HLS lisible par ffmpeg.
    `audio_track` choisit la piste (0 = première) pour les fichiers multi-audio (VO/VF).
    """
    name = getattr(path, "name", str(path))
    cmd = [_require("ffmpeg"), "-nostdin", "-v", "error"]
    if offset > 0:
        cmd += ["-ss", f"{offset:.3f}"]
    if duration is not None:
        cmd += ["-t", f"{duration:.3f}"]
    cmd += ["-i", str(path)]
    if audio_track is not None:
        cmd += ["-map", f"0:a:{audio_track}"]
    cmd += ["-vn", "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    try:
        raw = subprocess.run(
            cmd, capture_output=True, check=True, timeout=timeout, creationflags=_NO_WINDOW
        ).stdout
    except subprocess.SubprocessError as exc:
        raise MediaError(f"Décodage audio impossible pour {name}: {exc}") from exc
    audio = np.frombuffer(raw, dtype=np.float32)
    if audio.size < sr:  # moins d'une seconde exploitable
        raise MediaError(f"Piste audio vide ou trop courte dans {name}")
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
