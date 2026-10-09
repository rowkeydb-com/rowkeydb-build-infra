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

"""Compares two decoded execution logs (decode.py output).

For spawns: the multiset of action digests, and the multiset of content
hashes (arguments, environment, platform, expanded inputs and tools,
outputs, exit code, timeout and cacheability). For symlink actions: the
multiset of (mnemonic, target, input, output). Prints the counts and, for
each spawn present on one side only, its identity and which fields differ
from the spawn on the other side with the same mnemonic, target and outputs.

Usage: python3 -I compare.py before.jsonl after.jsonl
"""
import collections
import json
import sys


def load(path):
    return [json.loads(line) for line in open(path)]


a, b = load(sys.argv[1]), load(sys.argv[2])
for kind in ("spawn", "symlink"):
    ra = [r for r in a if r["kind"] == kind]
    rb = [r for r in b if r["kind"] == kind]
    print(f"{kind}: {len(ra)} before, {len(rb)} after")
    ca = collections.Counter(r["content"] for r in ra)
    cb = collections.Counter(r["content"] for r in rb)
    print(f"  content only before: {sum((ca - cb).values())}, "
          f"only after: {sum((cb - ca).values())}")
    if kind == "spawn":
        da = collections.Counter(r["digest"] for r in ra)
        db = collections.Counter(r["digest"] for r in rb)
        print(f"  digest only before: {sum((da - db).values())}, "
              f"only after: {sum((db - da).values())}, "
              f"spawns without digest: {da['']} before, {db['']} after")
        ident = lambda r: (r["mnemonic"], r["target"], tuple(r["outputs"]))
        byid = collections.defaultdict(list)
        for r in rb:
            byid[ident(r)].append(r)
        for r in ra:
            if r["content"] in cb:
                continue
            others = byid.get(ident(r), [])
            print("  DIFF", r["mnemonic"], r["target"], r["outputs"][:1])
            for o in others[:1]:
                for k in sorted(r):
                    if k in ("content",):
                        continue
                    if r[k] != o[k]:
                        if isinstance(r[k], list):
                            sa, sb = set(map(json.dumps, r[k])), set(map(json.dumps, o[k]))
                            print(f"    {k}: before-only {sorted(sa - sb)[:5]}"
                                  f" after-only {sorted(sb - sa)[:5]}"
                                  f" (same set: {sa == sb})")
                        else:
                            print(f"    {k}: {r[k]!r} vs {o[k]!r}")
