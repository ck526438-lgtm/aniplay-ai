"""Routes HTTP de l'API v1."""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from app.schemas import AnalyzeRequest, SegmentType, SkipTimesResponse
from app.services.skip_service import SkipService

router = APIRouter(prefix="/api/v1", tags=["skip"])


def get_service(request: Request) -> SkipService:
    return request.app.state.skip_service


ServiceDep = Annotated[SkipService, Depends(get_service)]


def _parse_types(types: str) -> list[SegmentType]:
    try:
        return [SegmentType(t.strip()) for t in types.split(",") if t.strip()]
    except ValueError as exc:
        allowed = ", ".join(t.value for t in SegmentType)
        raise HTTPException(422, f"Type inconnu. Valeurs autorisées : {allowed}") from exc


@router.get("/skip-times/{mal_id}/{episode}", response_model=SkipTimesResponse)
async def get_skip_times(
    service: ServiceDep,
    mal_id: int,
    episode: float,
    episode_length: Annotated[float, Query(ge=0, description="Durée du fichier (s)")] = 0.0,
    types: Annotated[str, Query(description="Ex : op,ed,recap")] = "op,ed",
) -> SkipTimesResponse:
    """Segments à passer pour un épisode, via AniSkip uniquement (rapide, sans fichier)."""
    if mal_id <= 0 or episode <= 0:
        raise HTTPException(422, "mal_id et episode doivent être positifs")
    return await service.from_aniskip(mal_id, episode, episode_length, _parse_types(types))


@router.post("/skip-times/{mal_id}/{episode}/resolve", response_model=SkipTimesResponse)
async def resolve_skip_times(
    service: ServiceDep,
    mal_id: int,
    episode: float,
    local: AnalyzeRequest | None = None,
    episode_length: Annotated[float, Query(ge=0)] = 0.0,
    types: str = "op,ed",
) -> SkipTimesResponse:
    """AniSkip d'abord ; si rien n'est trouvé, détection IA locale sur les fichiers fournis."""
    return await service.resolve(mal_id, episode, episode_length, _parse_types(types), local)


@router.post("/analyze", response_model=SkipTimesResponse)
async def analyze_local(service: ServiceDep, req: AnalyzeRequest) -> SkipTimesResponse:
    """Détection IA locale seule (épisodes inconnus d'AniSkip, fansubs, fichiers perso)."""
    return await service.analyze(req)


@router.get("/debug/aniskip", response_model=SkipTimesResponse, tags=["debug"])
async def debug_aniskip(
    service: ServiceDep, mal_id: int = 21, episode: float = 1
) -> SkipTimesResponse:
    """Route de test d'intégration : interroge AniSkip sans cache (One Piece ép. 1 par défaut)."""
    try:
        res = await service.aniskip.get_skip_times(mal_id, episode, use_cache=False)
    except Exception as exc:  # noqa: BLE001 - route de diagnostic
        return SkipTimesResponse(mal_id=mal_id, episode=episode, found=False, message=str(exc))
    return SkipTimesResponse(
        mal_id=mal_id, episode=episode, found=res.found,
        source="aniskip" if res.found else None, segments=res.segments, message=res.message,
    )
