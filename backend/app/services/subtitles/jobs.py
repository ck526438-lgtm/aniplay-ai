"""Génération de sous-titres en tâche de fond.

Transcrire un épisode de 24 min prend de quelques dizaines de secondes (GPU)
à quelques minutes (CPU) : l'API crée donc un JOB, le lecteur suit sa
progression, puis télécharge le fichier.

Étapes :  extraction audio → transcription (langue d'origine) → traduction → fichier
Les deux versions sont conservées : originale (.orig) et traduite.
"""
from __future__ import annotations

import asyncio
import hashlib
import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from urllib.parse import urlparse

from app.config import Settings
from app.services import media
from app.services.subtitles import formats
from app.services.subtitles.engines import EngineUnavailable, Transcriber, Translator
from app.services.subtitles.languages import is_supported

log = logging.getLogger(__name__)

WHISPER_SR = 16_000

# Répartition de la barre de progression entre les étapes
P_EXTRACT, P_TRANSCRIBE, P_TRANSLATE = 0.05, 0.70, 0.25


class JobStatus(str, Enum):
    queued = "queued"
    extracting = "extracting"
    transcribing = "transcribing"
    translating = "translating"
    done = "done"
    error = "error"


@dataclass
class SubtitleJob:
    id: str
    source: str
    target_lang: str
    source_lang: str | None
    fmt: str
    audio_track: int | None
    cache_key: str
    status: JobStatus = JobStatus.queued
    progress: float = 0.0
    detected_language: str | None = None
    cue_count: int = 0
    error: str | None = None
    created_at: float = field(default_factory=time.time)
    finished_at: float | None = None

    @property
    def finished(self) -> bool:
        return self.status in (JobStatus.done, JobStatus.error)


