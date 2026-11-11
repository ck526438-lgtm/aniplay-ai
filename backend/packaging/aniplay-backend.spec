# -*- mode: python ; coding: utf-8 -*-
"""Spécification PyInstaller du backend AniPlay AI.

    cd backend
    pyinstaller packaging/aniplay-backend.spec --noconfirm

Résultat : dist/aniplay-backend/aniplay-backend(.exe) + ses bibliothèques (mode « onedir »,
bien plus rapide à démarrer qu'un exe unique qui se décompresse à chaque lancement).

Éditions (variable d'environnement ANIPLAY_EDITION) :
- ``standard`` (défaut) : AniSkip + détection IA locale (librosa, OpenCV). ~250 Mo.
- ``full`` : ajoute les sous-titres IA (faster-whisper, OPUS-MT/NLLB via transformers + torch CPU).
  Installez d'abord ``requirements-subtitles.txt``. ~1,5 Go.
"""
import os
from pathlib import Path

from PyInstaller.utils.hooks import collect_all, collect_data_files, collect_submodules

EDITION = os.environ.get("ANIPLAY_EDITION", "standard").lower()
BACKEND = Path(SPECPATH).parent  # noqa: F821 (SPECPATH est fourni par PyInstaller)

datas = []
binaries = []
hiddenimports = []

# Application : les routes et services sont importés normalement, mais on force tout le paquet
hiddenimports += collect_submodules("app")
# uvicorn charge ses boucles / protocoles par nom
hiddenimports += collect_submodules("uvicorn")
# librosa utilise lazy_loader : les stubs .pyi doivent être embarqués
datas += collect_data_files("librosa")
datas += collect_data_files("lazy_loader")
hiddenimports += collect_submodules("librosa")
hiddenimports += ["soundfile", "sklearn.utils._typedefs", "sklearn.neighbors._partition_nodes"]
for pkg in ("soundfile",):
    d, b, h = collect_all(pkg)
    datas += d
    binaries += b
    hiddenimports += h

excludes = ["tkinter", "matplotlib", "IPython", "pytest", "notebook"]

if EDITION == "full":
    for pkg in ("faster_whisper", "ctranslate2", "tokenizers", "sentencepiece"):
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    datas += collect_data_files("transformers", include_py_files=True)
    hiddenimports += collect_submodules("transformers.models.marian")
    hiddenimports += collect_submodules("transformers.models.m2m_100")
    hiddenimports += collect_submodules("transformers.models.nllb")
else:
    # Édition standard : les moteurs de sous-titres répondent « non installé » proprement
    excludes += ["torch", "transformers", "faster_whisper", "ctranslate2", "tensorflow"]

a = Analysis(  # noqa: F821
    [str(BACKEND / "aniplay_server.py")],
    pathex=[str(BACKEND)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
)
pyz = PYZ(a.pure)  # noqa: F821

icon = BACKEND.parent / "frontend" / "assets" / "branding" / "app_icon.ico"
exe = EXE(  # noqa: F821
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="aniplay-backend",
    debug=False,
    strip=False,
    upx=False,
    # Pas de fenêtre console : le backend tourne en arrière-plan de l'application
    console=os.environ.get("ANIPLAY_CONSOLE", "0") == "1",
    icon=str(icon) if icon.is_file() else None,
)
coll = COLLECT(  # noqa: F821
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="aniplay-backend",
)
