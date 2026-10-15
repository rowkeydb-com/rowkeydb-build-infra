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
- `recipe/Dockerfile`: the recipe of the image `image.bzl` names, with
  every input pinned, so that two builds give the same image. The inputs
  no other place is sure to keep, apt.llvm.org's packages and the Maven
  repository of the HBase tests, are the assets of the release
  `image-inputs-20261001`, which holds no commit's archive.
  `recipe/llvm-debs.sha256` and `recipe/requirements.txt` hold the
  checksums of the packages, and `recipe/files/` the files the recipe
  copies in.
- `recipe/Dockerfile.ci`: the recipe of the image the releases `v0.1.0`
  and `v0.1.1` name. That image was built by rowkeydb's workflow, not by
  this repository, and the recipe is kept as the record of what it
  contains.
- `scripts/build-image.sh`: builds `recipe/Dockerfile` with a pinned
  builder and no build cache. The workflow `build-image.yml`, started by
  hand, runs it and pushes the image by digest.
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

rowkeydb is the first consumer. It adopted this repository without any
change to its build: the same image, Bazel version, module versions and
build options. The image of the releases `v0.1.0` and `v0.1.1` is the
linux/amd64 image of `ghcr.io/chanzo-dev/rowkeydb-ci`, copied unchanged
and tagged `v0.1.0`. From `v0.2.0` on, the image is built from
`recipe/Dockerfile`; the manifest of the image of `v0.2.0` equals the
earlier image's apart from the differences `manifests/README.md` lists.
Each image is tagged with the name of the release that first names it;
consumers name it by digest, never by tag. Next, rowkeydb moves to the
image of `v0.2.0`; the other three repositories are brought in later.
RowKeyDB's `design/shared_build_architecture.md` describes each step and
the evidence it requires.

Licensed under the Apache License, Version 2.0; see `LICENSE`.
