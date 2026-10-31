"""Représentation des sous-titres et export SRT / WebVTT.

Règles de lisibilité appliquées (standards du sous-titrage professionnel) :
  * 42 caractères max par ligne, 2 lignes max par sous-titre ;
  * une phrase trop longue est découpée en plusieurs sous-titres,
    le temps étant réparti au prorata du nombre de caractères ;
  * durée d'affichage minimale de 0,8 s, sans chevaucher le suivant.
"""
from __future__ import annotations

import textwrap
from dataclasses import dataclass, replace

MAX_LINE = 42
MAX_LINES = 2
MIN_DURATION = 0.8


@dataclass(slots=True)
class Cue:
    start: float  # secondes
    end: float
    text: str


def _ts(seconds: float, sep: str) -> str:
    ms = max(0, round(seconds * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}{sep}{ms:03d}"


def _wrap(text: str) -> list[str]:
    return textwrap.wrap(" ".join(text.split()), width=MAX_LINE, break_long_words=False) or [""]


def split_long_cues(cues: list[Cue]) -> list[Cue]:
    """Découpe les cues qui ne tiennent pas sur 2 lignes."""
    out: list[Cue] = []
    for cue in cues:
        lines = _wrap(cue.text)
        if len(lines) <= MAX_LINES:
            out.append(replace(cue, text="\n".join(lines)))
            continue
        chunks = ["\n".join(lines[i : i + MAX_LINES]) for i in range(0, len(lines), MAX_LINES)]
        total_chars = sum(len(c) for c in chunks)
        t = cue.start
        for chunk in chunks:
            dur = (cue.end - cue.start) * len(chunk) / total_chars
            out.append(Cue(t, t + dur, chunk))
            t += dur
    return out


def normalize_timing(cues: list[Cue]) -> list[Cue]:
    """Durée minimale + suppression des chevauchements + retrait des cues vides."""
    cues = sorted((c for c in cues if c.text.strip()), key=lambda c: c.start)
    out: list[Cue] = []
    for i, c in enumerate(cues):
        end = max(c.end, c.start + MIN_DURATION)
        if i + 1 < len(cues):
            end = min(end, cues[i + 1].start - 0.04)
        if end > c.start:
            out.append(Cue(c.start, end, c.text.strip()))
    return out


def to_srt(cues: list[Cue]) -> str:
    blocks = [
        f"{i}\n{_ts(c.start, ',')} --> {_ts(c.end, ',')}\n{c.text}"
        for i, c in enumerate(cues, start=1)
    ]
    return "\n\n".join(blocks) + "\n"


def to_vtt(cues: list[Cue]) -> str:
    body = "\n\n".join(f"{_ts(c.start, '.')} --> {_ts(c.end, '.')}\n{c.text}" for c in cues)
    return "WEBVTT\n\n" + body + "\n"


def render(cues: list[Cue], fmt: str) -> str:
    cues = normalize_timing(split_long_cues(cues))
    if fmt == "vtt":
        return to_vtt(cues)
    return to_srt(cues)
