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
# Run it from the newest commit of this repository's main. It reads the
# commit a consumer names from the clone it runs in, so it checks the
# consumers of earlier releases as well.
#
#   scripts/check.sh --self
#       In this repository: image.bzl names a repository and a digest,
#       bazelrc/shared.bazelrc names that image, and every image reference
#       in this repository's text files, tracked or not ignored, is that
#       image. Markdown is not read, and neither are image.bzl and the
#       shared file, which are checked on their own, nor this script, which
#       holds the patterns of a reference.
#
#   scripts/check.sh <consumer directory>
#       In a consumer, against the commit of this repository named in the
#       first line of its copy, bazel/build_infra/shared.bazelrc:
#       - the commit is the commit of a release of this repository;
#       - the copy, below its two header lines, equals bazelrc/shared.bazelrc
#         at that commit, and the second line holds the SHA-256 of those
#         lines;
#       - .bazelrc imports the copy with import, once;
#       - .bazelversion equals this repository's;
#       - MODULE.bazel depends on rowkeydb_build_infra at that commit's
#         version, and overrides it with one archive_override that sets
#         only the URL of the asset of a release whose tag points at the
#         commit, the strip prefix and the integrity of the asset as
#         published; the asset is downloaded and must hold that commit's
#         files under that prefix;
#       - MODULE.bazel, read as Starlark, passes every argument of module,
#         bazel_dep, include and the overrides as a literal, declares none
#         of the four shared modules at another version, overrides none,
#         and includes no other file; MODULE.bazel.lock selects from the
#         registry, at the approved version, each of the four that
#         MODULE.bazel declares or the consumer's graph contains; and no
#         text file, Markdown and the copy apart, holds an option that
#         replaces a module or its registry or turns modules off
#         (--override_module, --override_repository, --registry,
#         --vendor_dir, --enable_bzlmod, --noenable_bzlmod);
#       - every file listed in bazel/build_infra/image_references holds the
#         approved image reference, and every image reference in the
#         consumer's text files, tracked or not ignored, Markdown apart, is
#         the approved one.
#
# An image reference is what follows container-image=, docker:// or
# ghcr.io/, up to white space, a quotation mark or a character that closes
# or separates an expression; a reference built from a variable or an
# expression is therefore not the approved one. Other spellings, such as a
# Dockerfile's FROM line, are not read.
#
# Repositories a consumer fetches itself, with use_repo_rule or a module
# extension, are not read either: a consumer that fetches a shared module
# that way, under another name, is not refused.
#
# It changes nothing. It prints each failure and exits 1 if there is any.
# It needs git, curl, python3, openssl, base64, sha256sum, diff, sed, grep
# and mktemp.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 --self | <consumer directory>" >&2
    exit 2
fi

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INFRA_DIR
readonly COPY_PATH="bazel/build_infra/shared.bazelrc"
readonly REFERENCES_PATH="bazel/build_infra/image_references"
readonly SHARED_MODULES=(abseil-cpp protobuf grpc opentelemetry-cpp)
readonly RELEASES_URL="https://github.com/rowkeydb-com/rowkeydb-build-infra/releases/download"
# Options that replace a module or its registry outside MODULE.bazel, or
# turn modules off.
readonly MODULE_OPTIONS='--override_module|--override_repository|--registry|--vendor_dir|--(no)?enable_bzlmod'

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

# A check that cannot run must not pass, so every tool is required first.
for tool in git curl python3 openssl base64 sha256sum diff sed grep \
    mktemp; do
    if ! command -v "$tool" > /dev/null; then
        fail "$tool is not installed"
    fi
done
if [ "$failures" -gt 0 ]; then
    exit 1
fi

TMP_DIR="$(mktemp -d)"
readonly TMP_DIR
trap 'rm -rf "$TMP_DIR"' EXIT

