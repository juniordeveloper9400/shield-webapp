#!/usr/bin/env bash
# Vercel build: no Flutter on the build image, so fetch the SDK and build web.
# vercel.json's inline buildCommand is capped at 256 chars, hence this script.
set -euo pipefail
set -x  # echo every command so a failed Vercel build is diagnosable

FLUTTER_DIR="_flutter"
FLUTTER_CHANNEL="stable"

# A cached (Vercel build cache) _flutter/ can be a partial clone that leaves
# bin/flutter present but broken. Verify it actually runs; re-clone if not.
if [ ! -x "$FLUTTER_DIR/bin/flutter" ] || ! "$FLUTTER_DIR/bin/flutter" --version >/dev/null 2>&1; then
  rm -rf "$FLUTTER_DIR"
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_CHANNEL" "$FLUTTER_DIR"
fi

export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"
git config --global --add safe.directory "$PWD/$FLUTTER_DIR"

# lib/data/neon/neon_secret.dart is git-ignored. The web bundle does not use it:
# the empty template is copied only so the shared NeonHttp file compiles, and no
# database connection is ever built into the bundle.
if [ ! -f lib/data/neon/neon_secret.dart ]; then
  cp lib/data/neon/neon_secret.example.dart lib/data/neon/neon_secret.dart
fi

flutter --version
flutter config --enable-web
flutter pub get

# backend/api's base URL (set in the Vercel project's Environment Variables).
# Without this, BackendHttp.isConfigured is false at runtime, the app never
# signs in to backend/api, and PersonaRepository always resolves "not
# converted" — an agent/investor the Super Admin converts never sees their
# card on this build no matter what the database says. Public, not a secret:
# it is just this deployment's own backend URL.
BACKEND_URL="${BACKEND_API_BASE_URL:-}"
echo "BACKEND_API_BASE_URL: $BACKEND_URL"

# Sentry (set in the Vercel project's Environment Variables). Public, not a
# secret — a DSN is meant to travel in client-side code (same as a Firebase
# web config); it identifies which project to send events to, nothing more.
# Leave unset and this build simply reports no crashes. See docs/sentry.md.
SENTRY_DSN_VALUE="${SENTRY_DSN:-}"
echo "SENTRY_DSN length: ${#SENTRY_DSN_VALUE}"

# MSG91 Widget OTP (set in the Vercel project's Environment Variables — same
# widgetId/tokenAuth pair shieldweb's own VITE_MSG91_WIDGET_ID/
# VITE_MSG91_TOKEN_AUTH and the root shield app's own build carry). Without
# these, lib/module/auth/msg91_widget_otp_web.dart's _ensureWidget throws
# "OTP sending is not configured in this build" and member sign-in/agent
# registration can never send a code at all. tokenAuth is the scoped,
# throttled, browser-safe token made specifically to travel in client code —
# not the master Auth Key, which stays server-only (backend/api's own
# MSG91_AUTH_KEY).
MSG91_WIDGET_ID_VALUE="${MSG91_WIDGET_ID:-}"
MSG91_WIDGET_TOKEN_AUTH_VALUE="${MSG91_WIDGET_TOKEN_AUTH:-}"
echo "MSG91_WIDGET_ID length: ${#MSG91_WIDGET_ID_VALUE}"
echo "MSG91_WIDGET_TOKEN_AUTH length: ${#MSG91_WIDGET_TOKEN_AUTH_VALUE}"

flutter build web --release \
  --dart-define=BACKEND_API_BASE_URL="$BACKEND_URL" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN_VALUE" \
  --dart-define=MSG91_WIDGET_ID="$MSG91_WIDGET_ID_VALUE" \
  --dart-define=MSG91_WIDGET_TOKEN_AUTH="$MSG91_WIDGET_TOKEN_AUTH_VALUE"
