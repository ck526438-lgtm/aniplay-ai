"""Routes de génération de sous-titres par IA."""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.services.media import MediaError
from app.services.subtitles.jobs import JobStatus, SubtitleJob, SubtitleJobManager
from app.services.subtitles.languages import DEFAULT_TARGET, catalog

router = APIRouter(prefix="/api/v1/subtitles", tags=["subtitles"])


class SubtitleRequest(BaseModel):
    source: str = Field(
        ...,
        description="Chemin relatif à ANIPLAY_MEDIA_ROOT, chemin absolu (mode local) ou URL http(s)",
        examples=["frieren/ep05.mkv"],
    )
    target_lang: str = Field(DEFAULT_TARGET, description="Langue des sous-titres (ISO 639-1)")
    source_lang: str | None = Field(None, description="Langue parlée ; vide = détection auto")
    format: Literal["srt", "vtt"] = "srt"
    audio_track: int | None = Field(None, ge=0, description="Index de la piste audio (0 = 1re)")


class SubtitleJobOut(BaseModel):
    id: str
    status: JobStatus
    progress: float
    target_lang: str
    detected_language: str | None
    cue_count: int
    error: str | None
    download_url: str | None
    original_url: str | None


def _manager(request: Request) -> SubtitleJobManager:
    return request.app.state.subtitle_jobs


def _out(request: Request, job: SubtitleJob) -> SubtitleJobOut:
    mgr = _manager(request)
    base = str(request.url_for("download_subtitle", job_id=job.id))
    has_orig = mgr.output_path(job, original=True).is_file()
    return SubtitleJobOut(
        id=job.id, status=job.status, progress=job.progress, target_lang=job.target_lang,
        detected_language=job.detected_language, cue_count=job.cue_count, error=job.error,
        download_url=base if job.status is JobStatus.done else None,
        original_url=f"{base}?original=true" if has_orig else None,
    )


@router.get("/languages")
async def languages() -> list[dict[str, str]]:
    """Langues disponibles pour la traduction."""
    return catalog()


@router.post("", response_model=SubtitleJobOut, status_code=202)
async def create_job(request: Request, req: SubtitleRequest) -> SubtitleJobOut:
    """Lance la génération. Suivre ensuite GET /jobs/{id} jusqu'à status=done."""
    try:
        job = _manager(request).submit(
            req.source, req.target_lang, req.source_lang, req.format, req.audio_track
        )
    except (MediaError, ValueError) as exc:
        raise HTTPException(422, str(exc)) from exc
    return _out(request, job)


@router.get("/jobs/{job_id}", response_model=SubtitleJobOut)
async def job_status(request: Request, job_id: str) -> SubtitleJobOut:
    job = _manager(request).get(job_id)
    if job is None:
        raise HTTPException(404, "Job inconnu")
    return _out(request, job)


@router.get("/jobs/{job_id}/file", name="download_subtitle")
async def download_subtitle(request: Request, job_id: str, original: bool = False):
    mgr = _manager(request)
    job = mgr.get(job_id)
    if job is None:
        raise HTTPException(404, "Job inconnu")
    path = mgr.output_path(job, original=original)
    if not path.is_file():
        raise HTTPException(409, "Sous-titres pas encore prêts")
    lang = (job.detected_language or "orig") if original else job.target_lang
    media_type = "text/vtt" if job.fmt == "vtt" else "application/x-subrip"
    return FileResponse(
        path, media_type=f"{media_type}; charset=utf-8", filename=f"aniplay.{lang}.{job.fmt}"
    )
