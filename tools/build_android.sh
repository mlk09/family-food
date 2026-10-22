#!/usr/bin/env bash
# Builds installable Android packages. Requires the Android SDK (Android Studio).
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env}"
DEFINES=()
[[ -f "$ENV_FILE" ]] && DEFINES=(--dart-define-from-file="$ENV_FILE") || echo "⚠️  $ENV_FILE not found — Demo-only build."

flutter build apk --debug "${DEFINES[@]}"
flutter build apk --release "${DEFINES[@]}"
flutter build appbundle --release "${DEFINES[@]}"   # for Google Play

mkdir -p dist
cp build/app/outputs/flutter-apk/app-debug.apk   dist/family-food-assistant-debug.apk
cp build/app/outputs/flutter-apk/app-release.apk dist/family-food-assistant.apk
cp build/app/outputs/bundle/release/app-release.aab dist/family-food-assistant.aab
ls -lh dist/
