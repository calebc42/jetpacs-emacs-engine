#!/usr/bin/env bash
# The whole pipeline: verify the tarball, build every ABI, harvest, package.
# Logs go to work/logs/.
set -euo pipefail
. "$(dirname "$0")/env.sh"
mkdir -p "$ENGINE_ROOT/work/logs"
"$ENGINE_ROOT/tools/fetch-upstream.sh" 2>&1 | tee "$ENGINE_ROOT/work/logs/fetch.log"
for abi in $ENGINE_ABIS; do
  "$ENGINE_ROOT/tools/build-abi.sh" "$abi" "$@" > "$ENGINE_ROOT/work/logs/build-$abi.log" 2>&1 \
    || { echo "build-all: $abi failed, see work/logs/build-$abi.log" >&2; tail -40 "$ENGINE_ROOT/work/logs/build-$abi.log" >&2; exit 1; }
  tail -3 "$ENGINE_ROOT/work/logs/build-$abi.log"
done
"$ENGINE_ROOT/tools/harvest.sh" 2>&1 | tee "$ENGINE_ROOT/work/logs/harvest.log"
"$ENGINE_ROOT/tools/package-aar.sh" 2>&1 | tee "$ENGINE_ROOT/work/logs/package-aar.log"
