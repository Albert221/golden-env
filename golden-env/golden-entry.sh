#!/bin/sh
# Resolve dependencies inside the image so the lockfile meets the image's Dart SDK.
set -e
if [ -f pubspec.yaml ]; then
  flutter pub get --offline >/dev/null 2>&1 || flutter pub get
fi
exec "$@"
