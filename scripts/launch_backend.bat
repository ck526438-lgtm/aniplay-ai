@echo off
rem Demarre l'API AniPlay AI sur http://localhost:8000
setlocal
cd /d "%~dp0..\backend"

if not exist ".venv\Scripts\python.exe" (
    echo [!] Creation de l'environnement Python...
    python -m venv .venv
    ".venv\Scripts\python.exe" -m pip install -r requirements-dev.txt
)

rem Ajoute FFmpeg au PATH s'il est installe via winget mais pas encore dans le PATH
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg_*") do (
    for /d %%F in ("%%D\ffmpeg-*\bin") do set "PATH=%PATH%;%%F"
)

echo [*] API AniPlay AI : http://localhost:8000/docs  (Ctrl+C pour arreter)
".venv\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
