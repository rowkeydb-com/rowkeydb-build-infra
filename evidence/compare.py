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
Then, for each side, the cacheable spawns that were not cache hits; how
many of them the other side found in the cache under the same action
digest; and how many of those produced outputs with the same paths and
digests as the other side's.

Usage: python3 -I compare.py before.jsonl after.jsonl
"""
import collections
import json
import sys

# Fields that describe a run of the action, not the action.
RUN_FIELDS = ("content", "runner", "cache_hit", "output_digests")


def load(path):
    return [json.loads(line) for line in open(path)]


def ident(r):
    return (r["mnemonic"], r["target"], tuple(r["outputs"]))


def misses(rs, others):
    """The cacheable spawns of rs that were not cache hits; how many of
    them have a digest which one of others found in the cache; and how many
    of those have that spawn's outputs."""
    missed = [r for r in rs if r["remote_cacheable"] and not r["cache_hit"]]
    hits = collections.defaultdict(list)
    for o in others:
        if o["cache_hit"]:
            hits[o["digest"]].append(o["output_digests"])
    found = [r for r in missed if r["digest"] in hits]
    same = sum(r["output_digests"] in hits[r["digest"]] for r in found)
    return len(missed), len(found), same


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
                    if k in RUN_FIELDS:
                        continue
                    if r[k] != o[k]:
                        if isinstance(r[k], list):
                            sa, sb = set(map(json.dumps, r[k])), set(map(json.dumps, o[k]))
                            print(f"    {k}: before-only {sorted(sa - sb)[:5]}"
                                  f" after-only {sorted(sb - sa)[:5]}"
                                  f" (same set: {sa == sb})")
                        else:
                            print(f"    {k}: {r[k]!r} vs {o[k]!r}")
        for side, rs, others in (("before", ra, rb), ("after", rb, ra)):
            n, found, same = misses(rs, others)
            print(f"  cacheable spawns not found in the cache {side}: {n}; "
                  f"the other side found {found} of them in the cache "
                  f"under the same digest, {same} with the same outputs")
