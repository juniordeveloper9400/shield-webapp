#!/usr/bin/env bash
# Vercel build: no Flutter on the build image, so fetch the SDK and build web.
# vercel.json's inline buildCommand is capped at 256 chars, hence this script.
set -euo pipefail

FLUTTER_DIR="_flutter"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
fi

# neon_secret.dart is git-ignored (holds the Neon password). Ship the empty
# template so the bundle compiles; the real connection string is passed as a
# --dart-define below, read from the DATABASE_URL Vercel environment variable.
if [ ! -f lib/data/neon/neon_secret.dart ]; then
  cp lib/data/neon/neon_secret.example.dart lib/data/neon/neon_secret.dart
fi

export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"

flutter config --enable-web
flutter pub get

# DATABASE_URL (set in the Vercel project's Environment Variables) is compiled
# into the web bundle so the storefront catalogue, sign-in and registration can
# reach Neon. NOTE: this puts the connection string in the shipped JS — the
# same trade-off the staff admin console already makes. Leave it unset to build
# a catalogue-less bundle (the shop then shows an "unavailable" state).
flutter build web --release --dart-define=DATABASE_URL="${DATABASE_URL:-}"
