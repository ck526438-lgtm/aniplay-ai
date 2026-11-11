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
| 💬 **Sous-titres VF par IA** | Génère des sous-titres français depuis n'importe quelle langue parlée : Whisper transcrit, OPUS-MT traduit (NLLB-200 en secours) — 100 % local, sans clé d'API |
| ⌨️ **Clavier / TV** | `S` passer · `Espace` pause · `←/→` ±10 s · bouton focalisable à la télécommande |

---

## 💬 Sous-titres générés par IA

Dans le lecteur, touchez **✨** → choisissez la langue (Français par défaut) → **Générer**.
La piste se charge automatiquement dans le lecteur dès qu'elle est prête, et vous pouvez
continuer à regarder pendant la génération.

```
audio de l'épisode ──► Whisper (détecte la langue + transcrit) ──► OPUS-MT (traduit) ──► .srt
   (piste choisie : VO/VF)        ja, en, ko, zh…                    → fr, en, es…
```

- **Toutes les langues sources reconnues par Whisper** (~100), détectées automatiquement.
- **Deux moteurs de traduction**, au choix via `ANIPLAY_TRANSLATOR` :
  - `opus` *(défaut)* — un petit modèle par paire de langues (~300 Mo), rapide sur CPU.
    Les paires utiles pour l'animation existent (`ja-fr`, `ko-fr`, `zh-fr`, `en-fr`…),
    mais **toutes les combinaisons ne sont pas publiées** : le job renvoie alors une erreur
    explicite invitant à passer à `nllb`.
  - `nllb` — NLLB-200 couvre les **27 langues cibles** listées ci-dessous (dont dioula,
    bambara, wolof, lingala, swahili, haoussa, yoruba — qualité plus variable), mais il est
    lourd (~1,1 Go, 2,4 Go de RAM en fp32) et lent sans GPU.
- Deux fichiers par génération : la **transcription originale** et la **traduction**.
- Lisibilité pro : 42 caractères par ligne, 2 lignes max, pas de chevauchement.
- Résultats mis en cache : une seconde demande identique est instantanée.

**Temps indicatifs pour un épisode de 24 min**, mesurés (pipeline complet, modèles déjà
téléchargés) :

| Machine | Coefficient mesuré | Durée estimée |
|---|---|---|
| GPU NVIDIA + `small` | ≪ temps réel | ~1 min |
| Core i3-2100, 8 Go, CPU seul + `base` | **≈ 2,7 × le temps réel** | **50 à 70 min** |

Sur un CPU modeste, la génération est donc une tâche de fond : on la lance, on fait autre
chose, la piste apparaît dans le lecteur une fois prête.

> ⚠️ Première utilisation : les modèles se téléchargent automatiquement (~150 Mo pour Whisper
> `base`, ~300 Mo par paire OPUS-MT, ~1,1 Go pour NLLB 600M), puis restent en cache.
>
> Une traduction automatique reste moins fine qu'un fansub humain (jeux de mots, honorifiques).

