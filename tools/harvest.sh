#!/usr/bin/env bash
# Collect the engine distribution dist/engine-<version>+<build>/ from the
# per-ABI work trees built by tools/build-abi.sh:
#
#   lib/<abi>/*.so      the Emacs shared object and its lib*.so helper programs
#   assets/             lisp, etc (with the cross DOC), info, bitmaps,
#                       directory-tree, version, build_info (from the first ABI)
#   java/org/gnu/emacs/ the pristine Java sources plus the generated
#                       EmacsConfig.java; R.java is left out (AGP generates R)
#   res/                the resources those sources reference
#   proguard.conf       Emacs's keep rules, shipped as consumer rules
#   reference/          the stock APKs Emacs's build produced, for A/B checks
#   MANIFEST.json       provenance, checksums, feature list, page-size check
set -euo pipefail
. "$(dirname "$0")/env.sh"
dist="$ENGINE_DIST"
rm -rf "$dist"; mkdir -p "$dist/lib" "$dist/reference"
first=""
for abi in $ENGINE_ABIS; do
  tree="$ENGINE_ROOT/work/$abi/emacs-$EMACS_VERSION"
  staging="$tree/java/install_temp"
  [ -d "$staging/lib/$abi" ] || { echo "harvest: $staging/lib/$abi missing; run tools/build-abi.sh $abi" >&2; exit 1; }
  cp -a "$staging/lib/$abi" "$dist/lib/$abi"
  cp -a "$tree"/java/emacs-*.apk "$dist/reference/" 2>/dev/null || true
  if [ -z "$first" ]; then
    first="$abi"
    cp -a "$staging/assets" "$dist/assets"
    mkdir -p "$dist/java/org/gnu/emacs"
    for f in "$tree"/java/org/gnu/emacs/*.java; do
      case "$(basename "$f")" in R.java) ;; *) cp -a "$f" "$dist/java/org/gnu/emacs/" ;; esac
    done
    [ -f "$dist/java/org/gnu/emacs/EmacsConfig.java" ] || { echo "harvest: generated EmacsConfig.java missing" >&2; exit 1; }
    cp -a "$tree/java/res" "$dist/res"
    cp -a "$tree/java/proguard.conf" "$dist/proguard.conf"
  fi
done

# 16 KB page alignment: every LOAD segment of every shared object must be
# aligned to 0x4000 or more (Android 15+ devices with 16 KB pages).
align_ok=1
for so in "$dist"/lib/*/*.so; do
  # librcs2log.so is a shell script wearing the lib*.so naming convention.
  [ "$(head -c 4 "$so" | tr -d '\0')" = $'\x7fELF' ] || continue
  for align in $("$ENGINE_LLVM_BIN/llvm-readelf" -lW "$so" | awk '$1=="LOAD" { print $NF }'); do
    if [ "$((align))" -lt 16384 ]; then
      echo "harvest: $so has a LOAD segment aligned below 16 KB ($align)" >&2; align_ok=0
    fi
  done
done
[ "$align_ok" = 1 ] || exit 1

# Assets must not depend on the ABI; compare the trees minus build_info.
for abi in $ENGINE_ABIS; do
  [ "$abi" = "$first" ] && continue
  other="$ENGINE_ROOT/work/$abi/emacs-$EMACS_VERSION/java/install_temp/assets"
  if ! diff -rq --exclude=build_info "$dist/assets" "$other" >/dev/null; then
    echo "harvest: WARNING assets differ between $first and $abi:" >&2
    diff -rq --exclude=build_info "$dist/assets" "$other" | head -20 >&2
  fi
done

