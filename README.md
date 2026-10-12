# rowkeydb-build-infra

The shared build infrastructure of RowKeyDB, RowKeyRaft, Limen and
zetasketch-cpp: one place in which to choose, and to update, the versions
and build options of their large dependencies (the compilers, gRPC,
Protobuf, Abseil and the OpenTelemetry C++ SDK).

It holds:

- `image.bzl`: the image every build runs in, named by the digest of each
  architecture's image. This is the authoritative copy of the digest.
- `MODULE.bazel`: the Bazel module `rowkeydb_build_infra`, which declares
  the approved versions of the four shared modules as "nodep"
  dependencies.
- `bazelrc/shared.bazelrc`: the shared build options. A consumer keeps a
  checked copy and imports it.
- `registry/`: a Bazel registry for patched versions of the shared
  modules, empty until one is needed.
- `recipe/Dockerfile.ci`: the recipe of the image `image.bzl` names. That
  image was built by rowkeydb's workflow, not by this repository, and the
  recipe is kept as the record of what it contains.
- `scripts/manifest.sh`: lists an image's configuration, every Debian
  package, every file with its extended attributes and content, and the
  versions of the tools installed outside Debian's packages, so that two
  images can be compared.
- `scripts/check.sh`: checks that a consumer's copies, pins and declared
  versions agree with a commit of this repository.
- `manifests/`: the checksums of the images' manifests, which are kept as
  release assets.
- `evidence/`: the tools that compare a consumer's builds before and after
  a change.

Every reference a consumer makes to this repository names a commit or a
digest, so that any past commit of a consumer builds as it did. A change
is one commit here, followed in each consumer by one commit which moves its
pins and passes `scripts/check.sh`, run from the newest commit of main: the
script reads the commit a consumer names from the clone it runs in, so it
checks the consumers of earlier releases as well. A consumer names a
commit through a release, whose asset is that commit's archive. Releases
are immutable: once a release is published, GitHub refuses to move its
tag or to change or delete its assets. GitHub still allows a whole release
to be deleted, which would stop every past commit that names it from
building, so this repository's releases are never deleted.

rowkeydb is the first consumer. It adopts this repository without any
change to its build: the same image, Bazel version, module versions and
build options. The image is the linux/amd64 image of
`ghcr.io/chanzo-dev/rowkeydb-ci` that `image.bzl` names, copied unchanged
and tagged `v0.1.0`; consumers name it by digest, never by tag. Next, the
image is rebuilt from a recipe that reproduces it, and then the other
three repositories are brought in. RowKeyDB's
`design/shared_build_architecture.md` describes each step and the evidence
it requires.

Licensed under the Apache License, Version 2.0; see `LICENSE`.
