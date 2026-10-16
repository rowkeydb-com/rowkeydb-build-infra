# Manifests

`scripts/manifest.sh` writes the manifest of an image. A manifest lists:

- the image's configuration: its command, entry point, environment,
  shell, user and working directory;
- the version of every Debian package;
- the type, mode, owner and extended attributes of every file;
- the SHA-256 of every regular file;
- the versions of the tools installed outside Debian's packages.

A manifest is 29 to 38 MB, so the manifests are kept as assets of this
repository's releases and compressed with zstd, as `manifest-*.txt.zst`.
`SHA256SUMS` here holds the checksums of the decompressed files. Each
manifest is named by the first eight hexadecimal digits of the digest of
the linux/amd64 image it describes.

- `manifest-a612ddba.txt` describes the image `image.bzl` names,
  `sha256:a612ddbaafe981453ff6ea9a2fee8906462be071b4f6369279d28b7f64fdfc15`,
  which `scripts/build-image.sh` builds from `recipe/Dockerfile` at
  d815082, for the release `v0.3.0`.
- `manifest-07ce31e8.txt` describes the image of `v0.2.0`,
  `sha256:07ce31e8be9d63aadccae2a36dfcbb30c2250ef8e7279366e661536f0b14cd3e`,
  which `scripts/build-image.sh` builds from `recipe/Dockerfile` at 0e4332f.
- `manifest-a1c8fa1e.txt` describes the image the releases `v0.1.0` and
  `v0.1.1` name,
  `sha256:a1c8fa1e1a3b49e61cfcd3240e18d4a1288b6375fb95e025c3d31f7f37b0145e`,
  built from `recipe/Dockerfile.ci`. It is the linux/amd64 image of index
  `sha256:9716b9a8...` in `ghcr.io/chanzo-dev/rowkeydb-ci`.
- `manifest-4f804cd9.txt` describes the other build of
  `recipe/Dockerfile.ci` on 2026-10-01,
  `sha256:4f804cd9db4a8924bfcd27dc4b6b98011e514657041758ecf67f2ed580cf09a1`.
  It is the linux/amd64 image of index `sha256:fc492a87...`, which
  rowkeydb's self-hosted runners held.

The images `a1c8fa1e` and `4f804cd9` have the same configuration,
packages, extended attributes and tool versions. They differ in five paths
and in nothing else:

- the Bazel server's log written while the image was built (its name, its
  content and the link to it);
- tflint's record of a version check
  (`/root/.cache/tflint/version_check_cache.json`);
- terraform's checkpoint signature (`/root/.terraform.d/checkpoint_signature`);
- wget's HSTS list (`/root/.wget-hsts`).

No build or check reads these files: Bazel runs with `HOME=/tmp`, and
terraform with `HOME=/workspace`. The two images are therefore equivalent
for every build. The releases `v0.1.0` and `v0.1.1` name the first, which
a new pull of the index obtains.

The manifest of the image `07ce31e8` lists the configuration, packages and
extended attributes of `a1c8fa1e`. It differs from `a1c8fa1e`'s manifest
in the following, which RowKeyDB's `design/shared_build_architecture.md`
lists as the rebuild's intended changes, and in nothing else:

- Bazelisk holds Bazel 7.6.1, the version the consumers use, where
  `a1c8fa1e` holds 9.2.0, the highest version Bazel had released when
  that image was built, which Bazelisk took for the latest. The other
  tools have the same versions.
- Absent or changed, because their content or name depends on the time
  or the machine of the build:
  - tflint's record, terraform's checkpoint signature and wget's HSTS
    list, named above, and terraform's record of its latest release
    (`/root/.terraform.d/checkpoint_cache`);
  - Bazel 9.2.0's install base and output base, with its server's log
    (`/root/.cache/bazel/_bazel_root`);
  - gcloud's records of its update check and survey prompt, its logs, and
    its answer to whether it runs on Compute Engine (in
    `/root/.config/gcloud`, which keeps gcloud's configuration);
  - Go's build cache and telemetry counters (`/root/.cache/go-build`,
    `/root/.config/go/telemetry`) and its checksum database's records
    (`/root/go/pkg/sumdb` and `/root/go/pkg/mod/cache/download/sumdb`);
  - pip's HTTP cache (`/root/.cache/pip/http-v2`);
  - the Python bytecode of the environment `/opt/ansible-env`, which
    records the times of its sources; the `RECORD` files of the packages
    pip installs there no longer list it, while pip's own, written when
    the environment is made, still does;
  - the logs of apt, dpkg and update-alternatives under `/var/log`, and
    the caches of ldconfig (`/var/cache/ldconfig/aux-cache`) and
    fontconfig (the `.cache-9` files in `/var/cache/fontconfig`);
  - the machine identifiers: `/var/lib/dbus/machine-id` is absent and
    `/etc/machine-id` is empty;
  - the build machine's resolver configuration
    (`/run/systemd/resolve/stub-resolv.conf`).
- Absent, because it varies from one build to the next: gcloud's Python
  bytecode (under `/usr/local/google-cloud-sdk`), which gcloud compiles
  with several worker processes and which depends on how the files are
  shared among them.
- Absent with them, the directories which held nothing else:
  `/root/.cache/bazel` and `/root/.cache/pip`.

The files under `/opt/maven_cache` keep their contents and modes; only
their times, which a manifest does not list, are 1970-01-01.

The manifest of the image `a612ddba` differs from that of `07ce31e8` in
the following, which RowKeyDB's `design/shared_build_architecture.md`
lists as the later changes made in the image, and in nothing else: the
configuration, the Debian packages and the extended attributes are the
same.

- The MSan builds of libc++, libc++abi, libc++experimental and libunwind
  (`/usr/lib/llvm-19/lib/msan/*.a`) are built from the LLVM 19.1.7
  sources, the release of the clang 19 and libc++ headers in the image,
  where `07ce31e8`'s were built from 19.1.0.
- `/usr/bin/gcov` and `/usr/bin/cpp` link to `gcov-14` and `cpp-14`,
  where they linked to GCC 13's, so that coverage reads GCC 14's objects
  with GCC 14's `gcov`.
- Go, under `/usr/local/go`, is 1.27.1, the version rowkeydb's Bazel
  builds download, where it was 1.25.14; and golangci-lint 1.64.8 is
  built by it, so its binary differs and reports that Go.
