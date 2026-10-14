#!/bin/sh
# Prepares the drift web runtime in web/: downloads sqlite3.wasm pinned to the
# sqlite3 version in pubspec.lock and compiles drift_worker.js locally. Idempotent.
set -eu
mkdir -p "$(dirname "$0")/../.dart_tool"
cd "$(dirname "$0")/.."
SQLITE3_VERSION=$(awk '/^  sqlite3:$/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)
DRIFT_VERSION=$(awk '/^  drift:$/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)
fetch() { # url dest
  if [ -s "$2" ] && [ "$(cat ".dart_tool/$(basename "$2").version" 2>/dev/null)" = "$1" ]; then return; fi
  echo "fetching $1"
  curl -fsSL "$1" -o "$2.tmp"
  mv "$2.tmp" "$2"
  echo "$1" > ".dart_tool/$(basename "$2").version"
}
fetch "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE3_VERSION}/sqlite3.wasm" web/sqlite3.wasm
# compile the worker from our own lockfile (prebuilt release workers may target another sqlite3 version)
if [ ! -s web/drift_worker.js ] || [ "$(cat .dart_tool/drift_worker.js.version 2>/dev/null)" != "local-${DRIFT_VERSION}-${SQLITE3_VERSION}" ]; then
  echo "compiling drift_worker.js"
  dart compile js -O4 tool/web/drift_worker.dart -o web/drift_worker.js >/dev/null
  rm -f web/drift_worker.js.deps web/drift_worker.js.map
  echo "local-${DRIFT_VERSION}-${SQLITE3_VERSION}" > .dart_tool/drift_worker.js.version
fi
