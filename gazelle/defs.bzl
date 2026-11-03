# Copyright 2026 Chanzo
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""The Gazelle targets of a repository built on this infrastructure."""

load("@gazelle//:def.bzl", "gazelle", "gazelle_test")

# Gazelle's options, the same for writing the BUILD files and for checking
# them. Gazelle leaves .proto files alone instead of writing proto rules for
# them: the repositories write their proto rules by hand.
_ARGS = ["-proto=disable_global"]

def gazelle_targets():
    """Defines the Gazelle targets of the calling package.

    `bazel run :gazelle` writes the BUILD files of the repository's Go code;
    `bazel test :gazelle_test` fails when they differ from what Gazelle
    would write. Call this from bazel/gazelle/BUILD.bazel, not from the root
    package: another repository may load from a consumer's root package
    while this infrastructure is only the consumer's development
    dependency, and there the load of this file would fail.

    Both targets, and the runners Gazelle defines for them, are manual, so
    that `bazel build //...` and `bazel test //...` neither build Gazelle
    nor fetch its Go dependencies; a repository's static analysis names the
    test. Gazelle tags the test no-cache and no-sandbox, so the test runs
    on every invocation, while the Gazelle binary it runs is cached. The
    test is also no-remote-exec: it finds the repository by following the
    link of MODULE.bazel in its runfiles, and on a remote executor that file
    is a copy, so the test would compare nothing.
    """
    gazelle(
        name = "gazelle",
        args = _ARGS,
        tags = ["manual"],
    )
    gazelle_test(
        name = "gazelle_test",
        args = _ARGS,
        workspace = "//:MODULE.bazel",
        tags = [
            "manual",
            "no-remote-exec",
        ],
    )
