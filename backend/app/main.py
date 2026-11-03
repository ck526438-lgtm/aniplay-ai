"""Point d'entrée FastAPI — AniPlay AI Backend.

Lancement :  uvicorn app.main:app --reload
Docs live :  http://localhost:8000/docs
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router
from app.api.subtitles import router as subtitles_router
from app.config import get_settings
from app.services.aniskip import AniSkipClient
from app.services.skip_service import SkipService
from app.services.subtitles.engines import NllbTranslator, OpusMtTranslator, WhisperTranscriber
from app.services.subtitles.jobs import SubtitleJobManager


def create_app() -> FastAPI:
    settings = get_settings()
    logging.basicConfig(
        level=settings.log_level.upper(),
        format="%(asctime)s %(levelname)-7s %(name)s — %(message)s",
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        aniskip = AniSkipClient(
            base_url=settings.aniskip_base_url,
            timeout=settings.aniskip_timeout,
            retries=settings.aniskip_retries,
            cache_ttl=settings.aniskip_cache_ttl,
        )
        app.state.skip_service = SkipService(settings, aniskip)
        # Les moteurs IA ne sont chargés en mémoire qu'au premier job (chargement paresseux)
        if not hasattr(app.state, "subtitle_jobs"):  # les tests peuvent injecter des faux moteurs
            translator = (
                NllbTranslator(settings.nllb_model)
                if settings.translator == "nllb"
                else OpusMtTranslator()
            )
            app.state.subtitle_jobs = SubtitleJobManager(
                settings,
                WhisperTranscriber(settings.whisper_model, device=settings.whisper_device),
                translator,
            )
        yield
        await aniskip.aclose()

    app = FastAPI(
        title=settings.app_name,
        version=settings.version,
        description="Passerelle AniSkip + détection IA des openings/endings pour le lecteur AniPlay.",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_list,
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )
    app.include_router(router)
    app.include_router(subtitles_router)

    @app.get("/health", tags=["system"])
    async def health() -> dict:
        return {"status": "ok", "version": settings.version}

    return app


app = create_app()
