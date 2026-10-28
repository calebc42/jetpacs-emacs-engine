#!/usr/bin/env bash
# Release-named copies of the built engine, and their publication as a GitHub
# release of this repository.
#
#   tools/publish-release.sh stage          dist/release/: the AAR, its .sha256,
#                                           MANIFEST.json and NOTES.md under release names,
#                                           and the corresponding source
#   tools/publish-release.sh publish [SHA]  developer path: create release engine-<id>
#                                           (and its tag, on SHA, default the local HEAD,
#                                           which must be pushed) from this dist/;
#                                           refuses a release that already exists
#   tools/publish-release.sh fill TAG       CI path: create the release if absent,
#                                           upload only the assets it lacks
#
# The engine id is EMACS_VERSION+ENGINE_BUILD from versions.env. GitHub
# rewrites "+" in asset names, so the assets spell it with "-"
# (jetpacs-emacs-engine-31.1-2.aar); the bytes are the same, so the SHA-256
# the Companion pins in gradle/engine.lock holds under either name.
#
# The first asset wins. assets/build_info inside the AAR carries the build
# time, so a rebuild never reproduces a pinned digest: the AAR on the
# release must be the one the Companion pins. `publish` uploads the
# developer's own build, which the Companion was pinned against first; the
# tag it creates runs the engine workflow, whose `fill` then finds the
# assets present and adds nothing. A bare tag push without a prior
# `publish` lets `fill` provide CI-built assets, which the Companion pins
# afterwards. Never upload a second AAR to a release the Companion already
# pins.
#
# Every release also carries the corresponding source of what the AAR
# contains (README.md, "Policy"): the Emacs tarball with its signature and
# each GnuTLS port, unmodified and checked against versions.env, so the
# release offers it at the same place as the binaries and never depends on
# the upstream hosts staying up. SQLite and the build glue are this
# repository at the release tag.
set -euo pipefail
. "$(dirname "$0")/env.sh"
id="$EMACS_VERSION+$ENGINE_BUILD"
rid="${id//+/-}"
tag="engine-$id"
release="$ENGINE_ROOT/dist/release"
aar="$ENGINE_ROOT/dist/jetpacs-emacs-engine-$id.aar"
manifest="$ENGINE_DIST/MANIFEST.json"
title="Jetpacs Emacs engine $id"

die() { echo "publish-release: $*" >&2; exit 1; }

notes() {
  python3 -I - "$manifest" "$release/jetpacs-emacs-engine-$rid.aar.sha256" \
    "$id" "$EMACS_VERSION" "$EMACS_TARBALL" "$EMACS_TARBALL_SHA256" "$EMACS_SIGNING_KEY" \
    "$EMACS_TARBALL_URL" <<'PY'
import json, sys
manifest, shafile, eid, version, tarball, tarball_sha, key, tarball_url = sys.argv[1:9]
m = json.load(open(manifest))
aar_sha = open(shafile).read().split()[0]
rid = eid.replace("+", "-")
print(f"GNU Emacs {version} built unmodified for Android as the Jetpacs Companion's "
      f"bundled engine (README.md). Source: `{tarball}`, SHA-256 `{tarball_sha}`, "
      f"signed by `{key}`; no Emacs source or patch lives in this repository.\n")
print(f"| Asset | SHA-256 |\n|---|---|\n| `jetpacs-emacs-engine-{rid}.aar` | `{aar_sha}` |\n")
print("Asset names spell the `+` of the engine id as `-` (GitHub rewrites `+`); "
      "the Companion pins the digest, which is the same under either name:\n")
print(f"```\nengine={eid}\nsha256={aar_sha}\n```\n")
abis = m.get("abis", {})
if abis:
    print("| ABI | libemacs.so SHA-256 | features |\n|---|---|---|")
    for abi, info in sorted(abis.items()):
        print(f"| {abi} | `{info.get('libemacs_sha256', '?')}` | {info.get('features', '?')} |")
    print()
deps = m.get("deps", {})
print("Corresponding source, attached to this release unmodified:\n")
print("| Source | SHA-256 | Upstream |\n|---|---|---|")
print(f"| `{tarball}` (and `.sig`) | `{tarball_sha}` | <{tarball_url}> |")
for name, info in sorted(deps.items()):
    if "url" in info:
        print(f"| `{name}` | `{info['sha256']}` | <{info['url']}> |")
print()
if "sqlite" in deps:
    print(f"SQLite {deps['sqlite'].get('version', '')} and the build glue are this "
          "repository at the release tag (`deps/sqlite`, `tools/`).\n")
for k in ("engine", "assets_trimmed"):
    if k in m:
        print(f"- {k}: {m[k]}")
PY
}

