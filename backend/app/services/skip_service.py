"""Orchestration : AniSkip en priorité, détection locale IA en secours.

    Flutter ──► /skip-times ──► AniSkip ──(rien / hors ligne)──► audio ──► visuel
"""
from __future__ import annotations

import asyncio
import logging
import statistics
from pathlib import Path

from app.config import Settings
from app.schemas import (
    AnalyzeRequest,
    SegmentSource,
    SegmentType,
    SkipSegment,
    SkipTimesResponse,
)
from app.services import audio_detector, media, visual_detector
from app.services.aniskip import AniSkipClient, AniSkipError
from app.services.audio_detector import DetectedInterval

log = logging.getLogger(__name__)


class SkipService:
    def __init__(self, settings: Settings, aniskip: AniSkipClient) -> None:
        self.settings = settings
        self.aniskip = aniskip
        self._local_cache: dict[tuple, list[SkipSegment]] = {}
        self._locks: dict[tuple, asyncio.Lock] = {}

    # --------------------------------------------------------------- AniSkip
    async def from_aniskip(
        self, mal_id: int, episode: float, episode_length: float, types: list[SegmentType]
    ) -> SkipTimesResponse:
        try:
            res = await self.aniskip.get_skip_times(mal_id, episode, episode_length, types)
        except AniSkipError as exc:
            return SkipTimesResponse(
                mal_id=mal_id, episode=episode, found=False,
                message=f"AniSkip indisponible : {exc}",
            )
        return SkipTimesResponse(
            mal_id=mal_id,
            episode=episode,
            found=res.found,
            source=SegmentSource.aniskip if res.found else None,
            segments=res.segments,
            message=res.message,
        )

    async def resolve(
        self,
        mal_id: int,
        episode: float,
        episode_length: float = 0.0,
        types: list[SegmentType] | None = None,
        local: AnalyzeRequest | None = None,
    ) -> SkipTimesResponse:
        """Point d'entrée unique utilisé par le lecteur."""
        types = types or [SegmentType.opening, SegmentType.ending]
        response = await self.from_aniskip(mal_id, episode, episode_length, types)
        if response.found or local is None or not self.settings.enable_local_fallback:
            return response

        log.info("Fallback local pour MAL %s ép. %s", mal_id, episode)
        local_resp = await self.analyze(local)
        local_resp.mal_id, local_resp.episode = mal_id, episode
        return local_resp

    # -------------------------------------------------------- Détection locale
    async def analyze(self, req: AnalyzeRequest) -> SkipTimesResponse:
        root = self.settings.media_root
        try:
            target = media.resolve_media(root, req.target)
            refs = [media.resolve_media(root, r) for r in req.references if r != req.target]
        except media.MediaError as exc:
            return SkipTimesResponse(found=False, message=str(exc))
        if not refs:
            return SkipTimesResponse(found=False, message="Au moins une référence distincte requise")

        key = (
            str(target), target.stat().st_mtime,
            tuple(sorted((str(r), r.stat().st_mtime) for r in refs)),
            tuple(sorted(t.value for t in req.detect)), req.use_visual,
        )
        if key in self._local_cache:
            segs = self._local_cache[key]
            return self._local_response(segs)

        lock = self._locks.setdefault(key, asyncio.Lock())
        async with lock:  # évite deux analyses lourdes identiques en parallèle
            if key not in self._local_cache:
                # Le traitement signal est CPU-bound : on sort de la boucle asyncio
                segs = await asyncio.to_thread(self._analyze_sync, target, refs, req)
                self._local_cache[key] = segs
        self._locks.pop(key, None)
        return self._local_response(self._local_cache[key])

    @staticmethod
    def _local_response(segs: list[SkipSegment]) -> SkipTimesResponse:
        return SkipTimesResponse(
            found=bool(segs),
            source=segs[0].source if segs else None,
            segments=segs,
            message="Détection locale" if segs else "Aucun générique commun détecté",
        )

    def _analyze_sync(
        self, target: Path, refs: list[Path], req: AnalyzeRequest
    ) -> list[SkipSegment]:
        s = self.settings
        t_dur = media.probe_duration(target)
        ref_durs = {r: media.probe_duration(r) for r in refs}
        out: list[SkipSegment] = []

        for seg_type in req.detect:
            if seg_type not in (SegmentType.opening, SegmentType.ending):
                continue  # recap/mixed : non gérés localement pour l'instant

            def window(dur: float, kind: SegmentType = seg_type) -> tuple[float, float]:
                """Opening → début de l'épisode ; ending → fin de l'épisode."""
                if kind is SegmentType.opening:
                    return 0.0, min(s.op_search_window, dur)
                w = min(s.ed_search_window, dur)
                return dur - w, w

            for source, detector in (
                (SegmentSource.local_audio, audio_detector.detect_in_window),
                (SegmentSource.local_visual, visual_detector.detect_in_window),
            ):
                if source is SegmentSource.local_visual and not req.use_visual:
                    break
                hits: list[DetectedInterval] = []
                for ref in refs:
                    try:
                        hit = detector(
                            target, ref, window(t_dur), window(ref_durs[ref]),
                            min_seconds=s.min_segment_seconds,
                            max_seconds=s.max_segment_seconds,
                        )
                    except Exception as exc:  # noqa: BLE001 - un fichier défectueux ne doit pas tout casser
                        log.warning("%s échoué sur %s : %s", source.value, ref.name, exc)
                        continue
                    if hit:
                        hits.append(hit)
                segment = self._aggregate(hits, len(refs), seg_type, source)
                if segment:
                    out.append(segment)
                    break  # l'audio a suffi : pas besoin de l'analyse visuelle

        return sorted(out, key=lambda x: x.start)

    @staticmethod
    def _aggregate(
        hits: list[DetectedInterval], n_refs: int, seg_type: SegmentType, source: SegmentSource
    ) -> SkipSegment | None:
        """Fusionne les détections obtenues contre plusieurs références (médiane robuste)."""
        if not hits:
            return None
        start = statistics.median(h.start for h in hits)
        end = statistics.median(h.end for h in hits)
        # Les références qui s'écartent de plus de 5 s de la médiane ne « votent » pas
        agree = [h for h in hits if abs(h.start - start) <= 5 and abs(h.end - end) <= 5]
        similarity = max(0.0, min(1.0, statistics.fmean(h.score for h in agree or hits)))
        confidence = round(similarity * (len(agree) / n_refs) ** 0.5, 3)
        if end <= start:
            return None
        return SkipSegment(
            type=seg_type, start=round(start, 2), end=round(end, 2),
            source=source, confidence=confidence,
        )
