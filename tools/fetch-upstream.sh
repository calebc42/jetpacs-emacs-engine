#!/usr/bin/env bash
# Obtain and verify the pristine Emacs release tarball named in versions.env.
# The tarball is never unpacked here and never modified anywhere: the engine
# is built from an untouched extraction of it (see README.md, "Policy").
set -euo pipefail
. "$(dirname "$0")/env.sh"
# A fresh clone has no upstream/ yet (its contents are ignored by git).
mkdir -p "$ENGINE_ROOT/upstream"
cd "$ENGINE_ROOT/upstream"

if [ ! -e "$EMACS_TARBALL" ]; then
  echo "fetch-upstream: downloading $EMACS_TARBALL_URL"
  curl -fL --retry 3 -o "$EMACS_TARBALL" "$EMACS_TARBALL_URL"
fi
if [ ! -e "$EMACS_TARBALL.sig" ]; then
  curl -fL --retry 3 -o "$EMACS_TARBALL.sig" "$EMACS_TARBALL_URL.sig"
fi

echo "$EMACS_TARBALL_SHA256  $EMACS_TARBALL" | sha256sum -c -

# Signature: the key must verify as the pinned fingerprint. Try the user's
# keyring first, then the GNU keyring fetched beside the tarball.
verify_with() { gpg --batch --status-fd 1 "$@" --verify "$EMACS_TARBALL.sig" "$EMACS_TARBALL" 2>/dev/null \
  | grep -q "VALIDSIG $EMACS_SIGNING_KEY"; }
if verify_with; then
  echo "fetch-upstream: signature valid ($EMACS_SIGNING_KEY, user keyring)"
else
  [ -e gnu-keyring.gpg ] || curl -fL --retry 3 -o gnu-keyring.gpg https://ftp.gnu.org/gnu/gnu-keyring.gpg
  if verify_with --no-default-keyring --keyring "$PWD/gnu-keyring.gpg"; then
    echo "fetch-upstream: signature valid ($EMACS_SIGNING_KEY, GNU keyring)"
  else
    echo "fetch-upstream: signature of $EMACS_TARBALL did not verify against $EMACS_SIGNING_KEY" >&2
    exit 1
  fi
fi
