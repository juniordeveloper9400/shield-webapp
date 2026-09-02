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

# neon_secret.dart is git-ignored (holds the Neon password). Ship the empty
# template so the bundle compiles; the real connection string is passed as a
# --dart-define below, read from the DATABASE_URL Vercel environment variable.
if [ ! -f lib/data/neon/neon_secret.dart ]; then
  cp lib/data/neon/neon_secret.example.dart lib/data/neon/neon_secret.dart
fi

flutter --version
flutter config --enable-web
flutter pub get

# DATABASE_URL (set in the Vercel project's Environment Variables) is compiled
# into the web bundle so the storefront catalogue, sign-in and registration can
# reach Neon. NOTE: this puts the connection string in the shipped JS — the
# same trade-off the staff admin console already makes. Leave it unset to build
# a catalogue-less bundle (the shop then shows an "unavailable" state).
DB_URL="${DATABASE_URL:-}"
echo "DATABASE_URL length: ${#DB_URL}"  # value not printed; 0 = env var missing

flutter build web --release --dart-define=DATABASE_URL="$DB_URL"
