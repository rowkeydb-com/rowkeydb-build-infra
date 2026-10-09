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
The copies of the digest elsewhere (bazelrc/shared.bazelrc and each
consumer's workflows and scripts) are compared with it by scripts/check.sh.
"""

IMAGE_REPOSITORY = "ghcr.io/rowkeydb-com/rowkeydb-build-infra"

# The linux/amd64 image of index
# sha256:9716b9a89c625b3d446872e2c17149d941ecbb41e6f9d152484bb01b0eeb3ef0,
# which ghcr.io/chanzo-dev/rowkeydb-ci serves for rowkeydb c8807f6b's image
# tag and for `latest`. rowkeydb's self-hosted runners held, under that
# image tag, the other build of the same recipe,
# sha256:4f804cd9db4a8924bfcd27dc4b6b98011e514657041758ecf67f2ed580cf09a1,
# which differs only in files no build reads (manifests/README.md). The
# image was copied unchanged, without its attestation, and is tagged
# v0.1.0. recipe/Dockerfile.ci is its recipe.
IMAGE_DIGEST_AMD64 = "sha256:a1c8fa1e1a3b49e61cfcd3240e18d4a1288b6375fb95e025c3d31f7f37b0145e"

# The value of the `container-image` execution property.
IMAGE_AMD64 = "docker://" + IMAGE_REPOSITORY + "@" + IMAGE_DIGEST_AMD64
