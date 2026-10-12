# The registry

A static Bazel registry, empty until some consumer needs a version it
holds. It is for patched versions of the four shared modules (gRPC,
Protobuf, Abseil and the OpenTelemetry C++ SDK), and later for this
repository's own module; nothing else.

A patched version is named `<upstream version>.rowkey.<n>`, for example
`1.81.1.rowkey.1`, which sorts above the upstream version. A hyphen, as in
`1.81.1-rowkey.1`, would mark a pre-release, which sorts below 1.81.1. No
version number the central registry uses is ever placed here.

When a consumer needs it, `bazelrc/shared.bazelrc` lists the registry at a
fixed commit, before the central registry, which must then be listed
again, and each consumer takes the two lines through its copy of that
file; `scripts/check.sh` refuses `--registry` anywhere else in a
consumer:

```
common --registry=<URL of this directory at a commit>
common --registry=https://bcr.bazel.build
```
