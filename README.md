# rowkeydb-build-infra

The shared build infrastructure of RowKeyDB, RowKeyRaft, Limen and
zetasketch-cpp: one place in which to choose, and to update, the versions
and build options of their large dependencies (the compilers, gRPC,
Protobuf, Abseil and the OpenTelemetry C++ SDK).

It holds:

- `image.bzl`: the image every build runs in, named by the digest of each
  architecture's image. This is the authoritative copy of the digest.
- `MODULE.bazel`: the Bazel module `rowkeydb_build_infra`, which declares
  the approved versions of the shared modules as "nodep" dependencies:
  Abseil, protobuf, gRPC, the OpenTelemetry C++ SDK, googletest, zlib, RE2,
  BoringSSL, c-ares, Google Benchmark, protoc-gen-validate, googleapis and
  its two C++ modules, and the rules the consumers' graphs hold (rules_cc,
  bazel_lib, bazel_skylib, package_metadata, rules_proto, rules_python).
  It also declares the Go rules and Gazelle, which are shared modules as
  well, and the Go SDK every consumer builds its Go with.
- `gazelle/defs.bzl`: the Gazelle targets every consumer defines in
  `bazel/gazelle`, the one which writes the BUILD files of its Go code and
  the test which fails when they differ from what Gazelle would write.
  This repository defines them too, and its check workflow runs the test,
  with the shared options, which its `.bazelrc` imports.
- `go/`: the nogo target, which consumers with Go register and which
  replaces go vet and golangci-lint: the analyzers golangci-lint 2.15.0
  runs by default for govet, staticcheck, errcheck, ineffassign and
  unused, at the versions of its go.mod, which `go/go.mod` repeats.
  `go/analyzers.bzl` lists them. `go/unused` reports what staticcheck's
  unused-code check finds, and `go/inline` gives go vet's inline analyzer
  the file reader nogo leaves unset. This repository's own Go is checked
  with it too.
- `clang_tidy.bzl`: the remote and commit of the clang-tidy aspect the
  shared clang-tidy configuration runs.
- `buildbuddy/`: the platforms BuildBuddy runs the consumers' actions on,
  which the shared options select.
- `bazelrc/shared.bazelrc`: the shared build options. A consumer keeps a
  checked copy and imports it as the first option line of its `.bazelrc`.
- `allowlists/`: for each consumer, its own build lines, with the reason
  for each: the option lines of its `.bazelrc` after the import, the
  overrides, patches and shared-module declarations of its `MODULE.bazel`,
  and the `copts`, `features` and `defines` of its BUILD files. A line is
  added here before the consumer adds it, and removed after.
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
  versions agree with a commit of this repository, from v0.9.0 that its
  own build lines are on its allowlist, and from v0.10.0 that its Go SDK
  and the Go release of its go.mod and go.work files are the approved ones.
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
earlier image's apart from the differences `manifests/README.md` lists,
that of `v0.3.1` differs from `v0.2.0`'s in the MSan libraries and in
`gcov` and `cpp`, that of `v0.4.0` from `v0.3.1`'s in Go and
golangci-lint, and that of `v0.5.0` from `v0.4.0`'s in Bazel, as it
also lists. Each image is tagged with the name of
the release that first names it; consumers name it by digest, never by
tag. rowkeydb moved to the image of `v0.2.0`, then to the image `v0.3.2`
names, with the one set of options for third-party code, and then to
`v0.4.0`'s, with Go 1.27.3 inside and outside Bazel; the other three
repositories are brought in later. RowKeyDB's
`design/shared_build_architecture.md` describes each step and the
evidence it requires.

Licensed under the Apache License, Version 2.0; see `LICENSE`.