# The value of a string constant assigned at the start of a line of the
# given text of image.bzl.
bzl_string() {
    sed -n "s/^$1 = \"\\([^\"]*\\)\"\$/\\1/p"
}

# The image references in a file, one per line, with any container-image=
# or docker:// prefix removed. A reference may be empty, when a quotation
# mark or an expression follows the prefix.
references_in() {
    local end=']}[:space:]"'"'"'`,);<>|'
    grep -a -o -i -E \
        "container-image=[^$end]*|docker://[^$end]*|ghcr\\.io/[^$end]*" "$1" |
        sed -E 's#^container-image=##I; s#^docker://##I' || true
}

# Fails for each reference read on stdin which is not the approved one,
# spelt exactly as approved: a host in another case names the same
# registry, but the approved reference has one spelling.
check_references() {
    local approved="$1" where="$2" reference
    while IFS= read -r reference; do
        if [ "$reference" != "$approved" ]; then
            fail "$where: image reference ${reference:-(none, an expression follows)} is not $approved"
        fi
    done
}

# Fails when git grep, whose exit status and standard error are given,
# could not read every file of the directory: it exits 1 when nothing
# matches and above 1 when it fails, and reports a file it cannot read on
# standard error while it goes on.
git_grep_failed() {
    local dir="$1" status="$2" errors="$3"
    if [ "$status" -gt 1 ] || [ -s "$errors" ]; then
        fail "git grep could not read every file of $dir: $(head -n 1 "$errors")"
        return 0
    fi
    return 1
}

# Fails for each image reference which is not the approved one in the text
# files git tracks, or would add, in the given directory, file by file,
# Markdown and the files the further arguments exclude apart; git grep -I
# passes over binary files.
scan_references() {
    local dir="$1" approved="$2" status=0 file
    local list="$TMP_DIR/references" errors="$TMP_DIR/errors"
    shift 2
    git -C "$dir" grep -z -l -I --untracked -i -E \
        'container-image=|docker://|ghcr\.io/' -- ':!*.md' "$@" \
        > "$list" 2> "$errors" || status=$?
    if git_grep_failed "$dir" "$status" "$errors"; then
        return
    fi
    while IFS= read -r -d '' file; do
        if [ ! -r "$dir/$file" ]; then
            fail "$file cannot be read"
        else
            check_references "$approved" "$file" < <(references_in "$dir/$file")
        fi
    done < "$list"
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
    # The check workflow must run in the image, not merely name no other.
    grep -q -x -F "      image: $repository@$digest" \
        "$INFRA_DIR/.github/workflows/check.yml" ||
        fail ".github/workflows/check.yml does not run in $repository@$digest"
    scan_references "$INFRA_DIR" "$repository@$digest" \
        ':!image.bzl' ':!scripts/check.sh' ':!bazelrc/shared.bazelrc'
}

