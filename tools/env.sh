# Toolchain environment for building the Jetpacs Emacs engine.
# Source this in every shell that runs tools/*.sh:
#
#   source tools/env.sh
#
# Overrides: ANDROID_HOME, JETPACS_ENGINE_JDK (a JDK <= 19: Emacs's own
# Android build compiles Java with -source 7, which JDK 20+ rejects).
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ENGINE_ROOT
# shellcheck source=../versions.env
. "$ENGINE_ROOT/versions.env"
export EMACS_VERSION EMACS_TARBALL EMACS_TARBALL_URL EMACS_TARBALL_SHA256 \
  EMACS_SIGNING_KEY ENGINE_BUILD ANDROID_API ANDROID_NDK_VERSION \
  ANDROID_PLATFORM ANDROID_BUILD_TOOLS ENGINE_ABIS ENGINE_ANDROID_CFLAGS \
  ENGINE_CONFIGURE_EXTRA ENGINE_LDFLAGS ENGINE_TRIM_ASSETS ENGINE_PORTS_URL \
  ENGINE_TLS_PORTS

export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/$ANDROID_NDK_VERSION"
export JAVA_HOME="${JETPACS_ENGINE_JDK:-$HOME/.gradle/jdks/eclipse_adoptium-17-amd64-linux.2}"
export PATH="$JAVA_HOME/bin:$PATH"
export EMACS_ANDROID_JAR="$ANDROID_HOME/platforms/$ANDROID_PLATFORM/android.jar"
export EMACS_SDK_BUILD_TOOLS="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS"
export ENGINE_LLVM_BIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
export ENGINE_DIST_NAME="engine-$EMACS_VERSION+$ENGINE_BUILD"
export ENGINE_DIST="$ENGINE_ROOT/dist/$ENGINE_DIST_NAME"

# The ANDROID_CC for an ABI, derived the way Emacs's configure derives the
# ABI from the compiler name (configure.ac, android_abi).
engine_cc_for_abi() {
  case "$1" in
    arm64-v8a) echo "$ENGINE_LLVM_BIN/aarch64-linux-android$ANDROID_API-clang" ;;
    x86_64)    echo "$ENGINE_LLVM_BIN/x86_64-linux-android$ANDROID_API-clang" ;;
    *) echo "engine: unsupported ABI '$1' (use arm64-v8a or x86_64)" >&2; return 1 ;;
  esac
}

engine_check_toolchain() {
  # Everything local: callers hold their ABI in `abi` too.
  local ok=1 f abi tool
  "$JAVA_HOME/bin/javac" -version 2>&1 | grep -q '^javac 1[0-9]\.' || {
    echo "engine: javac at $JAVA_HOME is not JDK 10..19: $("$JAVA_HOME/bin/javac" -version 2>&1)" >&2; ok=0; }
  for f in "$EMACS_ANDROID_JAR" "$EMACS_SDK_BUILD_TOOLS/aapt" "$EMACS_SDK_BUILD_TOOLS/d8" \
           "$EMACS_SDK_BUILD_TOOLS/apksigner" "$EMACS_SDK_BUILD_TOOLS/zipalign" \
           "$ENGINE_LLVM_BIN/llvm-readelf"; do
    [ -e "$f" ] || { echo "engine: missing $f" >&2; ok=0; }
  done
  for abi in $ENGINE_ABIS; do
    [ -x "$(engine_cc_for_abi "$abi")" ] || { echo "engine: missing compiler for $abi" >&2; ok=0; }
  done
  for tool in autoconf makeinfo gzip xz tar python3 sha256sum; do
    command -v "$tool" >/dev/null || { echo "engine: missing host tool $tool" >&2; ok=0; }
  done
  [ "$ok" = 1 ]
}
