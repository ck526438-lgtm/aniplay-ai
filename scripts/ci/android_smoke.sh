#!/usr/bin/env bash
# Test de l'APK sur émulateur (CI) : installation + lancement de la version release,
# puis test d'intégration (lecture vidéo réelle avec libmpv).
#   android_smoke.sh <apk-x86_64-release>
set -uo pipefail
APK="$1"
PKG=com.aniplay.aniplay
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"

echo "=== Vidéo de test servie à l'émulateur (http://10.0.2.2:8088) ==="
ffmpeg -loglevel error -f lavfi -i testsrc=duration=12:size=640x360:rate=24 \
  -f lavfi -i sine=frequency=440:duration=12 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  "$WORK/test.mp4"
(cd "$WORK" && python3 -m http.server 8088 >/dev/null 2>&1 &)
sleep 1

echo "=== APK release : installation et lancement ==="
adb install -r "$APK" || exit 1
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 25
if ! adb shell pidof "$PKG" >/dev/null; then
  echo "[!] L'application s'est arrêtée au démarrage"
  adb logcat -d | grep -E -A30 "FATAL EXCEPTION|AndroidRuntime" | head -120
  exit 1
fi
echo "[ok] application en cours d'exécution après 25 s"
adb logcat -d | grep -E "FATAL|E/flutter" | head -20 || true
adb exec-out screencap -p > "$WORK/smoke.png"
echo "SCREENSHOT_B64_BEGIN"
base64 -w0 "$WORK/smoke.png"
echo
echo "SCREENSHOT_B64_END"
adb uninstall "$PKG" >/dev/null

echo "=== Test d'intégration : lecture vidéo ==="
cd "$ROOT/frontend"
timeout 1200 flutter test integration_test/playback_test.dart -d emulator-5554 \
  --dart-define=TEST_VIDEO_URL=http://10.0.2.2:8088/test.mp4
