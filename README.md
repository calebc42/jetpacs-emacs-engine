# jetpacs-emacs-engine

Builds GNU Emacs for Android as an **engine library** for the Jetpacs
Companion: an AAR carrying `libemacs.so` for arm64-v8a and x86_64, Emacs's
Lisp and data assets, and the unmodified `org.gnu.emacs` Java sources. The
Companion's bundled flavor starts Emacs headless from its own service; see
`jetpacs-poc/docs/PLAN-bundled-emacs.md`.

## Policy

GNU Emacs prohibits LLM-generated contributions (its `AGENTS.md`). This
repository therefore contains **no Emacs source and no patches**. It
downloads the signed release tarball named in `versions.env`, verifies the
SHA-256 and the GPG signature, extracts it untouched under `work/`, and runs
Emacs's own `configure` and `make`. Everything committed here is Jetpacs's
own build glue; nothing is sent upstream.

## Layout

| Path | Purpose |
|---|---|
| `versions.env` | Pinned Emacs version, tarball digest and signing key, NDK, platform, build-tools, ABIs, flags, `ENGINE_BUILD` |
| `tools/env.sh` | Toolchain environment (JDK ≤ 19 for Emacs's `-source 7` javac, NDK, android.jar, build-tools) |
| `tools/fetch-upstream.sh` | Download and verify the tarball (sha256 + GPG against the GNU keyring) |
| `tools/build-abi.sh ABI` | Fresh extraction, `configure`, `make all`, then `make -C java install_temp` |
| `tools/harvest.sh` | Collect `dist/engine-<version>+<build>/` (lib, assets, java, res, proguard.conf, reference APKs, `MANIFEST.json`); checks 16 KB page alignment |
| `tools/package-aar.sh` | Build `dist/jetpacs-emacs-engine-<version>+<build>.aar` + `.sha256` from `dist/current` |
| `tools/build-all.sh` | The whole pipeline; logs under `work/logs/` |
| `tools/publish-release.sh` | Release-named copies under `dist/release/` (`stage`), the developer's publication of a release (`publish`), CI's fill of a release's missing assets (`fill`) |
| `.github/workflows/engine.yml` | Builds both ABIs on a clean runner for every `engine-*` tag (publishing the release) and on manual dispatch |
| `deps/sqlite` | SQLite 3.44.4 as AOSP's `platform/external/sqlite` dist (public domain) with the `Android.mk` Emacs's ndk-build reads; built static into `libemacs.so` for ebp.el's receipts store |
| `android/` | The Gradle project producing the AAR (AGP 9.2.1, namespace `org.gnu.emacs`, empty manifest, consumer keep rules) |

## Build

```sh
source tools/env.sh && engine_check_toolchain
tools/build-all.sh            # or: tools/build-abi.sh arm64-v8a; tools/build-abi.sh x86_64; tools/harvest.sh; tools/package-aar.sh
```

Requirements: NDK r27c (`ANDROID_NDK_VERSION`), platform `android-37.0`,
build-tools 37.0.0, a JDK between 10 and 19 (`JETPACS_ENGINE_JDK`),
autoconf, texinfo, gzip, xz, python3, curl, gpg. A full build of one ABI
compiles the host tools and byte-compiles all of Lisp before cross-compiling
`libemacs.so`; the first-run dump is produced on the device, never here.

## What the AAR contains

- `jni/<abi>/libemacs.so` plus Emacs's helper programs renamed `lib*.so`
  (`libexec1.so` and `libloader.so` run subprocesses under SELinux,
  `libandroid-emacs.so`, `libemacsclient.so`, `libetags.so`, ...);
- `assets/lisp` (`.elc` and gzipped `.el`), `assets/etc` (with the cross
  `DOC`), `assets/info`, `assets/bitmaps`, `assets/directory-tree` (the
  index Emacs's asset VFS stats through), `assets/version`,
  `assets/build_info`;
- `classes.jar` from `java/org/gnu/emacs/*.java` and the generated
  `EmacsConfig.java`, compiled unmodified; `res/` for the resources they
  reference; `proguard.txt` from `java/proguard.conf`.

`MANIFEST.json` in the distribution records the tarball digest, the exact
configure line per ABI, the feature list from `config.h.android`, the
SHA-256 of every shared object and of the asset, Java and resource trees.

## Trimming

`ENGINE_TRIM_ASSETS` in `versions.env` names top-level `assets/` entries the
harvest drops before it rebuilds `directory-tree` with the build's own
`asset-directory-tool`; the index is what Emacs's asset filesystem stats
through, so a trimmed tree is simply absent to it. The default drops
`info`, the Info manuals (21 MB uncompressed), which a headless engine
never reads. Trimming happens only here, never in the Companion.

## Releases and CI

`.github/workflows/engine.yml` builds both ABIs on a clean `ubuntu-latest`
runner (JDK 17, the SDK components `versions.env` names installed through
`sdkmanager`, the tarball fetched and verified there) for every tag
`engine-<version>+<build>`, which must match `versions.env`, and on manual
dispatch. A tag publishes a GitHub release.

Release assets spell the `+` as `-` (`jetpacs-emacs-engine-31.1-2.aar`)
because GitHub rewrites `+` in asset names; the bytes are the same, so the
SHA-256 the Companion pins holds under either name.

The first asset wins. `assets/build_info` inside the AAR carries the build
time, so a rebuild never reproduces a pinned digest, and the AAR on the
release must be the one the Companion pins:

1. `tools/build-all.sh`; pin `EMACS_VERSION+ENGINE_BUILD` and the
   `.sha256` in `jetpacs-poc/companion/gradle/engine.lock` and run
   `:app:verifyBundledEngine` there;
2. push the commit, then `tools/publish-release.sh publish` creates the
   release and its tag from that commit with the local AAR;
3. the workflow runs on the tag, rebuilds as evidence, keeps its own output
   as a workflow artifact and adds only assets the release lacks.

A bare tag push without step 2 lets the workflow provide CI-built assets,
which the Companion then pins. Never upload a second AAR to a release the
Companion already pins. The Companion's CI downloads the pinned asset with
`jetpacs-poc/tools/fetch-engine-aar.sh` and checks the digest against the
lock before every bundled build.

## Versioning

An engine is identified as `EMACS_VERSION+ENGINE_BUILD`, e.g. `31.1+1`.
Bump `ENGINE_BUILD` for any change in `versions.env`, `deps/` or `tools/`
that alters the output; the Companion pins that identifier and the AAR's
SHA-256.
