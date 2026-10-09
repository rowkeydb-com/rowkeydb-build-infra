# Manifests

`scripts/manifest.sh` writes the manifest of an image. A manifest lists:

- the image's configuration;
- the version of every Debian package;
- the type, mode, owner and extended attributes of every file;
- the SHA-256 of every regular file;
- the versions of the tools installed outside Debian's packages.

A manifest is about 38 MB, so the manifests are kept as assets of this
repository's releases and compressed with zstd, as `manifest-*.txt.zst`.
`SHA256SUMS` here holds the checksums of the decompressed files. Each
manifest is named by the first eight hexadecimal digits of the digest of
the linux/amd64 image it describes.

- `manifest-a1c8fa1e.txt` describes the image `image.bzl` names,
  `sha256:a1c8fa1e1a3b49e61cfcd3240e18d4a1288b6375fb95e025c3d31f7f37b0145e`.
  It is the linux/amd64 image of index `sha256:9716b9a8...` in
  `ghcr.io/chanzo-dev/rowkeydb-ci`.
- `manifest-4f804cd9.txt` describes the other build of the same recipe on
  2026-10-01,
  `sha256:4f804cd9db4a8924bfcd27dc4b6b98011e514657041758ecf67f2ed580cf09a1`.
  It is the linux/amd64 image of index `sha256:fc492a87...`, which
  rowkeydb's self-hosted runners held.

The two images have the same configuration, packages, extended attributes
and tool versions. They differ in five paths and in nothing else:

- the Bazel server's log written while the image was built (its name, its
  content and the link to it);
- tflint's record of a version check
  (`/root/.cache/tflint/version_check_cache.json`);
- terraform's checkpoint signature (`/root/.terraform.d/checkpoint_signature`);
- wget's HSTS list (`/root/.wget-hsts`).

No build or check reads these files: Bazel runs with `HOME=/tmp`, and
terraform with `HOME=/workspace`. The two images are therefore equivalent
for every build. `image.bzl` names the first, which a new pull of the
index obtains.
