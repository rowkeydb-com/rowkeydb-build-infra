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

# Downloads, for each BuildBuddy invocation named, its record and its
# compact execution log:
#
#   <directory>/<prefix><invocation id>.json  the record, with the build
#                                             events, among them the
#                                             canonical command line;
#   <directory>/<prefix><invocation id>.zst   the execution log, as Bazel
#                                             wrote it with
#                                             --execution_log_compact_file.
#
# The record is the one BuildBuddy's web interface reads (the RPC
# BuildBuddyService/GetInvocation), which holds the build events. An
# invocation without an execution log gets no .zst file, and a line on
# standard error says so.
#
# The API key is read from the file BUILDBUDDY_API_KEY_FILE names, by
# default ~/.config/buildbuddy/api-key. It reaches curl on standard input,
# so that it appears in no command line, and is never printed.
#
# Usage: evidence/fetch.sh <directory> <prefix> <invocation id>...

set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "usage: $0 <directory> <prefix> <invocation id>..." >&2
    exit 2
fi
dir="$1"
prefix="$2"
shift 2
key_file="${BUILDBUDDY_API_KEY_FILE:-$HOME/.config/buildbuddy/api-key}"
[ -r "$key_file" ] || { echo "cannot read $key_file" >&2; exit 1; }
mkdir -p "$dir"

header() {
    printf 'x-buildbuddy-api-key: %s\n' "$(< "$key_file")"
}

for id in "$@"; do
    if [[ ! "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo "not an invocation id: $id" >&2
        exit 2
    fi
    record="$dir/$prefix$id.json"
    header | curl -fsS -H @- -H 'Content-Type: application/json' \
        -d "{\"lookup\":{\"invocationId\":\"$id\"}}" -o "$record" \
        https://app.buildbuddy.io/rpc/BuildBuddyService/GetInvocation
    uri="$(jq -r '[.invocation[0].event[].buildEvent.buildToolLogs.log[]?
        | select(.name == "execution_log.binpb.zst") | .uri] | .[0] // empty' \
        "$record")"
    if [ -z "$uri" ]; then
        echo "$id: no execution log" >&2
        continue
    fi
    header | curl -fsS -G -H @- -o "$dir/$prefix$id.zst" \
        --data-urlencode "bytestream_url=$uri" \
        --data-urlencode "invocation_id=$id" \
        https://app.buildbuddy.io/file/download
done