class SubtitleJobManager:
    def __init__(self, settings: Settings, transcriber: Transcriber, translator: Translator):
        self.settings = settings
        self.transcriber = transcriber
        self.translator = translator
        self.out_dir = Path(settings.subtitles_dir)
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self._jobs: dict[str, SubtitleJob] = {}
        self._by_key: dict[str, str] = {}
        self._sem = asyncio.Semaphore(max(1, settings.subtitles_max_jobs))
        self._tasks: set[asyncio.Task] = set()

    # ------------------------------------------------------------ API
    def resolve_source(self, source: str) -> str:
        """Valide la source et renvoie ce que ffmpeg doit lire (chemin ou URL)."""
        parsed = urlparse(source)
        if parsed.scheme in ("http", "https"):
            if not self.settings.allow_remote_media:
                raise media.MediaError("Les URL distantes sont désactivées sur ce serveur")
            return source
        if parsed.scheme and len(parsed.scheme) > 1:  # "C:" n'est pas un schéma
            raise media.MediaError(f"Schéma non pris en charge : {parsed.scheme}")

        path = Path(source)
        if path.is_absolute():
            if not self.settings.local_mode:
                raise media.MediaError(
                    "Chemin absolu refusé : activez ANIPLAY_LOCAL_MODE si le backend "
                    "tourne sur la même machine que le lecteur"
                )
            if not path.is_file():
                raise media.MediaError(f"Fichier introuvable : {source}")
            return str(path)
        return str(media.resolve_media(self.settings.media_root, source))

    def submit(
        self,
        source: str,
        target_lang: str = "fr",
        source_lang: str | None = None,
        fmt: str = "srt",
        audio_track: int | None = None,
    ) -> SubtitleJob:
        if not is_supported(target_lang):
            raise ValueError(f"Langue cible non prise en charge : {target_lang}")
        if source_lang and not is_supported(source_lang):
            raise ValueError(f"Langue source non prise en charge : {source_lang}")
        resolved = self.resolve_source(source)
        key = self._cache_key(resolved, target_lang, source_lang, fmt, audio_track)

        # Même demande déjà en cours ou terminée avec succès → on la réutilise
        existing = self._jobs.get(self._by_key.get(key, ""))
        if existing is not None and existing.status is not JobStatus.error:
            return existing

        job = SubtitleJob(
            id=uuid.uuid4().hex[:12], source=resolved, target_lang=target_lang,
            source_lang=source_lang, fmt=fmt, audio_track=audio_track, cache_key=key,
        )
        self._jobs[job.id] = job
        self._by_key[key] = job.id

        if self.output_path(job).is_file():  # déjà généré lors d'une session précédente
            job.status, job.progress, job.finished_at = JobStatus.done, 1.0, time.time()
            return job

        task = asyncio.create_task(self._run(job))
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return job

    def get(self, job_id: str) -> SubtitleJob | None:
        return self._jobs.get(job_id)

    def output_path(self, job: SubtitleJob, original: bool = False) -> Path:
        suffix = ".orig" if original else ""
        return self.out_dir / f"{job.cache_key}{suffix}.{job.fmt}"

    # ------------------------------------------------------------ worker
    async def _run(self, job: SubtitleJob) -> None:
        async with self._sem:
            try:
                await asyncio.to_thread(self._process, job)
                job.status, job.progress = JobStatus.done, 1.0
            except (media.MediaError, EngineUnavailable, ValueError) as exc:
                job.status, job.error = JobStatus.error, str(exc)
            except Exception as exc:
                log.exception("Échec du job %s", job.id)
                job.status, job.error = JobStatus.error, f"Erreur interne : {exc}"
            finally:
                job.finished_at = time.time()

    def _process(self, job: SubtitleJob) -> None:
        def step(base: float, span: float):
            return lambda p: setattr(job, "progress", round(base + span * p, 4))

        # 1. Extraction audio (16 kHz mono, format attendu par Whisper)
        job.status = JobStatus.extracting
        audio = media.load_audio(
            job.source, sr=WHISPER_SR, audio_track=job.audio_track, timeout=900
        )
        job.progress = P_EXTRACT

        # 2. Transcription dans la langue parlée
        job.status = JobStatus.transcribing
        cues, detected = self.transcriber.transcribe(
            audio, job.source_lang, step(P_EXTRACT, P_TRANSCRIBE)
        )
        job.detected_language = detected
        job.cue_count = len(cues)
        if not cues:
            raise ValueError("Aucune parole détectée dans cette piste audio")
        self._write(self.output_path(job, original=True), cues, job.fmt)

        # 3. Traduction (inutile si l'épisode est déjà dans la langue cible)
        source = job.source_lang or detected
        if source != job.target_lang:
            if not is_supported(source):
                raise ValueError(
                    f"Langue détectée « {source} » non prise en charge pour la traduction "
                    "(la transcription originale reste disponible)"
                )
            job.status = JobStatus.translating
            texts = self.translator.translate(
                [c.text for c in cues], source, job.target_lang,
                step(P_EXTRACT + P_TRANSCRIBE, P_TRANSLATE),
            )
            cues = [formats.Cue(c.start, c.end, t) for c, t in zip(cues, texts, strict=True)]
        self._write(self.output_path(job), cues, job.fmt)

    @staticmethod
    def _write(path: Path, cues: list[formats.Cue], fmt: str) -> None:
        tmp = path.with_suffix(path.suffix + ".part")
        # newline="" : sur Windows, write_text remplacerait \n par \r\n et
        # casserait le format SRT attendu par les lecteurs.
        tmp.write_text(formats.render(cues, fmt), encoding="utf-8", newline="")
        tmp.replace(path)  # écriture atomique : jamais de fichier à moitié écrit

    def _cache_key(
        self, source: str, target: str, src_lang: str | None, fmt: str, track: int | None
    ) -> str:
        p = Path(source)
        identity = f"{source}|{p.stat().st_size}|{p.stat().st_mtime}" if p.is_file() else source
        raw = "|".join(
            [identity, self.settings.whisper_model, self.settings.nllb_model,
             target, src_lang or "auto", fmt, str(track)]
        )
        return hashlib.sha1(raw.encode()).hexdigest()[:20]
