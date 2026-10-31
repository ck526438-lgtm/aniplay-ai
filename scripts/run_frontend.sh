#!/usr/bin/env bash
# Prépare et lance l'app Flutter (génère les dossiers plateformes au 1er lancement)
set -euo pipefail
cd "$(dirname "$0")/../frontend"

if [ ! -d linux ] && [ ! -d windows ] && [ ! -d android ]; then
  echo "→ Génération des dossiers plateformes"
  flutter create --project-name aniplay --org com.aniplay --platforms=android,linux,windows,macos .
fi
flutter pub get
flutter run "$@"
