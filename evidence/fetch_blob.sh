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

# Downloads one file from BuildBuddy's cache by its digest and size, as
# find.py prints them, through the invocation which wrote it, and checks
# its SHA-256. The API key is read as fetch.sh reads it, and never printed.
#
# Usage: evidence/fetch_blob.sh <file> <invocation id> <digest> <size>

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <file> <invocation id> <digest> <size>" >&2
    exit 2
fi
file="$1"
id="$2"
digest="$3"
size="$4"
if [[ ! "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "not an invocation id: $id" >&2
    exit 2
fi
if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]] || [[ ! "$size" =~ ^[0-9]+$ ]]; then
    echo "not a digest and size: $digest $size" >&2
    exit 2
fi
key_file="${BUILDBUDDY_API_KEY_FILE:-$HOME/.config/buildbuddy/api-key}"
[ -r "$key_file" ] || { echo "cannot read $key_file" >&2; exit 1; }

printf 'x-buildbuddy-api-key: %s\n' "$(< "$key_file")" |
    curl -fsS -G -H @- -o "$file" \
        --data-urlencode "bytestream_url=bytestream://remote.buildbuddy.io/blobs/$digest/$size" \
        --data-urlencode "invocation_id=$id" \
        https://app.buildbuddy.io/file/download
echo "$digest  $file" | sha256sum -c --quiet