> ⚖️ **Licence des modèles** : Whisper est sous licence MIT et **OPUS-MT sous Apache-2.0** :
> l'usage commercial est autorisé avec le moteur par défaut.
> **NLLB-200 en revanche est sous CC-BY-NC 4.0 : usage non commercial uniquement.** Si vous
> distribuez une version commerciale, laissez `ANIPLAY_TRANSLATOR=opus` (ou implémentez votre
> propre moteur — il suffit de respecter le protocole `Translator` de
> `backend/app/services/subtitles/engines.py`), et n'activez `nllb` que pour un usage personnel.

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
│   │       └── subtitles/         Sous-titres IA : engines (Whisper, OPUS-MT, NLLB),
│   │                              jobs, formats SRT/VTT, langues
│   └── tests/
├── frontend/           Application Flutter
│   └── lib/
│       ├── controllers/skip_controller.dart  Logique d'affichage / skip
│       ├── widgets/skip_button.dart          Bouton animé
│       ├── services/skip_api_service.dart    Client du backend
│       ├── services/backend_launcher.dart    Démarre le moteur IA embarqué
│       ├── models/skip_segment.dart
│       └── screens/  home_screen · player_screen
├── docs/ARCHITECTURE.md
├── backend/aniplay_server.py   Point d'entrée « bureau » (gelé en aniplay-backend.exe)
├── installer/aniplay.iss       Installateur Windows (Inno Setup)
├── scripts/            Lancement Linux / Windows, build_windows.ps1
└── docker-compose.yml
```

Le détail de l'algorithme de détection est dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 🪟 Application Windows

**La façon la plus simple d'utiliser AniPlay AI** : un installateur classique, sans Python,
sans Flutter, sans ligne de commande. Le moteur IA (backend) et FFmpeg sont embarqués : l'application
les démarre toute seule en arrière-plan et les arrête à la fermeture.

1. Téléchargez la dernière version dans **[Releases](https://github.com/ck526438-lgtm/aniplay-ai/releases)** :

   | Fichier | Contenu | Taille |
   |---|---|---|
   | `AniPlay-AI-x.y.z-standard-setup.exe` | Lecteur + skip IA (AniSkip, détection audio/vidéo) | ~180 Mo |
   | `AniPlay-AI-x.y.z-full-setup.exe` | + **sous-titres IA** (Whisper, OPUS-MT, NLLB) | ~350 Mo |
   | `…-portable.zip` | Même chose, sans installation (décompressez, lancez `aniplay.exe`) | |

2. Lancez l'installateur (droits administrateur **non** requis). Options proposées :
   raccourci sur le Bureau, entrée **« Ouvrir avec AniPlay AI »** sur les vidéos (mkv, mp4…).
3. Ouvrez AniPlay AI : l'accueil indique **« Moteur IA prêt »** après quelques secondes.

Windows 10/11 64 bits requis. Données (modèles IA téléchargés, sous-titres générés, journaux) :
`%LOCALAPPDATA%\AniPlay AI` — le désinstallateur propose de les supprimer.
Pour régler le moteur IA, créez-y un fichier `backend.env` avec les variables `ANIPLAY_*`
(voir [Configuration](#️-configuration-backend)), par exemple `ANIPLAY_WHISPER_MODEL=small`.

> SmartScreen peut afficher « Windows a protégé votre ordinateur » car l'installateur n'est pas
> signé : cliquez sur **Informations complémentaires → Exécuter quand même**.

### Construire l'application Windows soi-même

Prérequis : Python 3.11, Flutter 3.27+ avec *Desktop development with C++* (Visual Studio),
et [Inno Setup 6](https://jrsoftware.org/isinfo.php) pour l'installateur (`winget install JRSoftware.InnoSetup`).

```powershell
.\scripts\build_windows.ps1                  # édition standard
.\scripts\build_windows.ps1 -Edition full    # avec les sous-titres IA
```

Le script gèle le backend avec PyInstaller, télécharge FFmpeg (build LGPL), vérifie que le
backend démarre, compile l'app Flutter, puis produit dans `dist\` l'installateur et le zip portable.

**Publier une version** : poussez un tag (`git tag v1.0.0 && git push origin v1.0.0`). Le workflow
[`windows.yml`](.github/workflows/windows.yml) construit les deux éditions et les attache à la
release GitHub. À chaque push, les installateurs sont aussi disponibles dans l'onglet *Actions*
(section *Artifacts*).

**Développer sous Windows** : `.\scripts\prepare_windows.ps1` génère le dossier `frontend\windows`
(nom, icône, fenêtre), puis `.\scripts\run_backend.ps1` et `cd frontend; flutter run -d windows`.

---

## 📱 Application Android (APK)

Téléchargez l'APK dans **[Releases](https://github.com/ck526438-lgtm/aniplay-ai/releases)** :

| Fichier | Pour |
|---|---|
| `AniPlay-AI-x.y.z-android-arm64-v8a.apk` | **La plupart des téléphones récents** (2017 et après) |
| `AniPlay-AI-x.y.z-android-armeabi-v7a.apk` | Anciens téléphones 32 bits |
| `AniPlay-AI-x.y.z-android-universel.apk` | En cas de doute : fonctionne partout (plus lourd) |

Installation : ouvrez l'APK sur le téléphone et autorisez « Installer des applis inconnues »
pour votre navigateur ou gestionnaire de fichiers. Android 7.0 ou plus récent.

**Ce qui fonctionne sur le téléphone :**

- **Mode autonome** (par défaut) : lecture des fichiers et des liens (mp4, mkv, HLS…), pistes
  audio et sous-titres, **skip des openings/endings via AniSkip** directement depuis le téléphone.
- **Avec un serveur IA** : le téléphone ne peut pas exécuter les modèles IA (détection locale,
  sous-titres Whisper). Lancez le backend sur un PC du même Wi-Fi
  (`.\scripts\run_backend.ps1` ou `docker compose up`, qui écoutent sur le port 8000), puis
  dans l'app : ⚙️ **Serveur IA** → adresse du PC, par exemple `192.168.1.20:8000`.
  Les sous-titres IA fonctionnent alors pour les vidéos en **URL** (le PC ne voit pas les
  fichiers stockés sur le téléphone).

**Construire l'APK soi-même** (Flutter 3.29+, Android SDK, Java 17) :

```bash
python scripts/prepare_android.py      # génère frontend/android (nom, icône, permissions)
cd frontend && flutter build apk --release --split-per-abi
```

**Signature** : sans configuration, l'APK est signé avec une clé de débogage, ce qui suffit pour
l'installer. Pour des mises à jour qui s'installent par-dessus l'ancienne version (et pour le Play
Store), créez votre clé une fois pour toutes et gardez-la précieusement :

```bash
keytool -genkeypair -v -keystore aniplay-release.jks -alias aniplay -keyalg RSA -keysize 4096 -validity 10000
```

puis ajoutez dans GitHub → *Settings* → *Secrets and variables* → *Actions* :
`ANDROID_KEYSTORE_BASE64` (sortie de `base64 -w0 aniplay-release.jks`), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` (`aniplay`) et `ANDROID_KEY_PASSWORD`. La CI signera alors les APK avec.
En local, créez `frontend/android/key.properties` (`storeFile=`, `storePassword=`, `keyAlias=`,
`keyPassword=`) — ce fichier n'est jamais versionné.

La CI ([`android.yml`](.github/workflows/android.yml)) construit les APK à chaque push, les teste
sur un émulateur Android (démarrage de l'app et lecture vidéo réelle avec libmpv) et les attache
aux releases (tags `v*`).

---

## 🚀 Installation (développeurs)

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
| `ANIPLAY_WHISPER_MODEL` | `base` | `tiny` · `base` · `small` · `medium` · `large-v3` (sur CPU lent, `base` ≈ 2× le temps réel, `small` ≈ 4-5×) |
| `ANIPLAY_WHISPER_DEVICE` | `auto` | `auto` · `cpu` · `cuda` |
| `ANIPLAY_TRANSLATOR` | `opus` | `opus` = OPUS-MT par paire, rapide sur CPU · `nllb` = NLLB-200, toutes les langues mais lourd et lent sans GPU |
| `ANIPLAY_NLLB_MODEL` | `facebook/nllb-200-distilled-600M` | Utilisé seulement si `ANIPLAY_TRANSLATOR=nllb` (`…-1.3B` plus précis) |
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
- [x] Application Windows (installateur + portable) construite par GitHub Actions
- [x] Application Android (APK) construite et testée sur émulateur par GitHub Actions
- [ ] Build CI pour Linux

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
