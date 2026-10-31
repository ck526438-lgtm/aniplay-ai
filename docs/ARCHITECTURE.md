# Architecture d'AniPlay AI

## Vue d'ensemble

```
┌──────────────────────── Frontend Flutter ────────────────────────┐
│  HomeScreen ─► PlayerScreen                                      │
│                 ├─ media_kit Player (libmpv)  ── position ──┐    │
│                 ├─ SkipController  ◄────────────────────────┘    │
│                 │     └─ seek(end) ──► Player                    │
│                 ├─ SkipButton (écoute SkipController)            │
│                 └─ SkipApiService ── HTTP ──┐                    │
└─────────────────────────────────────────────┼────────────────────┘
                                              ▼
┌──────────────────────── Backend FastAPI ─────────────────────────┐
│  routes.py ─► SkipService                                        │
│                ├─ 1. AniSkipClient  ──► api.aniskip.com (cache)  │
│                └─ 2. Fallback local (si rien / hors ligne)       │
│                      ├─ audio_detector  (librosa : chroma+MFCC)  │
│                      ├─ visual_detector (OpenCV : dHash)         │
│                      └─ matching.find_common_segment             │
└──────────────────────────────────────────────────────────────────┘
```

## Principes

1. **Contrat unique.** Le frontend ne reçoit que `SkipSegment {type, start, end, source, confidence}`.
   Il ignore d'où viennent les données ; on peut ajouter une source (base communautaire, modèle
   ML) sans toucher à l'app.
2. **Le lecteur ne dépend jamais du backend.** Toute erreur réseau donne une liste vide :
   la vidéo se lit normalement, simplement sans bouton.
3. **`SkipController` est indépendant de media_kit.** Il consomme des `Duration` et appelle un
   callback `seek`. Il est testable unitairement et réutilisable avec un autre moteur.

## Détection locale : l'algorithme

Un opening est le même contenu audio/vidéo répété d'un épisode à l'autre. On compare donc
l'épisode cible à 1–3 épisodes de la même série.

| Étape | Audio | Visuel |
|---|---|---|
| Fenêtre | 6 premières min (OP) / 6 dernières (ED) | idem |
| Descripteur | Chroma CENS (harmonie) + MFCC 1–12 (timbre), z-score, 2 pas/s | dHash 64 bits/image, 1 image/s |
| Similarité | cosinus entre chaque pas de A et de B | idem (= 1 − 2·Hamming/64) |
| Recherche | plus longue **diagonale** au-dessus du seuil, trous ≤ 2 s tolérés | idem |

**Seuil adaptatif** : un générique n'occupe qu'une diagonale, soit < 1 % des cellules de la
matrice. Le seuil est relevé au 99e centile de la matrice (plafonné à 0,93) : on ne garde que
l'élite des similarités, ce qui reste fiable sur les séries dont toute la bande-son se ressemble.

**Agrégation multi-références** : médiane des débuts/fins ; la confiance combine la similarité
moyenne et la part de références concordantes (± 5 s). Le lecteur ignore les segments sous 0,5.

**Garde-fous** : segment < 45 s ou > ~160 s rejeté (ce n'est pas un générique) ; chemins confinés
à `ANIPLAY_MEDIA_ROOT` ; calcul exécuté hors de la boucle asyncio ; résultat mis en cache par
(fichier, date de modification).

## Évolutions prévues

- Cache persistant (SQLite) des empreintes par série : une seule analyse par saison.
- Contribution des segments détectés vers AniSkip (avec validation utilisateur).
- Mapping AniList / Kitsu → MAL via l'API Jikan.
- Détection des segments « mixed-op » (opening sur animation d'épisode) via l'audio seul.
