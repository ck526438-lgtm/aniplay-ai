# 🎬 AniPlay AI

**Lecteur d'anime open-source multiplateforme avec skip intelligent des openings et endings.**

AniPlay AI combine un lecteur vidéo performant (Flutter + libmpv) et un service d'IA en Python
qui sait où commencent et finissent les génériques, même pour des épisodes que personne n'a
encore référencés.

![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?logo=fastapi&logoColor=white)
![License](https://img.shields.io/badge/licence-MIT-green)

---

## ✨ Fonctionnalités

| | |
|---|---|
| ▶️ **Lecture avancée** | Fichiers locaux et flux distants (mp4, mkv, webm, HLS…) via `media_kit` / libmpv |
| 🌐 **Multiplateforme** | Windows, Linux, macOS, Android (iOS possible) |
| 🔤 **Pistes multiples** | Choix audio (VO/VF) et sous-titres embarqués, sous-titres externes `.srt`/`.ass` |
| ⏭️ **Bouton « Passer l'opening »** | Apparaît pile pendant le générique, se remplit au fil de l'opening |
| 🤖 **Auto-skip** | Optionnel, une seule fois par segment (on peut revenir revoir l'opening) |
| ☁️ **AniSkip en priorité** | Horodatages communautaires instantanés, avec cache et recalage selon la durée du fichier |
| 🧠 **IA locale en secours** | Empreinte audio (librosa) puis visuelle (OpenCV) pour détecter le générique commun à plusieurs épisodes |
| 💬 **Sous-titres VF par IA** | Génère des sous-titres français (ou dans 27 langues) depuis n'importe quelle langue parlée : Whisper transcrit, NLLB-200 traduit — 100 % local, sans clé d'API |
| ⌨️ **Clavier / TV** | `S` passer · `Espace` pause · `←/→` ±10 s · bouton focalisable à la télécommande |

---

## 💬 Sous-titres générés par IA

Dans le lecteur, touchez **✨** → choisissez la langue (Français par défaut) → **Générer**.
La piste se charge automatiquement dans le lecteur dès qu'elle est prête, et vous pouvez
continuer à regarder pendant la génération.

```
audio de l'épisode ──► Whisper (détecte la langue + transcrit) ──► NLLB-200 (traduit) ──► .srt
   (piste choisie : VO/VF)        ja, en, ko, zh…                       → fr, en, es…
```

- **Toutes les langues sources reconnues par Whisper** (~100), détectées automatiquement.
- **27 langues cibles**, dont le français, l'anglais, l'arabe, et des langues africaines
  (dioula, bambara, wolof, lingala, swahili, haoussa, yoruba — qualité plus variable).
- Deux fichiers par génération : la **transcription originale** et la **traduction**.
- Lisibilité pro : 42 caractères par ligne, 2 lignes max, pas de chevauchement.
- Résultats mis en cache : une seconde demande identique est instantanée.

**Temps indicatifs pour un épisode de 24 min** (modèle `small`) : ~1 min avec une carte
graphique NVIDIA, 5 à 10 min sur un processeur récent. Le modèle `medium` est plus précis mais
environ 2× plus lent ; `base` est plus rapide mais moins fiable sur le japonais.

> ⚠️ Première utilisation : les modèles se téléchargent automatiquement (~0,5 Go pour Whisper
> `small`, ~2,5 Go pour NLLB 600M), puis restent en cache.
>
> Une traduction automatique reste moins fine qu'un fansub humain (jeux de mots, honorifiques).

> ⚖️ **Licence des modèles** : Whisper est sous licence MIT (usage commercial autorisé).
> **NLLB-200 est sous licence CC-BY-NC 4.0 : usage non commercial uniquement.** Pour une version
> commerciale du logiciel, remplacez `NllbTranslator` par un autre moteur (Argos Translate / OPUS-MT,
> sous licences permissives, ou une API payante) : il suffit d'implémenter le protocole
> `Translator` de `backend/app/services/subtitles/engines.py`.

---

## 🏗️ Architecture

```
aniplay-ai/
├── backend/            Service Python : passerelle AniSkip + détection IA
│   ├── app/
│   │   ├── main.py              Point d'entrée FastAPI
│   │   ├── config.py            Paramètres (variables ANIPLAY_*)
│   │   ├── schemas.py           Contrat de données unifié
│   │   ├── api/routes.py        Routes HTTP v1
│   │   └── services/
│   │       ├── aniskip.py         Client AniSkip v2 (async, cache, retry)
│   │       ├── skip_service.py    Orchestration AniSkip → IA locale
│   │       ├── audio_detector.py  Empreinte audio librosa
│   │       ├── visual_detector.py Empreinte visuelle OpenCV
│   │       ├── matching.py        Recherche de séquence commune
│   │       ├── media.py           Accès ffmpeg / ffprobe
│   │       └── subtitles/         Sous-titres IA : engines (Whisper, NLLB),
│   │                              jobs, formats SRT/VTT, langues
│   └── tests/
├── frontend/           Application Flutter
│   └── lib/
│       ├── controllers/skip_controller.dart  Logique d'affichage / skip
│       ├── widgets/skip_button.dart          Bouton animé
│       ├── services/skip_api_service.dart    Client du backend
│       ├── models/skip_segment.dart
│       └── screens/  home_screen · player_screen
├── docs/ARCHITECTURE.md
├── scripts/            Lancement Linux / Windows
└── docker-compose.yml
```

Le détail de l'algorithme de détection est dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 🚀 Installation

### Prérequis

- **Python 3.10+** et **FFmpeg** (dans le PATH)
- **Flutter 3.27+** (`flutter doctor` sans erreur pour votre plateforme)
- Linux desktop : `sudo apt install libmpv-dev mpv`

### 1. Backend

```bash
# Linux / macOS / Termux
./scripts/run_backend.sh

# Windows (PowerShell)
.\scripts\run_backend.ps1
```

Ou manuellement :

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows : .venv\Scripts\activate
pip install -r requirements-dev.txt
pip install -r requirements-subtitles.txt   # optionnel : sous-titres IA
cp .env.example .env
uvicorn app.main:app --reload
```

> Avec une carte NVIDIA, installez d'abord PyTorch avec CUDA (voir pytorch.org) puis
> `requirements-subtitles.txt` : la génération de sous-titres sera environ 5× plus rapide.

➡️ Documentation interactive : **http://localhost:8000/docs**

**Avec Docker :**

```bash
mkdir media            # placez-y vos épisodes pour la détection locale
docker compose up --build
```

### 2. Frontend

```bash
cd frontend
flutter create --project-name aniplay --org com.aniplay --platforms=android,linux,windows,macos .
flutter pub get
flutter run -d windows        # ou linux, macos, android…
```

> La commande `flutter create .` génère les dossiers natifs (android/, windows/…) sans écraser `lib/`.
> `./scripts/run_frontend.sh` fait tout cela automatiquement.

**Pointer vers un autre backend :**

```bash
flutter run --dart-define=ANIPLAY_API=http://192.168.1.20:8000
# Émulateur Android → http://10.0.2.2:8000
```

**Android** : ajoutez dans `android/app/src/main/AndroidManifest.xml` :
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application android:usesCleartextTraffic="true" ...>  <!-- backend en http local -->
```

---

## 📖 Utilisation

1. Lancez le backend, puis l'application.
2. Choisissez un fichier ou collez une URL.
3. Renseignez l'**ID MyAnimeList** (dans l'URL `myanimelist.net/anime/`**`21`**`/One_Piece`) et le numéro d'épisode.
4. Lisez : le bouton **Passer l'opening** apparaît automatiquement pendant le générique.

### API

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/health` | État du service |
| `GET` | `/api/v1/skip-times/{mal_id}/{episode}?episode_length=1420&types=op,ed` | Segments via AniSkip |
| `POST` | `/api/v1/skip-times/{mal_id}/{episode}/resolve` | AniSkip, puis IA locale si rien n'est trouvé |
| `POST` | `/api/v1/analyze` | Détection IA locale seule |
| `GET` | `/api/v1/debug/aniskip?mal_id=21&episode=1` | Test d'intégration AniSkip (sans cache) |
| `GET` | `/api/v1/subtitles/languages` | Langues cibles disponibles |
| `POST` | `/api/v1/subtitles` | Lance une génération de sous-titres (job) |
| `GET` | `/api/v1/subtitles/jobs/{id}` | Progression du job |
| `GET` | `/api/v1/subtitles/jobs/{id}/file[?original=true]` | Télécharge le `.srt` traduit (ou l'original) |

**Générer des sous-titres VF :**

```bash
curl -X POST localhost:8000/api/v1/subtitles -H "content-type: application/json" \
  -d '{"source": "frieren/ep05.mkv", "target_lang": "fr"}'
# → {"id": "a1b2c3", "status": "queued", ...}
curl localhost:8000/api/v1/subtitles/jobs/a1b2c3
# → {"status": "translating", "progress": 0.82, "detected_language": "ja", ...}
```

`source` accepte un chemin relatif à `ANIPLAY_MEDIA_ROOT`, une URL `http(s)`, ou un chemin
absolu si `ANIPLAY_LOCAL_MODE=true` (backend et lecteur sur le même PC).

**Exemple de réponse :**

```json
{
  "mal_id": 21, "episode": 1.0, "found": true, "source": "aniskip",
  "segments": [
    {"type": "op", "start": 81.3, "end": 171.3, "source": "aniskip", "confidence": 1.0, "skip_id": "..."}
  ],
  "message": "Successfully found skip times"
}
```

**Détection IA locale** (chemins relatifs à `ANIPLAY_MEDIA_ROOT`) :

```bash
curl -X POST localhost:8000/api/v1/analyze -H "content-type: application/json" -d '{
  "target": "frieren/ep05.mkv",
  "references": ["frieren/ep04.mkv", "frieren/ep06.mkv"],
  "detect": ["op", "ed"]
}'
```

> 💡 Deux références donnent un résultat plus fiable qu'une seule. Comptez quelques secondes
> par épisode ; le résultat est ensuite mis en cache.

---

## ⚙️ Configuration (backend)

| Variable | Défaut | Description |
|---|---|---|
| `ANIPLAY_ANISKIP_BASE_URL` | `https://api.aniskip.com/v2` | Endpoint AniSkip |
| `ANIPLAY_ANISKIP_TIMEOUT` | `6.0` | Timeout réseau (s) |
| `ANIPLAY_ANISKIP_CACHE_TTL` | `21600` | Durée du cache (s) |
| `ANIPLAY_ENABLE_LOCAL_FALLBACK` | `true` | Active la détection IA |
| `ANIPLAY_MEDIA_ROOT` | `./data` | Seul dossier lisible par l'analyse |
| `ANIPLAY_OP_SEARCH_WINDOW` / `ED_` | `360` | Fenêtre de recherche (s) |
| `ANIPLAY_MIN_SEGMENT_SECONDS` | `45` | Durée minimale d'un générique |
| `ANIPLAY_WHISPER_MODEL` | `small` | `tiny` · `base` · `small` · `medium` · `large-v3` |
| `ANIPLAY_WHISPER_DEVICE` | `auto` | `auto` · `cpu` · `cuda` |
| `ANIPLAY_NLLB_MODEL` | `facebook/nllb-200-distilled-600M` | Modèle de traduction (`…-1.3B` plus précis) |
| `ANIPLAY_LOCAL_MODE` | `false` | Autorise les chemins absolus (usage bureau mono-utilisateur) |
| `ANIPLAY_ALLOW_REMOTE_MEDIA` | `true` | Autorise les URL http(s) comme source |
| `ANIPLAY_CORS_ORIGINS` | `*` | Origines autorisées (séparées par `,`) |