ENGINE_FIRST_ABI="$first" python3 - "$dist" <<'PY'
import hashlib, json, os, subprocess, sys, time
dist = sys.argv[1]; env = os.environ
def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()
def tree_digest(root, exclude=()):
    h = hashlib.sha256(); n = 0; size = 0
    for d, _, files in sorted(os.walk(root)):
        for name in sorted(files):
            rel = os.path.relpath(os.path.join(d, name), root)
            if rel in exclude: continue
            p = os.path.join(d, name); n += 1; size += os.path.getsize(p)
            h.update(rel.encode()); h.update(b"\0"); h.update(sha256(p).encode()); h.update(b"\n")
    return {"files": n, "bytes": size, "sha256": h.hexdigest()}
root = env["ENGINE_ROOT"]; ver = env["EMACS_VERSION"]
abis = {}
for abi in env["ENGINE_ABIS"].split():
    work = os.path.join(root, "work", abi); tree = os.path.join(work, f"emacs-{ver}")
    libs = {f: sha256(os.path.join(dist, "lib", abi, f)) for f in sorted(os.listdir(os.path.join(dist, "lib", abi)))}
    cfg = open(os.path.join(tree, "src", "config.h.android")).read()
    feats = [l for l in cfg.splitlines() if "EMACS_CONFIG_FEATURES" in l]
    seconds = open(os.path.join(work, "build-seconds")).read().strip() if os.path.exists(os.path.join(work, "build-seconds")) else None
    abis[abi] = {"android_cc": os.path.basename(subprocess.check_output(["bash", "-c", f". {root}/tools/env.sh; engine_cc_for_abi {abi}"]).decode().strip()),
                 "configure": open(os.path.join(work, "configure.cmd")).read().strip(),
                 "features": feats[0].split('"')[1] if feats else None,
                 "libemacs_sha256": libs.get("libemacs.so"), "libs": libs,
                 "page_align_16k": True, "build_seconds": int(seconds) if seconds else None}
manifest = {
  "engine": f"{ver}+{env['ENGINE_BUILD']}", "emacs_version": ver, "engine_build": int(env["ENGINE_BUILD"]),
  "tarball": {"name": env["EMACS_TARBALL"], "sha256": env["EMACS_TARBALL_SHA256"], "url": env["EMACS_TARBALL_URL"], "signing_key": env["EMACS_SIGNING_KEY"]},
  "toolchain": {"ndk": env["ANDROID_NDK_VERSION"], "android_api": int(env["ANDROID_API"]), "platform": env["ANDROID_PLATFORM"], "build_tools": env["ANDROID_BUILD_TOOLS"],
                "javac": subprocess.run([os.path.join(env["JAVA_HOME"], "bin", "javac"), "-version"], capture_output=True, text=True).stdout.strip() or subprocess.run([os.path.join(env["JAVA_HOME"], "bin", "javac"), "-version"], capture_output=True, text=True).stderr.strip()},
  "deps": {"sqlite": {"version": "3.44.4 (AOSP platform/external/sqlite dist, fdsan patch)", "module": "libsqlite_static_minimal", "sqlite3_c_sha256": sha256(os.path.join(root, "deps", "sqlite", "sqlite-autoconf-3440400", "sqlite3.c"))}},
  "abis": abis,
  "assets": tree_digest(os.path.join(dist, "assets"), exclude=("build_info",)),
  "assets_first_abi": env["ENGINE_FIRST_ABI"],
  "java": tree_digest(os.path.join(dist, "java")), "res": tree_digest(os.path.join(dist, "res")),
  "proguard_conf_sha256": sha256(os.path.join(dist, "proguard.conf")),
  "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "host": os.uname().nodename,
}
json.dump(manifest, open(os.path.join(dist, "MANIFEST.json"), "w"), indent=2, sort_keys=True); print(json.dumps({k: manifest[k] for k in ("engine", "assets")}, indent=2))
PY
ln -sfn "$ENGINE_DIST_NAME" "$ENGINE_ROOT/dist/current"
echo "harvest: $dist ready; dist/current -> $ENGINE_DIST_NAME"
du -sh "$dist"/lib/* "$dist/assets" "$dist/reference" 2>/dev/null
