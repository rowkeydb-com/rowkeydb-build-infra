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

# Checks that every copy of what this repository holds agrees with it.
#
#   scripts/check.sh --self
#       In this repository: image.bzl names a repository and a digest,
#       bazelrc/shared.bazelrc names that image, and every image reference
#       in this repository's text files, tracked or not ignored, is that
#       image (Markdown, image.bzl and this script apart).
#
#   scripts/check.sh <consumer directory>
#       In a consumer, against the commit of this repository named in the
#       first line of its copy, bazel/build_infra/shared.bazelrc:
#       - the commit is the commit of a release of this repository;
#       - the copy, below its two header lines, equals bazelrc/shared.bazelrc
#         at that commit, and the second line holds the SHA-256 of those
#         lines;
#       - .bazelversion equals this repository's;
#       - MODULE.bazel overrides rowkeydb_build_infra with that release's
#         archive, the strip prefix it holds and the integrity of the asset
#         as published (the asset is downloaded);
#       - MODULE.bazel.lock selects each of the four shared modules the
#         consumer's graph contains at the approved version, MODULE.bazel
#         declares none of them at another version, and overrides none;
#       - every file listed in bazel/build_infra/image_references holds the
#         approved image reference, and every image reference in the
#         consumer's text files, tracked or not ignored, Markdown apart, is
#         the approved one.
#
# It changes nothing. It prints each failure and exits 1 if there is any.
# It needs git, curl, jq, python3 and sha256sum.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INFRA_DIR
readonly COPY_PATH="bazel/build_infra/shared.bazelrc"
readonly REFERENCES_PATH="bazel/build_infra/image_references"
readonly SHARED_MODULES=(abseil-cpp protobuf grpc opentelemetry-cpp)
readonly RELEASES_URL="https://github.com/rowkeydb-com/rowkeydb-build-infra/releases/download"

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

# The value of a string constant assigned at the start of a line of the
# given text of image.bzl.
bzl_string() {
    sed -n "s/^$1 = \"\\([^\"]*\\)\"\$/\\1/p"
}

# Image references in text: the value after docker:// or container-image=,
# and anything naming a repository in ghcr.io, host in any case. One per
# line, with any docker:// or container-image= prefix removed.
references_in() {
    grep -a -o -i -E \
        'container-image=[^[:space:]"'"'"'`,)]+|docker://[^[:space:]"'"'"'`,)]+|ghcr\.io/[A-Za-z0-9._/-]+([@:][A-Za-z0-9:._-]+)?' "$@" |
        sed -E 's#^container-image=##I; s#^docker://##I' || true
}

# Fails for each reference read on stdin which is not the approved one,
# spelt exactly as approved: a host in another case names the same
# registry, but the approved reference has one spelling.
check_references() {
    local approved="$1" where="$2" reference
    while IFS= read -r reference; do
        if [ "$reference" != "$approved" ]; then
            fail "$where: image reference $reference is not $approved"
        fi
    done
}

# Fails for each image reference which is not the approved one in the text
# files git tracks, or would add, in the given directory, file by file,
# Markdown and the files the further arguments exclude apart; git grep -I
# passes over binary files.
scan_references() {
    local dir="$1" approved="$2" list status=0 file
    shift 2
    list="$(mktemp)"
    git -C "$dir" grep -z -l -I --untracked -i -E \
        'container-image=|docker://|ghcr\.io/' -- ':!*.md' "$@" > "$list" ||
        status=$?
    # git grep exits 1 when nothing matches and above 1 when it fails.
    if [ "$status" -gt 1 ]; then
        fail "git grep could not read $dir"
    fi
    while IFS= read -r -d '' file; do
        check_references "$approved" "$file" < <(references_in "$dir/$file")
    done < "$list"
    rm -f "$list"
}

