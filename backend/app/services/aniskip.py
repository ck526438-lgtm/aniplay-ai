"""Client asynchrone pour l'API publique AniSkip v2.

Documentation : https://api.aniskip.com/api-docs
Endpoint utilisé :
    GET /v2/skip-times/{malId}/{episodeNumber}?types[]=op&types[]=ed&episodeLength=0

Réponse type :
    {
      "found": true,
      "results": [
        {"interval": {"startTime": 81.3, "endTime": 171.3},
         "skipType": "op", "skipId": "...", "episodeLength": 1420.1}
      ],
      "message": "Successfully found skip times",
      "statusCode": 200
    }
Quand rien n'est trouvé, l'API renvoie 404 avec "found": false — ce n'est pas une erreur.
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass

import httpx

from app.schemas import SegmentSource, SegmentType, SkipSegment

log = logging.getLogger(__name__)

DEFAULT_TYPES: tuple[SegmentType, ...] = (
    SegmentType.opening,
    SegmentType.ending,
    SegmentType.mixed_opening,
    SegmentType.mixed_ending,
    SegmentType.recap,
)

# Tolérance (s) pour accepter un timestamp soumis sur une version de l'épisode
# de durée légèrement différente (version TV vs BD, etc.).
EPISODE_LENGTH_TOLERANCE = 3.0


class AniSkipError(Exception):
    """Erreur réseau ou réponse inexploitable : déclenche le fallback local."""


@dataclass(slots=True)
class AniSkipResult:
    found: bool
    segments: list[SkipSegment]
    message: str | None = None


class _TTLCache:
    """Petit cache mémoire avec expiration — suffisant pour un service mono-instance."""

    def __init__(self, ttl: float, max_items: int = 2048) -> None:
        self._ttl = ttl
        self._max = max_items
        self._data: dict[tuple, tuple[float, AniSkipResult]] = {}

    def get(self, key: tuple) -> AniSkipResult | None:
        item = self._data.get(key)
        if item is None:
            return None
        expires, value = item
        if expires < time.monotonic():
            self._data.pop(key, None)
            return None
        return value

    def set(self, key: tuple, value: AniSkipResult) -> None:
        if len(self._data) >= self._max:
            self._data.pop(next(iter(self._data)))  # éviction FIFO simple
        self._data[key] = (time.monotonic() + self._ttl, value)

    def clear(self) -> None:
        self._data.clear()


class AniSkipClient:
    def __init__(
        self,
        base_url: str = "https://api.aniskip.com/v2",
        timeout: float = 6.0,
        retries: int = 2,
        cache_ttl: float = 6 * 3600,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._retries = max(0, retries)
        self._cache = _TTLCache(cache_ttl)
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(timeout),
            headers={"User-Agent": "AniPlay-AI/0.1 (+https://github.com/ck526438-lgtm/aniplay-ai)"},
            follow_redirects=True,
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    # ------------------------------------------------------------------ API
    async def get_skip_times(
        self,
        mal_id: int,
        episode: float,
        episode_length: float = 0.0,
        types: tuple[SegmentType, ...] | list[SegmentType] = DEFAULT_TYPES,
        use_cache: bool = True,
    ) -> AniSkipResult:
        """Récupère les segments d'un épisode.

        :param mal_id: identifiant MyAnimeList de l'anime
        :param episode: numéro d'épisode (peut être décimal : 12.5)
        :param episode_length: durée réelle du fichier en secondes (0 = inconnue).
            Quand elle est fournie, AniSkip renvoie les timestamps soumis pour
            une version de durée proche, puis on filtre localement par sécurité.
        :raises AniSkipError: si l'API est injoignable ou renvoie une réponse invalide.
        """
        if mal_id <= 0 or episode <= 0:
            raise ValueError("mal_id et episode doivent être strictement positifs")

        types = tuple(types) or DEFAULT_TYPES
        ep_len = round(max(0.0, episode_length), 1)
        key = (mal_id, float(episode), ep_len, tuple(t.value for t in types))

        if use_cache and (cached := self._cache.get(key)) is not None:
            return cached

        data = await self._request(mal_id, episode, ep_len, types)
        result = self._parse(data, ep_len)
        self._cache.set(key, result)
        return result

    # ------------------------------------------------------------ internals
    async def _request(
        self, mal_id: int, episode: float, ep_len: float, types: tuple[SegmentType, ...]
    ) -> dict:
        ep = int(episode) if float(episode).is_integer() else episode
        url = f"{self._base_url}/skip-times/{mal_id}/{ep}"
        params = [("types[]", t.value) for t in types] + [("episodeLength", ep_len)]

        last_exc: Exception | None = None
        for attempt in range(self._retries + 1):
            try:
                resp = await self._client.get(url, params=params)
                if resp.status_code == 404:
                    # "Aucun timestamp" : réponse normale côté AniSkip
                    try:
                        return resp.json()
                    except ValueError:
                        return {"found": False, "results": [], "message": "Not found"}
                if resp.status_code == 429 or resp.status_code >= 500:
                    raise AniSkipError(f"AniSkip HTTP {resp.status_code}")
                resp.raise_for_status()
                return resp.json()
            except (httpx.TransportError, httpx.HTTPStatusError, AniSkipError, ValueError) as exc:
                last_exc = exc
                if attempt < self._retries:
                    await asyncio.sleep(0.4 * (2**attempt))  # backoff exponentiel
                    continue
        log.warning("AniSkip injoignable pour %s/%s : %s", mal_id, episode, last_exc)
        raise AniSkipError(str(last_exc)) from last_exc

    @staticmethod
    def _parse(data: dict, ep_len: float) -> AniSkipResult:
        if not isinstance(data, dict):
            raise AniSkipError("Réponse AniSkip invalide")

        segments: list[SkipSegment] = []
        for item in data.get("results") or []:
            try:
                interval = item["interval"]
                start = float(interval["startTime"])
                end = float(interval["endTime"])
                seg_type = SegmentType(item["skipType"])
            except (KeyError, TypeError, ValueError):
                continue  # entrée corrompue ou type inconnu : on ignore

            # Si on connaît la durée du fichier et que l'entrée concerne une
            # version trop différente, on recale proportionnellement.
            src_len = float(item.get("episodeLength") or 0)
            if ep_len > 0 and src_len > 0 and abs(src_len - ep_len) > EPISODE_LENGTH_TOLERANCE:
                ratio = ep_len / src_len
                start, end = start * ratio, end * ratio
            if end <= start:
                continue
            if ep_len > 0:
                end = min(end, ep_len)

            segments.append(
                SkipSegment(
                    type=seg_type,
                    start=round(max(0.0, start), 3),
                    end=round(end, 3),
                    source=SegmentSource.aniskip,
                    confidence=1.0,
                    skip_id=item.get("skipId"),
                )
            )

        segments.sort(key=lambda s: s.start)
        found = bool(data.get("found")) and bool(segments)
        return AniSkipResult(found=found, segments=segments, message=data.get("message"))
