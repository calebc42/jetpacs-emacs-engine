#!/usr/bin/env bash
# Obtain and verify the ndk-build ports pinned in versions.env
# (ENGINE_TLS_PORTS: GnuTLS and its dependencies). Like the Emacs tarball
# they are never edited: build-abi.sh extracts each into the ABI's work tree
# and names it in --with-ndk-path, as Emacs's java/INSTALL (GNUTLS) directs.
set -euo pipefail
. "$(dirname "$0")/env.sh"
mkdir -p "$ENGINE_ROOT/upstream/deps"
cd "$ENGINE_ROOT/upstream/deps"
for pin in $ENGINE_TLS_PORTS; do
  name="${pin%%=*}" sha="${pin#*=}"
  if [ ! -e "$name" ]; then
    echo "fetch-deps: downloading $name"
    # The project's download page redirects to a mirror.
    curl -fL --retry 3 -A "Wget/1.21" -o "$name.part" "$ENGINE_PORTS_URL/$name/download"
    mv "$name.part" "$name"
  fi
  echo "$sha  $name" | sha256sum -c -
done