check_self() {
    local repository digest
    repository="$(bzl_string IMAGE_REPOSITORY < "$INFRA_DIR/image.bzl")"
    digest="$(bzl_string IMAGE_DIGEST_AMD64 < "$INFRA_DIR/image.bzl")"
    if [[ ! "$repository" =~ ^ghcr\.io/[a-z0-9._/-]+$ ]]; then
        fail "image.bzl: IMAGE_REPOSITORY is missing or malformed"
        return
    fi
    if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        fail "image.bzl: IMAGE_DIGEST_AMD64 is missing or malformed"
        return
    fi
    grep -q '^IMAGE_AMD64 = "docker://" + IMAGE_REPOSITORY + "@" + IMAGE_DIGEST_AMD64$' \
        "$INFRA_DIR/image.bzl" ||
        fail "image.bzl: IMAGE_AMD64 is not built from IMAGE_REPOSITORY and IMAGE_DIGEST_AMD64"
    local count
    count="$(references_in "$INFRA_DIR/bazelrc/shared.bazelrc" | wc -l)"
    [ "$count" -ge 1 ] || fail "bazelrc/shared.bazelrc names no image"
    # Read through process substitution, not a pipe, so that fail() counts
    # in this shell.
    check_references "$repository@$digest" bazelrc/shared.bazelrc \
        < <(references_in "$INFRA_DIR/bazelrc/shared.bazelrc")
    # image.bzl holds the repository alone, and this script holds the
    # patterns of a reference.
    scan_references "$INFRA_DIR" "$repository@$digest" \
        ':!image.bzl' ':!scripts/check.sh' ':!bazelrc/shared.bazelrc'
}

# Prints the archive_override block naming rowkeydb_build_infra, with
# comments removed.
infra_override() {
    sed 's/#.*$//' "$1" | awk '
        /^archive_override\(/ { block = ""; inside = 1 }
        inside { block = block $0 "\n" }
        inside && /^\)/ {
            inside = 0
            if (block ~ /module_name *= *"rowkeydb_build_infra"/) printf "%s", block
        }'
}

check_modules() {
    local dir="$1" commit="$2"
    local module="$dir/MODULE.bazel" lock="$dir/MODULE.bazel.lock"
    # Declarations and overrides, read from the file with its comments
    # removed, so that a call written over several lines is read as one.
    local parsed
    parsed="$(python3 - "$module" <<'EOF'
import re, sys
text = re.sub(r"#[^\n]*", "", open(sys.argv[1]).read())
for m in re.finditer(r"\b(bazel_dep|[a-z_]*_override)\s*\(([^()]*)\)", text):
    kind, args = m.group(1), m.group(2)
    kw = dict(re.findall(r"(\w+)\s*=\s*\"([^\"]*)\"", args))
    name = kw.get("name") if kind == "bazel_dep" else kw.get("module_name")
    print(kind, name or "-", kw.get("version", "-"))
EOF
)"
    local name approved declared
    for name in "${SHARED_MODULES[@]}"; do
        approved="$(git -C "$INFRA_DIR" show "$commit:MODULE.bazel" |
            python3 -c '
import re, sys
text = re.sub(r"#[^\n]*", "", sys.stdin.read())
for m in re.finditer(r"bazel_dep\s*\(([^()]*)\)", text):
    kw = dict(re.findall(r"(\w+)\s*=\s*\"([^\"]*)\"", m.group(1)))
    if kw.get("name") == sys.argv[1]:
        print(kw.get("version", ""))
' "$name")"
        if [ -z "$approved" ]; then
            fail "rowkeydb-build-infra at $commit approves no version of $name"
            continue
        fi
        while read -r kind modname version; do
            [ "$modname" = "$name" ] || continue
            if [ "$kind" = "bazel_dep" ]; then
                [ "$version" = "$approved" ] ||
                    fail "MODULE.bazel declares $name $version; $commit approves $approved"
            else
                fail "MODULE.bazel overrides $name ($kind); the shared modules may not be overridden"
            fi
        done <<< "$parsed"
        if [ ! -f "$lock" ]; then
            continue
        fi
        declared="$(jq -r '.registryFileHashes | keys[]' "$lock" |
            sed -n "s#.*/modules/$name/\\([^/]*\\)/source\\.json\$#\\1#p" | sort -u)"
        if [ -n "$declared" ] && [ "$declared" != "$approved" ]; then
            fail "MODULE.bazel.lock selects $name $(echo "$declared" | tr '\n' ' '); $commit approves $approved"
        fi
    done
    [ -f "$lock" ] || fail "MODULE.bazel.lock is missing"
}