---

## 🧪 Tests

```bash
cd backend && pytest          # AniSkip (mocké), API, matching, détecteur audio, pipeline sous-titres
cd frontend && flutter test   # SkipController, SkipButton, génération de sous-titres
```

---

## 🗺️ Feuille de route

- [ ] Cache persistant des empreintes par saison (SQLite)
- [ ] Recherche d'anime par titre (Jikan) au lieu de l'ID MAL
- [ ] Bibliothèque locale avec reprise de lecture
- [ ] Envoi des segments détectés vers AniSkip
- [ ] Build CI (GitHub Actions) pour Windows, Linux et Android

## 🤝 Contribuer

1. Forkez le dépôt et créez une branche : `git checkout -b feat/ma-fonctionnalite`
2. Backend : `ruff check app tests && pytest` · Frontend : `flutter analyze && flutter test`
3. Ouvrez une Pull Request en décrivant le changement.

## 🙏 Remerciements

- [AniSkip](https://github.com/aniskip) pour sa base communautaire d'horodatages
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) et [NLLB-200](https://huggingface.co/facebook/nllb-200-distilled-600M) (Meta) pour les sous-titres
- [media_kit](https://github.com/media-kit/media-kit) et [mpv](https://mpv.io)
- [librosa](https://librosa.org) et [OpenCV](https://opencv.org)

## 📄 Licence

MIT — voir [`LICENSE`](LICENSE).
