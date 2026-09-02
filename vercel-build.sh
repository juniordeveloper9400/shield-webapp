#!/usr/bin/env bash
# Vercel build: no Flutter on the build image, so fetch the SDK and build web.
# vercel.json's inline buildCommand is capped at 256 chars, hence this script.
set -euo pipefail

FLUTTER_DIR="_flutter"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
fi

# neon_secret.dart is git-ignored (holds the Neon password). Ship the empty
# template so the bundle compiles; the deployed site runs without a DB.
if [ ! -f lib/data/neon/neon_secret.dart ]; then
  cp lib/data/neon/neon_secret.example.dart lib/data/neon/neon_secret.dart
fi

export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter build web --release