# Reads the consumer's MODULE.bazel as Starlark and compares it, and its
# MODULE.bazel.lock, with the MODULE.bazel of this repository at the
# commit. Fails once for each line the comparison prints, and writes the
# URLs, strip prefix and integrity of the override of rowkeydb_build_infra,
# one to a line, to $TMP_DIR/override.
check_modules() {
    local dir="$1" commit="$2" out line
    local lock="$dir/MODULE.bazel.lock"
    [ -f "$lock" ] || fail "MODULE.bazel.lock is missing"
    if ! out="$(python3 -I - "$dir/MODULE.bazel" "$lock" \
        <(git -C "$INFRA_DIR" show "$commit:MODULE.bazel") "$commit" \
        "$TMP_DIR/override" "${SHARED_MODULES[@]}" <<'EOF'
import ast
import json
import os
import re
import sys

module_path, lock_path, infra_path, commit, override_path = sys.argv[1:6]
shared = sys.argv[6:]
FUNCTIONS = re.compile(r"^(module|bazel_dep|include|[a-z_]*_override)$")
OVERRIDE_KEYS = ["integrity", "module_name", "strip_prefix", "urls"]


def calls(path, label):
    """Each call of module, bazel_dep, include or an override in a module
    file, as (function, keyword arguments). Prints a failure for anything
    whose arguments cannot be read: a positional argument, **, a value that
    is not a literal, or one of these functions named other than in a
    call."""
    tree = ast.parse(open(path).read(), label)
    found, called = [], set()
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and FUNCTIONS.match(node.func.id)):
            continue
        called.add(id(node.func))
        kwargs, readable = {}, not node.args
        for keyword in node.keywords:
            try:
                if keyword.arg is None:
                    raise ValueError("**")
                kwargs[keyword.arg] = ast.literal_eval(keyword.value)
            except (ValueError, TypeError, SyntaxError):
                readable = False
        if not readable:
            print(f"{label} line {node.lineno}: {node.func.id} has an "
                  "argument this check cannot read; write each as a name "
                  "and a literal")
        found.append((node.func.id, kwargs))
    for node in ast.walk(tree):
        if (isinstance(node, ast.Name) and FUNCTIONS.match(node.id)
                and id(node) not in called):
            print(f"{label} line {node.lineno}: {node.id} is named other "
                  "than in a call")
    return found


def main():
    try:
        consumer = calls(module_path, "MODULE.bazel")
        infra = calls(infra_path, f"MODULE.bazel at {commit}")
    except (OSError, SyntaxError, ValueError) as e:
        print(f"a MODULE.bazel cannot be read as Starlark: {e}")
        return

    if any(kind == "include" for kind, _ in consumer):
        print("MODULE.bazel includes another file, which this check does "
              "not read")

    own = [kw.get("version") for kind, kw in infra if kind == "module"]
    mine = [kw.get("version") for kind, kw in consumer
            if kind == "bazel_dep" and kw.get("name") == "rowkeydb_build_infra"]
    if mine != own:
        print(f"MODULE.bazel depends on rowkeydb_build_infra {mine}; "
              f"{commit} is version {own}")
    overrides = [(kind, kw) for kind, kw in consumer
                 if kind.endswith("_override")
                 and kw.get("module_name") == "rowkeydb_build_infra"]
    values = {}
    if [kind for kind, _ in overrides] != ["archive_override"]:
        print("MODULE.bazel overrides rowkeydb_build_infra with "
              f"{[kind for kind, _ in overrides]}; it must use one "
              "archive_override")
    else:
        values = overrides[0][1]
        if sorted(values) != OVERRIDE_KEYS:
            print("MODULE.bazel's archive_override of rowkeydb_build_infra "
                  f"sets {sorted(values)}; it must set "
                  f"{', '.join(OVERRIDE_KEYS)} and nothing else")
    urls = values.get("urls")
    with open(override_path, "w") as out:
        out.write(" ".join(urls) if isinstance(urls, list) else "")
        out.write(f"\n{values.get('strip_prefix', '')}\n")
        out.write(f"{values.get('integrity', '')}\n")

    selected = None
    if os.path.exists(lock_path):
        try:
            selected = list(json.load(open(lock_path))["registryFileHashes"])
        except (OSError, ValueError, KeyError, TypeError) as e:
            print(f"MODULE.bazel.lock cannot be read: {e!r}")

    for name in shared:
        approved = [kw.get("version") for kind, kw in infra
                    if kind == "bazel_dep" and kw.get("name") == name]
        if len(approved) != 1:
            print(f"rowkeydb-build-infra at {commit} approves no single "
                  f"version of {name}")
            continue
        approved = approved[0]
        declared = False
        for kind, kw in consumer:
            if kind == "bazel_dep" and kw.get("name") == name:
                declared = True
                if kw.get("version") != approved:
                    print(f"MODULE.bazel declares {name} "
                          f"{kw.get('version')}; {commit} approves "
                          f"{approved}")
            elif kind.endswith("_override") and kw.get("module_name") == name:
                print(f"MODULE.bazel overrides {name} ({kind}); the shared "
                      "modules may not be overridden")
        if selected is None:
            continue
        # The lock file records the source.json of each module version
        # taken from a registry, so one entry is the version selected, and
        # none means the module is absent or comes from elsewhere.
        found = sorted({m.group(1) for url in selected
                        for m in [re.search(r"/modules/" + re.escape(name) +
                                            r"/([^/]+)/source\.json$", url)]
                        if m})
        if (declared or found) and found != [approved]:
            print(f"MODULE.bazel.lock selects {name} "
                  f"{' '.join(found) or 'from no registry'}; "
                  f"{commit} approves {approved}")


