"""Configuration centralisée, chargée depuis les variables d'environnement (préfixe ANIPLAY_)."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ANIPLAY_", env_file=".env", extra="ignore")

    app_name: str = "AniPlay AI Backend"
    version: str = "1.1.0"
    log_level: str = "info"

    # --- AniSkip ---
    aniskip_base_url: str = "https://api.aniskip.com/v2"
    aniskip_timeout: float = 6.0
    aniskip_retries: int = 2
    aniskip_cache_ttl: int = 6 * 3600  # secondes

    # --- Détection locale ---
    enable_local_fallback: bool = True
    media_root: Path = Path("./data")
    op_search_window: float = 360.0  # on cherche l'opening dans les 6 premières minutes
    ed_search_window: float = 360.0  # et l'ending dans les 6 dernières
    min_segment_seconds: float = 45.0
    max_segment_seconds: float = 140.0

    # --- Sous-titres IA ---
    whisper_model: str = "base"  # tiny | base | small | medium | large-v3
    whisper_device: str = "auto"  # auto | cpu | cuda
    # "opus" = OPUS-MT, léger et rapide sur CPU, mais une paire de langues par modèle.
    # "nllb" = NLLB-200, couvre toutes les langues mais ~2,4 Go et lent sans GPU.
    translator: str = "opus"
    nllb_model: str = "facebook/nllb-200-distilled-600M"
    subtitles_dir: Path = Path("./cache/subtitles")
    subtitles_max_jobs: int = 1  # jobs IA simultanés (gourmands en CPU/GPU)
    # Mode bureau : backend et lecteur sur la même machine → chemins absolus autorisés.
    # À laisser à false sur un serveur partagé.
    local_mode: bool = False
    # Autoriser l'analyse d'URL distantes (http/https) par ffmpeg
    allow_remote_media: bool = True

    cors_origins: str = "*"

    @property
    def cors_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
