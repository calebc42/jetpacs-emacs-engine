#!/usr/bin/env bash
# Build the engine AAR from dist/current with the Gradle project in android/
# and place it beside the distribution with its SHA-256:
#   dist/jetpacs-emacs-engine-<version>+<build>.aar(.sha256)
set -euo pipefail
. "$(dirname "$0")/env.sh"
[ -d "$ENGINE_ROOT/dist/current" ] || { echo "package-aar: run tools/harvest.sh first" >&2; exit 1; }
cd "$ENGINE_ROOT/android"
./gradlew --console=plain -q :engine:assembleRelease "-PengineDist=$ENGINE_ROOT/dist/current"
out="$ENGINE_ROOT/dist/jetpacs-emacs-engine-$EMACS_VERSION+$ENGINE_BUILD.aar"
cp -f engine/build/outputs/aar/engine-release.aar "$out"
(cd "$ENGINE_ROOT/dist" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256" && cat "$(basename "$out").sha256")
ls -la "$out"