main()
EOF
)"; then
        fail "the module check could not run"
    fi
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            fail "$line"
        fi
    done <<< "$out"
}

# Fails unless the release asset holds the commit's files, with their modes
# and contents, under the strip prefix, and nothing else.
check_archive() {
    local asset="$1" commit="$2" out line
    if ! out="$(python3 -I - "$asset" "rowkeydb-build-infra-$commit" \
        <(git -C "$INFRA_DIR" ls-tree -r -z --full-tree "$commit") <<'EOF'
import hashlib
import sys
import tarfile

asset, prefix, tree = sys.argv[1:4]
expected = {}
for entry in open(tree, "rb").read().split(b"\0"):
    if entry:
        meta, path = entry.split(b"\t", 1)
        mode, _, blob = meta.split()
        expected[path.decode()] = (mode.decode(), blob.decode())
found = {}
with tarfile.open(asset, "r:gz") as archive:
    for member in archive:
        if member.isdir():
            continue
        if not member.name.startswith(prefix + "/"):
            print(f"the asset holds {member.name}, outside {prefix}/")
            continue
        if member.issym():
            data, mode = member.linkname.encode(), "120000"
        elif member.isfile():
            data = archive.extractfile(member).read()
            mode = "100755" if member.mode & 0o111 else "100644"
        else:
            print(f"the asset holds {member.name}, neither a file nor a link")
            continue
        blob = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
        found[member.name[len(prefix) + 1:]] = (mode, blob)
for path in sorted(set(expected) | set(found)):
    if expected.get(path) != found.get(path):
        print(f"the asset's {path} differs from the commit's")
EOF
)"; then
        fail "the release asset cannot be read as a gzip tar archive"
        return
    fi
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            fail "$line"
        fi
    done <<< "$out"
}

# Fails for each line of the consumer's text files, Markdown and the copy
# apart, which holds an option that replaces a module or its registry
# outside MODULE.bazel, where check_modules cannot see it, or turns modules
# off.
check_module_options() {
    local dir="$1" status=0 out line errors="$TMP_DIR/errors"
    out="$(git -C "$dir" grep -n -I --untracked -E -e "$MODULE_OPTIONS" \
        -- ':!*.md' ":!$COPY_PATH" 2> "$errors")" || status=$?
    if git_grep_failed "$dir" "$status" "$errors"; then
        return
    fi
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            fail "$line: replaces a module or its registry, or turns modules off"
        fi
    done <<< "$out"
}