check_consumer() {
    local dir="$1"
    local copy="$dir/$COPY_PATH"
    if [ ! -f "$copy" ]; then
        fail "$copy is missing"
        return
    fi

    local commit
    commit="$(sed -n '1s/^# Copied from rowkeydb-com\/rowkeydb-build-infra at \([0-9a-f]\{40\}\)\.$/\1/p' "$copy")"
    if [ -z "$commit" ]; then
        fail "$COPY_PATH line 1 does not name a commit of rowkeydb-build-infra"
        return
    fi
    if ! git -C "$INFRA_DIR" cat-file -e "$commit^{commit}" 2>/dev/null; then
        fail "commit $commit is not in $INFRA_DIR"
        return
    fi
    local tag
    tag="$(git -C "$INFRA_DIR" tag --points-at "$commit" | head -1)"
    if [ -z "$tag" ]; then
        fail "commit $commit is not the commit of a release (no tag points at it)"
        return
    fi
    at() { git -C "$INFRA_DIR" show "$commit:$1"; }

    local recorded actual
    recorded="$(sed -n '2s/^# SHA-256 of the lines below: \([0-9a-f]\{64\}\)\.$/\1/p' "$copy")"
    actual="$(tail -n +3 "$copy" | sha256sum | cut -d' ' -f1)"
    [ "$recorded" = "$actual" ] ||
        fail "$COPY_PATH line 2 records ${recorded:-no checksum}, its lines hash to $actual"
    if ! diff -q <(tail -n +3 "$copy") <(at bazelrc/shared.bazelrc) > /dev/null; then
        fail "$COPY_PATH differs from bazelrc/shared.bazelrc at $commit"
    fi

    if ! diff -q "$dir/.bazelversion" <(at .bazelversion) > /dev/null; then
        fail ".bazelversion differs from rowkeydb-build-infra's at $commit"
    fi

    local block asset url prefix integrity published
    block="$(infra_override "$dir/MODULE.bazel")"
    asset="rowkeydb-build-infra-$commit.tar.gz"
    url="$RELEASES_URL/$tag/$asset"
    prefix="$(sed -n 's/^ *strip_prefix *= *"\([^"]*\)".*/\1/p' <<< "$block")"
    integrity="$(sed -n 's/^ *integrity *= *"\([^"]*\)".*/\1/p' <<< "$block")"
    if [ "$(grep -o 'https://[^"]*' <<< "$block")" != "$url" ]; then
        fail "MODULE.bazel does not override rowkeydb_build_infra with $url alone"
    fi
    [ "$prefix" = "rowkeydb-build-infra-$commit" ] ||
        fail "MODULE.bazel's strip_prefix for rowkeydb_build_infra is not rowkeydb-build-infra-$commit"
    if published="sha256-$(curl -fsSL "$url" | openssl dgst -sha256 -binary | base64 -w0)" &&
        [ "$published" != "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" ]; then
        [ "$integrity" = "$published" ] ||
            fail "MODULE.bazel's integrity $integrity is not the published asset's $published"
    else
        fail "could not download $url to check its integrity"
    fi

    check_modules "$dir" "$commit"

    local repository digest approved path
    repository="$(at image.bzl | bzl_string IMAGE_REPOSITORY)"
    digest="$(at image.bzl | bzl_string IMAGE_DIGEST_AMD64)"
    approved="$repository@$digest"
    if [ ! -f "$dir/$REFERENCES_PATH" ]; then
        fail "$REFERENCES_PATH is missing"
    else
        while IFS= read -r path; do
            if [ -z "$path" ] || [ "${path:0:1}" = "#" ]; then
                continue
            elif [ ! -f "$dir/$path" ]; then
                fail "$path, listed in $REFERENCES_PATH, is missing"
            elif ! grep -a -q -F "$approved" "$dir/$path"; then
                fail "$path, listed in $REFERENCES_PATH, does not name $approved"
            fi
        done < "$dir/$REFERENCES_PATH"
    fi
    scan_references "$dir" "$approved"
}

if [ "$#" -ne 1 ]; then
    echo "usage: $0 --self | <consumer directory>" >&2
    exit 2
fi
if [ "$1" = "--self" ]; then
    check_self
else
    check_consumer "$1"
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed." >&2
    exit 1
fi
echo "All checks passed."
