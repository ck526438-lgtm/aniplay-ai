#!/usr/bin/env python3
"""Prépare le projet Flutter pour Android : génère frontend/android (si absent) puis
applique l'identité et la configuration d'AniPlay AI. Idempotent.

    python scripts/prepare_android.py
    cd frontend && flutter build apk --release --split-per-abi

Signature : si frontend/android/key.properties existe, l'APK « release » est signé avec
votre clé (voir README, section Android) ; sinon avec la clé de débogage.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
ANDROID = FRONTEND / "android"
APP_NAME = "AniPlay AI"


def run_flutter_create() -> None:
    print("-> Génération du projet Android (flutter create)")
    flutter = shutil.which("flutter") or shutil.which("flutter.bat")
    if not flutter:
        sys.exit("flutter est introuvable dans le PATH")
    subprocess.run(
        [flutter, "create", "--project-name", "aniplay", "--org", "com.aniplay",
         "--platforms=android", "."],
        cwd=FRONTEND,
        check=True,
    )


def edit(path: Path, transform) -> None:
    text = path.read_text(encoding="utf-8")
    new = transform(text)
    if new != text:
        path.write_text(new, encoding="utf-8")
        print(f"   modifié : {path.relative_to(ROOT)}")


def patch_manifest(text: str) -> str:
    text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', text, count=1)
    # Accès réseau (AniSkip, serveur IA) — absent du manifeste « main » par défaut
    if "android.permission.INTERNET" not in text:
        text = re.sub(
            r"(<manifest[^>]*>)",
            r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
            text,
            count=1,
        )
    # Serveur IA en http:// sur le réseau local (PC de la maison)
    if "usesCleartextTraffic" not in text:
        text = text.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    return text


SIGNING_HEADER = """import java.io.FileInputStream
import java.util.Properties

"""

SIGNING_PROPS = """
// Signature « release » : android/key.properties (non versionné), sinon clé de débogage
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
"""

SIGNING_CONFIG = """
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
"""


def patch_gradle_kts(text: str) -> str:
    if "keystorePropertiesFile" in text:
        return text
    text = SIGNING_HEADER + text
    text = text.replace("\nandroid {", SIGNING_PROPS + "\nandroid {", 1)
    text = text.replace("\nandroid {\n", "\nandroid {\n" + SIGNING_CONFIG, 1)
    new, n = re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (keystorePropertiesFile.exists()) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        text,
    )
    if n == 0:
        sys.exit("build.gradle.kts : configuration de signature introuvable, modèle inattendu")
    return new


def main() -> None:
    if not (ANDROID / "app" / "src" / "main" / "AndroidManifest.xml").is_file():
        run_flutter_create()

    sample = FRONTEND / "test" / "widget_test.dart"
    if sample.is_file() and "MyApp" in sample.read_text(encoding="utf-8"):
        sample.unlink()

    print("-> Identité et configuration de l'application")
    edit(ANDROID / "app" / "src" / "main" / "AndroidManifest.xml", patch_manifest)

    gradle = ANDROID / "app" / "build.gradle.kts"
    if not gradle.is_file():
        sys.exit("android/app/build.gradle.kts introuvable (Flutter trop ancien ? utilisez 3.29+)")
    edit(gradle, patch_gradle_kts)

    icons = FRONTEND / "assets" / "branding" / "android"
    res = ANDROID / "app" / "src" / "main" / "res"
    for folder in icons.iterdir():
        dest = res / folder.name
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(folder / "ic_launcher.png", dest / "ic_launcher.png")
    print(f"OK : projet Android prêt ({ANDROID})")


if __name__ == "__main__":
    main()
