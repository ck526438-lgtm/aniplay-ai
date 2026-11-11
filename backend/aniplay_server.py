"""Point d'entrée « bureau » du backend AniPlay AI.

Utilisé par l'application Windows (exécutable PyInstaller ``aniplay-backend.exe``),
mais fonctionne aussi en développement :

    python aniplay_server.py --port 8765

Différences avec ``uvicorn app.main:app`` :
- mode bureau activé (chemins absolus autorisés : backend et lecteur sur le même PC) ;
- caches, sous-titres et modèles IA rangés dans le dossier utilisateur
  (``%LOCALAPPDATA%\\AniPlay AI`` sous Windows) au lieu du dossier courant ;
- FFmpeg embarqué à côté de l'exécutable ajouté au PATH ;
- ``--parent-pid`` : le serveur s'arrête tout seul quand l'application se ferme,
  même si elle a planté ou été tuée.
"""
from __future__ import annotations

import argparse
import logging
import multiprocessing
import os
import sys
import threading
import time
from pathlib import Path

APP_DIR_NAME = "AniPlay AI"


def default_data_dir() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / APP_DIR_NAME
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_DIR_NAME
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "aniplay-ai"


def bundle_dir() -> Path:
    """Dossier de l'exécutable gelé, ou du script en développement."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def configure_environment(data_dir: Path) -> None:
    """Prépare les variables lues par app.config AVANT d'importer l'application."""
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "media").mkdir(exist_ok=True)

    # Un fichier backend.env dans le dossier de données permet de régler le backend sans
    # recompiler (mêmes variables ANIPLAY_* que backend/.env.example). Il est prioritaire.
    env_file = data_dir / "backend.env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())

    defaults = {
        "ANIPLAY_LOCAL_MODE": "true",
        "ANIPLAY_MEDIA_ROOT": str(data_dir / "media"),
        "ANIPLAY_SUBTITLES_DIR": str(data_dir / "subtitles"),
        "ANIPLAY_CORS_ORIGINS": "*",
        # Modèles Whisper / OPUS-MT / NLLB téléchargés au premier usage
        "HF_HOME": str(data_dir / "models"),
    }
    for key, value in defaults.items():
        os.environ.setdefault(key, value)

    # FFmpeg embarqué : <bundle>/ffmpeg.exe ou <bundle>/ffmpeg/ffmpeg.exe
    here = bundle_dir()
    extra = [str(p) for p in (here, here / "ffmpeg", here.parent / "ffmpeg") if p.is_dir()]
    os.environ["PATH"] = os.pathsep.join([*extra, os.environ.get("PATH", "")])


def redirect_output(data_dir: Path) -> None:
    """Exécutable gelé (sans console) : on journalise dans un fichier du dossier de données."""
    if not getattr(sys, "frozen", False) and sys.stdout is not None and sys.stderr is not None:
        return
    log_dir = data_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "backend.log"
    # Rotation minimaliste : on repart de zéro au-delà de 5 Mo
    if log_path.exists() and log_path.stat().st_size > 5 * 1024 * 1024:
        log_path.unlink()
    stream = open(log_path, "a", encoding="utf-8", buffering=1)  # noqa: SIM115
    sys.stdout = stream
    sys.stderr = stream


def _process_alive(pid: int) -> bool:
    if sys.platform == "win32":
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        try:
            code = ctypes.c_ulong()
            kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def watch_parent(pid: int, interval: float = 2.0) -> None:
    """Arrête le serveur dès que le processus parent (l'application) disparaît."""

    def loop() -> None:
        while _process_alive(pid):
            time.sleep(interval)
        logging.getLogger("aniplay").info("Application fermée (PID %s) : arrêt du backend", pid)
        os._exit(0)

    threading.Thread(target=loop, name="parent-watchdog", daemon=True).start()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backend AniPlay AI (mode bureau)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data-dir", type=Path, default=None)
    parser.add_argument("--parent-pid", type=int, default=None)
    parser.add_argument("--log-level", default=os.environ.get("ANIPLAY_LOG_LEVEL", "info"))
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Vérifie que l'exécutable embarque bien toutes ses dépendances, puis quitte",
    )
    return parser.parse_args(argv)


def self_test() -> int:
    """Contrôle rapide utilisé par la CI après PyInstaller (détecte les imports oubliés)."""
    import numpy as np

    from app.main import app
    from app.services import audio_detector, visual_detector
    from app.services.media import _require

    sr = audio_detector.SAMPLE_RATE
    t = np.arange(sr * 4) / sr
    tone = (0.3 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
    features = audio_detector.audio_fingerprint(tone, sr)
    visual_detector._dhash(np.zeros((9, 8), dtype=np.uint8))
    print(f"[ok] application : {app.title} {app.version}")
    print(f"[ok] empreinte audio librosa : {features.shape}")
    print("[ok] OpenCV / dHash")
    for binary in ("ffmpeg", "ffprobe"):
        try:
            print(f"[ok] {binary} : {_require(binary)}")
        except Exception as exc:  # noqa: BLE001
            print(f"[!] {binary} : {exc}")
    try:
        import faster_whisper  # noqa: F401
        import transformers  # noqa: F401

        print("[ok] sous-titres IA disponibles")
    except ImportError:
        print("[--] sous-titres IA non inclus (édition standard)")
    return 0


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    data_dir = (args.data_dir or default_data_dir()).expanduser().resolve()

    if args.self_test:
        if sys.stdout is None:  # exe sans console : le rapport va dans un fichier
            data_dir.mkdir(parents=True, exist_ok=True)
            report = open(data_dir / "self-test.log", "w", encoding="utf-8")  # noqa: SIM115
            sys.stdout = sys.stderr = report
    else:
        redirect_output(data_dir)
    configure_environment(data_dir)
    if args.self_test:
        sys.exit(self_test())
    if args.parent_pid:
        watch_parent(args.parent_pid)

    import uvicorn

    from app.main import app

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level=args.log_level.lower(),
        # La config de log par défaut d'uvicorn suppose un terminal (couleurs, isatty)
        log_config=None,
        access_log=False,
    )


if __name__ == "__main__":
    multiprocessing.freeze_support()  # indispensable pour PyInstaller (joblib, numba…)
    main()
