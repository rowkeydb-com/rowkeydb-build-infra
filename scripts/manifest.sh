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

# Writes the manifest of an image to standard output, in sections:
#
#   config    the image's configuration (environment, working directory,
#             user, entry point and command), from docker image inspect;
#   packages  the version of every installed Debian package;
#   files     the type, mode, owner and, for a link, the target of every
#             file, sorted by path;
#   xattrs    every extended attribute of every file;
#   contents  the SHA-256 of every regular file, sorted by path;
#   tools     the version each tool installed outside Debian's packages
#             reports, and every package of the pip environment.
#
# Two images whose manifests are equal hold the same software and the same
# files under the same configuration.
#
# The image must already be on this machine and provide bash, the GNU
# find, sort and sha256sum, dpkg-query and python3. It is run as root with
# no network and never pulled. The files Docker provides to every container
# (/.dockerenv, /etc/hostname, /etc/hosts and /etc/resolv.conf) are left
# out, since they belong to the container and not to the image. The tools
# run last, with their home directory outside the image's files, because
# running one can write files (go records counts under ~/.config/go); a
# tool missing from an image is reported as missing.
#
# Usage: scripts/manifest.sh <image reference>

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <image reference>" >&2
    exit 2
fi

echo "# config"
docker image inspect --format '{{json .Config}}' "$1" |
    jq -S '{Env, WorkingDir, User, Entrypoint, Cmd, Shell}'

# shellcheck disable=SC2016 # The script runs in the image's shell.
docker run --rm --network none --pull never --user 0:0 \
    --entrypoint /bin/bash "$1" -c '
set -euo pipefail
export LC_ALL=C
# sort keeps its temporary files under /dev, which is not listed, so that
# they do not appear in the listing of /tmp.
export TMPDIR=/dev/shm
list() {
    find / -xdev \
        \( -path /proc -o -path /sys -o -path /dev \
           -o -path /.dockerenv -o -path /etc/hostname -o -path /etc/hosts \
           -o -path /etc/resolv.conf \) -prune -o "$@"
}
version() {
    local name="$1"; shift
    if command -v "$1" > /dev/null 2>&1; then
        printf "%s: %s\n" "$name" "$("$@" 2>&1 | head -1)"
    else
        printf "%s: missing\n" "$name"
    fi
}
echo "# packages"
dpkg-query -W -f="\${Package} \${Version} \${Architecture}\n" | sort
echo "# files"
list -printf "%y %m %u:%g %p -> %l\n" | sort -k4
echo "# xattrs"
list -print0 | python3 -c "
import os, sys
for p in sorted(sys.stdin.buffer.read().split(b\"\\0\")):
    if not p:
        continue
    try:
        names = os.listxattr(p, follow_symlinks=False)
    except OSError:
        continue
    for n in sorted(names):
        v = os.getxattr(p, n, follow_symlinks=False)
        print(p.decode(errors=\"replace\"), n, v.hex())
"
echo "# contents"
list -type f -print0 | sort -z | xargs -0 -r sha256sum
echo "# tools"
mkdir /dev/shm/home
export HOME=/dev/shm/home
# Bazelisk reports its own version only after resolving a Bazel version,
# which needs the network. The contents section identifies its binary;
# the Bazel versions it holds are listed here.
if [ -d "${BAZELISK_HOME:-/nonexistent}/downloads/metadata" ]; then
    find "$BAZELISK_HOME/downloads/metadata" -mindepth 2 -maxdepth 2 \
        -printf "bazelisk holds: %P\n" | sort
else
    printf "bazelisk holds: nothing\n"
fi
version go go version
version golangci-lint golangci-lint --version
version typos typos --version
version terraform terraform version
version tflint tflint --version
version trivy trivy --version
# gcloud is not on the PATH, and running it writes under its home.
if [ -f /usr/local/google-cloud-sdk/VERSION ]; then
    printf "gcloud: %s\n" "$(cat /usr/local/google-cloud-sdk/VERSION)"
else
    printf "gcloud: missing\n"
fi
if [ -x /opt/ansible-env/bin/pip ]; then
    /opt/ansible-env/bin/pip freeze --all 2>/dev/null | sort | sed "s/^/pip: /"
fi
'
