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

"""The image every build of the consumers runs in.

This is the authoritative copy of the image's digest. Each architecture's
image is named by its own digest, never by the index which holds them, so
that adding an architecture changes no other architecture's cache keys.
The copies of the digest elsewhere (bazelrc/shared.bazelrc, this
repository's .github/workflows/check.yml, and each consumer's workflows
and scripts) are compared with it by scripts/check.sh.
"""

IMAGE_REPOSITORY = "ghcr.io/rowkeydb-com/rowkeydb-build-infra"

# The linux/amd64 image which scripts/build-image.sh builds from
# recipe/Dockerfile, tagged v0.2.0. Builds without any build cache, on
# different machines and on different days, gave this digest. Its manifest
# differs from that of the image of the earlier releases, tagged v0.1.0,
# only as manifests/README.md states.
IMAGE_DIGEST_AMD64 = "sha256:07ce31e8be9d63aadccae2a36dfcbb30c2250ef8e7279366e661536f0b14cd3e"

# The value of the `container-image` execution property.
IMAGE_AMD64 = "docker://" + IMAGE_REPOSITORY + "@" + IMAGE_DIGEST_AMD64
