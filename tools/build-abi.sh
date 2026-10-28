#!/usr/bin/env bash
# Cross-build pristine Emacs for one Android ABI with Emacs's own build
# system, then re-create java/install_temp, the staging directory whose
# lib/<abi> and assets/ are exactly what Emacs packages into its APK.
#
#   tools/build-abi.sh arm64-v8a|x86_64 [--keep]
#
# The work tree work/<abi>/emacs-<version> is a fresh extraction of the
# verified tarball; nothing in it is edited. --keep reuses an existing
# work tree (incremental make) instead of extracting again.
set -euo pipefail
. "$(dirname "$0")/env.sh"
abi="${1:?usage: build-abi.sh ABI [--keep]}"; keep="${2:-}"
cc="$(engine_cc_for_abi "$abi")"
engine_check_toolchain
[ -e "$ENGINE_ROOT/upstream/$EMACS_TARBALL" ] || "$ENGINE_ROOT/tools/fetch-upstream.sh"
"$ENGINE_ROOT/tools/fetch-deps.sh"

work="$ENGINE_ROOT/work/$abi"
tree="$work/emacs-$EMACS_VERSION"
if [ "$keep" != "--keep" ] || [ ! -d "$tree" ]; then
  rm -rf "$work"; mkdir -p "$work"
  echo "build-abi: extracting $EMACS_TARBALL into $work"
  tar -xJf "$ENGINE_ROOT/upstream/$EMACS_TARBALL" -C "$work"
  # The GnuTLS ports, unmodified, one directory each (versions.env).
  mkdir -p "$work/ports"
  for pin in $ENGINE_TLS_PORTS; do
    tar -xzf "$ENGINE_ROOT/upstream/deps/${pin%%=*}" -C "$work/ports"
  done
fi
# Every ndk-build module Emacs builds with: SQLite and the TLS ports.
ndk_path="$ENGINE_ROOT/deps/sqlite"
for port in "$work"/ports/*/; do ndk_path="$ndk_path ${port%/}"; done
[ -f "$tree/configure" ] || { echo "build-abi: $tree has no configure script" >&2; exit 1; }

cd "$tree"
jobs="${ENGINE_JOBS:-$(nproc)}"
start=$(date +%s)
if [ ! -f src/config.h.android ]; then
  # Reaches the exec loader's own configure through the environment (see
  # versions.env, ENGINE_LDFLAGS); the host tools link with it harmlessly.
  export LDFLAGS="$ENGINE_LDFLAGS" LOADERFLAGS="$ENGINE_LDFLAGS"
  # Quote the exact command for MANIFEST.json and for reproduction by hand.
  {
    printf '%q ' env "LDFLAGS=$ENGINE_LDFLAGS" "LOADERFLAGS=$ENGINE_LDFLAGS" ./configure "--with-android=$EMACS_ANDROID_JAR" "ANDROID_CC=$cc" \
      "SDK_BUILD_TOOLS=$EMACS_SDK_BUILD_TOOLS" "ANDROID_CFLAGS=$ENGINE_ANDROID_CFLAGS" \
      "--with-ndk-path=$ndk_path" $ENGINE_CONFIGURE_EXTRA
    echo
  } > "$work/configure.cmd"
  echo "build-abi: $(cat "$work/configure.cmd")"
  # shellcheck disable=SC2086
  ./configure "--with-android=$EMACS_ANDROID_JAR" "ANDROID_CC=$cc" \
    "SDK_BUILD_TOOLS=$EMACS_SDK_BUILD_TOOLS" "ANDROID_CFLAGS=$ENGINE_ANDROID_CFLAGS" \
    "--with-ndk-path=$ndk_path" $ENGINE_CONFIGURE_EXTRA
fi
echo "build-abi: make all -j$jobs"
make all -j"$jobs"
# The APK recipe deletes install_temp after zipping it; rebuild the staging
# directory so the harvest can take lib/<abi> and assets/ from it.
make -C java install_temp
end=$(date +%s)
echo "build-abi: $abi done in $((end - start)) s"
ls -la java/*.apk cross/src/libemacs.so
echo "$((end - start))" > "$work/build-seconds"
