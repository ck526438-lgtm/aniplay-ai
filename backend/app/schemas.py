"""Modèles de données exposés par l'API.

Le frontend ne connaît QUE ces modèles : peu importe que les segments viennent
d'AniSkip ou de la détection locale, le format est identique.
"""
from enum import Enum

from pydantic import BaseModel, Field, model_validator


class SegmentType(str, Enum):
    opening = "op"
    ending = "ed"
    mixed_opening = "mixed-op"
    mixed_ending = "mixed-ed"
    recap = "recap"


class SegmentSource(str, Enum):
    aniskip = "aniskip"
    local_audio = "local-audio"
    local_visual = "local-visual"


class SkipSegment(BaseModel):
    type: SegmentType
    start: float = Field(ge=0, description="Début du segment en secondes")
    end: float = Field(gt=0, description="Fin du segment en secondes")
    source: SegmentSource
    confidence: float = Field(1.0, ge=0, le=1)
    skip_id: str | None = None

    @model_validator(mode="after")
    def _check_order(self) -> "SkipSegment":
        if self.end <= self.start:
            raise ValueError("end doit être strictement supérieur à start")
        return self

    @property
    def duration(self) -> float:
        return self.end - self.start


class SkipTimesResponse(BaseModel):
    mal_id: int | None = None
    episode: float | None = None
    found: bool
    source: SegmentSource | None = None
    segments: list[SkipSegment] = []
    message: str | None = None


class AnalyzeRequest(BaseModel):
    """Détection locale : on compare l'épisode cible à d'autres épisodes de la même série.

    Les chemins sont relatifs à ANIPLAY_MEDIA_ROOT (sécurité : pas d'accès hors de ce dossier).
    """

    target: str = Field(..., examples=["one-piece/ep1080.mkv"])
    references: list[str] = Field(..., min_length=1, examples=[["one-piece/ep1079.mkv"]])
    detect: list[SegmentType] = [SegmentType.opening, SegmentType.ending]
    use_visual: bool = Field(True, description="Utiliser l'analyse visuelle si l'audio échoue")