check_consumer() {
    local dir="$1"
    local copy="$dir/$COPY_PATH"
    if [ ! -f "$copy" ] || [ ! -r "$copy" ]; then
        fail "$copy is missing or cannot be read"
        return
    fi

    local commit git_error
    commit="$(sed -n '1s/^# Copied from rowkeydb-com\/rowkeydb-build-infra at \([0-9a-f]\{40\}\)\.$/\1/p' "$copy")"
    if [ -z "$commit" ]; then
        fail "$COPY_PATH line 1 does not name a commit of rowkeydb-build-infra"
        return
    fi
    if ! git_error="$(git -C "$INFRA_DIR" rev-parse --git-dir 2>&1 > /dev/null)"; then
        fail "git cannot read $INFRA_DIR: ${git_error%%$'\n'*}"
        return
    fi
    if ! git -C "$INFRA_DIR" cat-file -e "$commit^{commit}" 2>/dev/null; then
        fail "commit $commit is not in $INFRA_DIR"
        return
    fi
    if [ -z "$(git -C "$INFRA_DIR" tag --points-at "$commit")" ]; then
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

    # Bazel skips a missing file named by try-import without an error.
    local imports
    imports="$(grep -c -x -F "import %workspace%/$COPY_PATH" "$dir/.bazelrc" || true)"
    [ "$imports" = 1 ] ||
        fail ".bazelrc does not import $COPY_PATH once, with import"
    if grep -q -E "^[[:space:]]*try-import[[:space:]]+%workspace%/$COPY_PATH" "$dir/.bazelrc"; then
        fail ".bazelrc names $COPY_PATH with try-import"
    fi

    if ! diff -q "$dir/.bazelversion" <(at .bazelversion) > /dev/null; then
        fail ".bazelversion differs from rowkeydb-build-infra's at $commit"
    fi

    check_modules "$dir" "$commit"

    local urls="" prefix="" integrity="" tag asset url published
    if [ -f "$TMP_DIR/override" ]; then
        { IFS= read -r urls; IFS= read -r prefix; IFS= read -r integrity; } \
            < "$TMP_DIR/override" || true
    fi
    asset="rowkeydb-build-infra-$commit.tar.gz"
    tag="$(sed -n "s#^$RELEASES_URL/\\([^/ ]*\\)/$asset\$#\\1#p" <<< "$urls")"
    url="$RELEASES_URL/$tag/$asset"
    [ "$prefix" = "rowkeydb-build-infra-$commit" ] ||
        fail "MODULE.bazel's strip_prefix for rowkeydb_build_infra is not rowkeydb-build-infra-$commit"
    if [ -z "$tag" ] || [ "$urls" != "$url" ]; then
        fail "MODULE.bazel does not override rowkeydb_build_infra with the URL of a release's $asset alone"
    elif [ "$(git -C "$INFRA_DIR" rev-parse -q --verify "refs/tags/$tag^{commit}")" != "$commit" ]; then
        fail "MODULE.bazel names the release $tag, whose tag does not point at $commit"
    elif ! curl -fsSL --max-time 300 --retry 3 -o "$TMP_DIR/asset" "$url"; then
        fail "could not download $url"
    else
        published="sha256-$(openssl dgst -sha256 -binary "$TMP_DIR/asset" | base64 -w0)"
        [ "$integrity" = "$published" ] ||
            fail "MODULE.bazel's integrity $integrity is not the published asset's $published"
        check_archive "$TMP_DIR/asset" "$commit"
    fi

    check_module_options "$dir"

    local repository digest approved path
    repository="$(at image.bzl | bzl_string IMAGE_REPOSITORY)"
    digest="$(at image.bzl | bzl_string IMAGE_DIGEST_AMD64)"
    approved="$repository@$digest"
    if [ ! -f "$dir/$REFERENCES_PATH" ] || [ ! -r "$dir/$REFERENCES_PATH" ]; then
        fail "$REFERENCES_PATH is missing or cannot be read"
    else
        # The last line is read whether or not a newline ends it.
        while IFS= read -r path || [ -n "$path" ]; do
            if [ -z "$path" ] || [ "${path:0:1}" = "#" ]; then
                continue
            elif [ ! -f "$dir/$path" ]; then
                fail "$path, listed in $REFERENCES_PATH, is missing"
            elif [ ! -r "$dir/$path" ]; then
                fail "$path, listed in $REFERENCES_PATH, cannot be read"
            elif ! grep -a -q -F "$approved" "$dir/$path"; then
                fail "$path, listed in $REFERENCES_PATH, does not name $approved"
            fi
        done < "$dir/$REFERENCES_PATH"
    fi
    scan_references "$dir" "$approved"
}

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
