#!/usr/bin/env bash
# Builds one deployable static site:
#   deploy/            ← download landing page (QR code points here)
#   deploy/app/        ← Flutter web app / PWA
# Upload the whole deploy/ folder to any static host (GitHub Pages, Netlify,
# Vercel, Firebase Hosting, Cloudflare Pages…).
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env}"
DEFINES=()
if [[ -f "$ENV_FILE" ]]; then
  DEFINES=(--dart-define-from-file="$ENV_FILE")
else
  echo "⚠️  $ENV_FILE not found — building in Demo-only mode (no cloud sync/AI)."
fi

flutter build web --release --base-href /app/ --no-web-resources-cdn "${DEFINES[@]}"

rm -rf deploy && mkdir -p deploy/app
cp -r build/web/. deploy/app/
cp web_download/index.html web_download/config.js web_download/icon.png deploy/
[ -f web_download/qr.png ] && cp web_download/qr.png deploy/
# Single-page-app fallback for hosts that support it (Netlify/Cloudflare).
printf '/app/*  /app/index.html  200\n' > deploy/_redirects
touch deploy/.nojekyll
echo "✔ Static site ready in ./deploy  (landing page at /, web app at /app/)"