stage() {
  [ -f "$aar" ] || die "$aar is missing; run tools/build-all.sh"
  [ -f "$manifest" ] || die "$manifest is missing; run tools/harvest.sh"
  (cd "$ENGINE_ROOT/dist" && sha256sum -c "jetpacs-emacs-engine-$id.aar.sha256")
  mkdir -p "$release"
  cp -f "$aar" "$release/jetpacs-emacs-engine-$rid.aar"
  cp -f "$manifest" "$release/jetpacs-emacs-engine-$rid-MANIFEST.json"
  (cd "$release" && sha256sum "jetpacs-emacs-engine-$rid.aar" > "jetpacs-emacs-engine-$rid.aar.sha256")
  (cd "$ENGINE_ROOT/upstream" && echo "$EMACS_TARBALL_SHA256  $EMACS_TARBALL" | sha256sum -c -)
  cp -fL "$ENGINE_ROOT/upstream/$EMACS_TARBALL" "$ENGINE_ROOT/upstream/$EMACS_TARBALL.sig" "$release/"
  for pin in $ENGINE_TLS_PORTS; do
    (cd "$ENGINE_ROOT/upstream/deps" && echo "${pin#*=}  ${pin%%=*}" | sha256sum -c -)
    cp -f "$ENGINE_ROOT/upstream/deps/${pin%%=*}" "$release/"
  done
  notes > "$release/NOTES.md"
  ls -la "$release"
}

assets() {
  printf '%s\n' "$release/jetpacs-emacs-engine-$rid".* "$release/jetpacs-emacs-engine-$rid-MANIFEST.json" \
    "$release/$EMACS_TARBALL" "$release/$EMACS_TARBALL.sig"
  for pin in $ENGINE_TLS_PORTS; do printf '%s\n' "$release/${pin%%=*}"; done
}

publish() {
  local target="${1:-$(git -C "$ENGINE_ROOT" rev-parse HEAD)}"
  command -v gh >/dev/null || die "gh is required"
  stage
  if gh release view "$tag" >/dev/null 2>&1; then
    die "release $tag exists; an AAR the Companion pins is never replaced (see the header)"
  fi
  # shellcheck disable=SC2046
  gh release create "$tag" --target "$target" --title "$title" \
    --notes-file "$release/NOTES.md" $(assets)
}

fill() {
  local t="${1:?fill needs the tag}" have f name
  [ "$t" = "$tag" ] || die "tag $t is not $tag (versions.env)"
  [ -d "$release" ] || stage
  if ! gh release view "$t" >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    gh release create "$t" --verify-tag --title "$title" \
      --notes-file "$release/NOTES.md" $(assets)
    return
  fi
  have="$(gh release view "$t" --json assets -q '.assets[].name')"
  for f in $(assets); do
    name="$(basename "$f")"
    if printf '%s\n' "$have" | grep -qx "$name"; then
      echo "publish-release: $name is already on $t; kept (first asset wins)"
    else
      gh release upload "$t" "$f"
    fi
  done
}

case "${1:-}" in
  stage) stage ;;
  publish) shift; publish "$@" ;;
  fill) shift; fill "$@" ;;
  *) sed -n 2,14p "$0" >&2; exit 1 ;;
esac
