#!/usr/bin/env bash
# Lance le backend en mode développement (Linux / macOS / Termux)
set -euo pipefail
cd "$(dirname "$0")/../backend"

if [ ! -d .venv ]; then
  echo "→ Création de l'environnement virtuel"
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -q -r requirements-dev.txt
[ -f .env ] || cp .env.example .env

exec uvicorn app.main:app --reload --host 0.0.0.0 --port "${ANIPLAY_PORT:-8000}"
