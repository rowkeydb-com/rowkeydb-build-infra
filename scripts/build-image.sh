#!/usr/bin/env bash
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

# Builds recipe/Dockerfile's linux/amd64 image with a pinned builder and
# no build cache, so that two builds of one commit give the same digest.
#
#   scripts/build-image.sh oci <file>   write an OCI image layout archive
#   scripts/build-image.sh registry     push the image, untagged, to the
#                                       repository image.bzl names
#
# With IMAGE_LOAD=<tag>, the image is also loaded into the local Docker
# under that tag, for scripts/manifest.sh. With IMAGE_INPUTS=<URL>, the
# recipe reads its release inputs from that URL instead, to test it before
# the inputs release exists; the build argument then enters the image's
# history, so its digest is not the published recipe's.
#
# It prints the image's digest. The builder is buildx at a fixed release,
# checked against its SHA-256, and a new BuildKit container started from an
# image named by digest, with the overlayfs snapshotter; the container is
# removed afterwards, so that no build cache is read or kept.
# SOURCE_DATE_EPOCH is the time of the Ubuntu snapshot the recipe names.
# File times later than it are set to it, and earlier ones, which come from
# the pinned inputs, are kept; the files the recipe reads from this
# repository are copied first, so that their times are this build's. Layers
# are compressed with gzip at a fixed level, and no provenance or SBOM is
# attached. A push uses the registry credentials docker login stored in
# $DOCKER_CONFIG, or in ~/.docker when that is not set; only the
# credentials are taken from that configuration, since its other settings
# can name other plugin directories, and so another buildx. It needs
# docker, curl, sha256sum, GNU date and python3.

set -euo pipefail

readonly BUILDX_VERSION=v0.38.0
readonly BUILDX_SHA256=4fe4cc38adf48169132749b6ca22a990928db0118e3407584ee553723115d287
readonly BUILDKIT_IMAGE=moby/buildkit:v0.34.0@sha256:b059f8d7226d0b326bc871af489a5dddf65e36af4d20d14251b072974d9ee87c

case "${1:-} $#" in
    "oci 2" | "registry 1") ;;
    *)
        echo "usage: $0 oci <file> | registry" >&2
        exit 2
        ;;
esac
kind="$1"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
if [ "$kind" = oci ]; then
    target="$2"
else
    target="$(sed -n 's/^IMAGE_REPOSITORY = "\([^"]*\)"$/\1/p' "$REPO_DIR/image.bzl")"
    if [ -z "$target" ]; then
        echo "image.bzl names no IMAGE_REPOSITORY" >&2
        exit 1
    fi
fi
snapshot="$(sed -n 's/^ARG UBUNTU_SNAPSHOT=\([0-9]\{8\}T[0-9]\{6\}Z\)$/\1/p' "$REPO_DIR/recipe/Dockerfile")"
if [ -z "$snapshot" ]; then
    echo "recipe/Dockerfile names no UBUNTU_SNAPSHOT" >&2
    exit 1
fi
SOURCE_DATE_EPOCH="$(date -u -d "${snapshot:0:4}-${snapshot:4:2}-${snapshot:6:2}T${snapshot:9:2}:${snapshot:11:2}:${snapshot:13:2}Z" +%s)"
readonly SOURCE_DATE_EPOCH

# Settings buildx reads from the environment which would change the image
# or the builder: labels and information from git, a source policy, and
# buildx's own configuration directory.
unset BUILDX_CONFIG BUILDX_GIT_LABELS BUILDX_GIT_INFO BUILDX_GIT_CHECK_DIRTY \
    EXPERIMENTAL_BUILDKIT_SOURCE_POLICY

work="$(mktemp -d)"
builder="rowkeydb-build-infra-$$"
cleanup() {
    DOCKER_CONFIG="$work" docker buildx rm --force "$builder" > /dev/null 2>&1 || true
    rm -rf "${work:?}"
}
trap cleanup EXIT

mkdir -p "$work/cli-plugins" "$work/context"
cp -R "$REPO_DIR/recipe" "$REPO_DIR/.bazelversion" "$work/context/"
curl -fsSL --retry 3 -o "$work/cli-plugins/docker-buildx" \
    "https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-$BUILDX_VERSION.linux-amd64"
echo "$BUILDX_SHA256  $work/cli-plugins/docker-buildx" | sha256sum -c - > /dev/null
chmod +x "$work/cli-plugins/docker-buildx"
credentials="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
if [ -f "$credentials" ]; then
    python3 -I -c '
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
keys = ("auths", "credsStore", "credHelpers")
with open(sys.argv[2], "w") as f:
    json.dump({k: config[k] for k in keys if k in config}, f)
' "$credentials" "$work/config.json"
fi
export DOCKER_CONFIG="$work"

docker buildx create --name "$builder" --driver docker-container \
    --driver-opt "image=$BUILDKIT_IMAGE" \
    --buildkitd-flags '--oci-worker-snapshotter=overlayfs' \
    --bootstrap > /dev/null

exporter="rewrite-timestamp=true,oci-mediatypes=true,compression=gzip,compression-level=6,force-compression=true"
outputs=()
if [ "$kind" = oci ]; then
    outputs+=(--output "type=oci,dest=$target,$exporter")
else
    # Pushed by digest alone; a tag is given only to an accepted image.
    outputs+=(--output "type=image,name=$target,push=true,push-by-digest=true,$exporter")
fi
if [ -n "${IMAGE_LOAD:-}" ]; then
    outputs+=(--output "type=docker,name=$IMAGE_LOAD,$exporter")
fi
extra=()
if [ -n "${IMAGE_INPUTS:-}" ]; then
    extra+=(--build-arg "INPUTS=$IMAGE_INPUTS")
fi
docker buildx build --builder "$builder" \
    --platform linux/amd64 \
    --target msan \
    --no-cache \
    --provenance=false \
    --sbom=false \
    --build-arg "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH" \
    "${extra[@]}" \
    --metadata-file "$work/metadata.json" \
    "${outputs[@]}" \
    -f "$work/context/recipe/Dockerfile" \
    "$work/context" >&2
digest="$(sed -n 's/.*"containerimage.digest": *"\(sha256:[0-9a-f]*\)".*/\1/p' "$work/metadata.json")"
if [ -z "$digest" ]; then
    echo "the build reported no image digest" >&2
    exit 1
fi
echo "$digest"
