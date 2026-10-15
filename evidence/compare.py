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

Finally, it pairs the spawns of the two sides by content and compares the
digests of their outputs: for each content, the multiset of output sets on
one side with that on the other. It prints every path whose digest differs
within a pair, and the number of such pairs.

When the image changes, every action digest changes with the platform's
container-image property, and the comparison of content needs three
options. With any of them it also prints, for each side, the number of
cache hits and the runners of the spawns, describes the spawns found after
only as it does those found before only, names each spawn whose content
occurs more often on one side, and reports what each option affected:

--strip-property NAME removes the platform property NAME from the content.
  For each side it prints every value the property had, with the number of
  spawns, and the number of spawns without it, so that each side can be
  seen to name its own image only.
--varying REGEX names, by a regular expression which must match the whole
  path, files which differ from run to run, such as test logs. Their
  digests are left out of the comparison of outputs and, where they are
  inputs or tools, out of the content. For each side and expression it
  prints every path it matched, as an output or as an input or tool, and
  the number of inputs and tools it blanked, by the mnemonic of their
  spawn.
--test-duration leaves out of the content the argument, all digits, in
  which the spawn that writes a test's test.xml records the test's
  duration, and prints for each side the target of every spawn it applied
  to.

Each option but --test-duration may be given more than once.

Usage: python3 -I compare.py [--strip-property NAME]... [--varying REGEX]...
           [--test-duration] before.jsonl after.jsonl
"""
import argparse
import collections
import hashlib
import json
import re

# Fields that describe a run of the action, not the action.
RUN_FIELDS = ("content", "runner", "cache_hit", "output_digests")

# The script whose spawn writes test.xml; its arguments are the script, the
# test log, test.xml, the duration in seconds and the exit code.
GENERATE_XML = "external/bazel_tools/tools/test/generate-xml.sh"

parser = argparse.ArgumentParser(
    description="Compares two decoded execution logs.")
parser.add_argument("before")
parser.add_argument("after")
parser.add_argument("--strip-property", action="append", default=[],
                    metavar="NAME")
parser.add_argument("--varying", action="append", default=[],
                    metavar="REGEX")
parser.add_argument("--test-duration", action="store_true")
args = parser.parse_args()
varying = [re.compile(v) for v in args.varying]
normalising = bool(args.strip_property or varying or args.test_duration)


def load(path):
    return [json.loads(line) for line in open(path)]


def ident(r):
    return (r["mnemonic"], r["target"], tuple(r["outputs"]))


def matching(path):
    """The varying expressions which match the whole path."""
    return [v.pattern for v in varying if v.fullmatch(path)]


class Report:
    """What the options affected on one side."""

    def __init__(self):
        self.properties = collections.Counter()
        self.outputs = collections.defaultdict(set)
        self.inputs = collections.defaultdict(set)
        self.blanked = collections.defaultdict(collections.Counter)
        self.durations = []


def normalise(r, report):
    """Sets r["norm"], the spawn's fields that describe the action, and
    r["key"], their hash, with the options applied. Without options the
    key is the content hash decode.py recorded."""
    norm = {k: v for k, v in r.items() if k not in RUN_FIELDS and k != "digest"}
    if not normalising:
        r["norm"], r["key"] = norm, r["content"]
        return
    for name in args.strip_property:
        values = [v for n, v in r["platform"] if n == name]
        report.properties[(name, values[0] if values else "(absent)")] += 1
    norm["platform"] = [[n, v] for n, v in r["platform"]
                        if n not in args.strip_property]
    for field in ("inputs", "tools"):
        entries = []
        for p, k, d in r[field]:
            hits = matching(p)
            for h in hits:
                report.inputs[h].add(p)
                report.blanked[h][r["mnemonic"]] += 1
            entries.append([p, k, "" if hits else d])
        norm[field] = entries
    for p, _ in r["output_digests"]:
        for h in matching(p):
            report.outputs[h].add(p)
    a = r["args"]
    if (args.test_duration and len(a) == 5 and a[0] == GENERATE_XML
            and a[3].isdigit()):
        norm["args"] = a[:3] + [""] + a[4:]
        report.durations.append(r["target"])
    r["norm"] = norm
    r["key"] = hashlib.sha256(
        json.dumps(norm, sort_keys=True).encode()).hexdigest()


def print_report(side, rs, report):
    runners = collections.Counter(r["runner"] for r in rs)
    hits = sum(r["cache_hit"] for r in rs)
    print(f"  {side}: cache hits: {hits}; runners: {dict(runners)}")
    for (name, value), n in sorted(report.properties.items()):
        print(f"  {side}: {name} = {value}: {n} spawns")
    for v in varying:
        h = v.pattern
        outs, ins = sorted(report.outputs[h]), sorted(report.inputs[h])
        print(f"  {side}: --varying {h!r} matched {len(outs)} output paths "
              f"and {len(ins)} input or tool paths; inputs blanked, by "
              f"mnemonic: "
              f"{dict(report.blanked[h])}")
        for p in outs:
            print(f"    output {p}")
        for p in ins:
            print(f"    input {p}")
    if args.test_duration:
        print(f"  {side}: test durations left out of "
              f"{len(report.durations)} spawns")
        for t in sorted(report.durations):
            print(f"    duration {t}")


def outputs(r):
    """The paths and digests of the spawn's outputs that do not vary."""
    return json.dumps([o for o in r["output_digests"] if not matching(o[0])])


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


def compare_outputs(ra, rb):
    """For each content present on both sides, the output sets of one side
    which the other lacks, counted as multisets, in both directions."""
    oa = collections.defaultdict(collections.Counter)
    ob = collections.defaultdict(collections.Counter)
    first = {}
    for r in ra:
        oa[r["key"]][outputs(r)] += 1
        first.setdefault(r["key"], r)
    for r in rb:
        ob[r["key"]][outputs(r)] += 1
    paired = differ = 0
    for key in oa.keys() & ob.keys():
        paired += min(sum(oa[key].values()), sum(ob[key].values()))
        only_a, only_b = oa[key] - ob[key], ob[key] - oa[key]
        # A spawn which occurs more often on one side has no partner, and is
        # counted among the content found on one side only.
        n = min(sum(only_a.values()), sum(only_b.values()))
        if not n:
            continue
        differ += n
        r = first[key]
        print("  OUTPUTS", r["mnemonic"], r["target"], f"({n} pairs)")
        changed = set()
        for x, y in zip(sorted(only_a.elements()), sorted(only_b.elements())):
            mine, theirs = dict(json.loads(x)), dict(json.loads(y))
            changed |= {p for p in mine.keys() | theirs.keys()
                        if mine.get(p) != theirs.get(p)}
        for p in sorted(changed):
            print(f"    differ: {p}")
    print(f"  spawns paired by content: {paired}; pairs whose outputs "
          f"differ: {differ}")


a, b = load(args.before), load(args.after)
for kind in ("spawn", "symlink"):
    ra = [r for r in a if r["kind"] == kind]
    rb = [r for r in b if r["kind"] == kind]
    print(f"{kind}: {len(ra)} before, {len(rb)} after")
    if kind == "symlink":
        for r in ra + rb:
            r["key"] = r["content"]
    else:
        reports = {"before": Report(), "after": Report()}
        for side, rs in (("before", ra), ("after", rb)):
            for r in rs:
                normalise(r, reports[side])
    ca = collections.Counter(r["key"] for r in ra)
    cb = collections.Counter(r["key"] for r in rb)
    print(f"  content only before: {sum((ca - cb).values())}, "
          f"only after: {sum((cb - ca).values())}")
    if kind == "spawn":
        if normalising:
            print_report("before", ra, reports["before"])
            print_report("after", rb, reports["after"])
        da = collections.Counter(r["digest"] for r in ra)
        db = collections.Counter(r["digest"] for r in rb)
        print(f"  digest only before: {sum((da - db).values())}, "
              f"only after: {sum((db - da).values())}, "
              f"spawns without digest: {da['']} before, {db['']} after")
        # With options, the spawns found after only are described as well.
        sides = [("DIFF", ra, rb, cb)]
        if normalising:
            sides.append(("DIFF after", rb, ra, ca))
        for label, rs, others_rs, other_keys in sides:
            byid = collections.defaultdict(list)
            for r in others_rs:
                byid[ident(r)].append(r)
            for r in rs:
                if r["key"] in other_keys:
                    continue
                others = byid.get(ident(r), [])
                print(" ", label, r["mnemonic"], r["target"], r["outputs"][:1])
                for o in others[:1]:
                    n = dict(r["norm"], digest=r["digest"])
                    m = dict(o["norm"], digest=o["digest"])
                    if rs is rb:
                        n, m = m, n
                    for k in sorted(n):
                        if n[k] == m[k]:
                            continue
                        if isinstance(n[k], list):
                            sa = set(map(json.dumps, n[k]))
                            sb = set(map(json.dumps, m[k]))
                            print(f"    {k}: before-only {sorted(sa - sb)[:5]}"
                                  f" after-only {sorted(sb - sa)[:5]}"
                                  f" (same set: {sa == sb})")
                        else:
                            print(f"    {k}: {n[k]!r} vs {m[k]!r}")
        if normalising:
            # Content found on both sides, but more often on one.
            for side, rs, extra, other_keys in (("before", ra, ca - cb, cb),
                                                ("after", rb, cb - ca, ca)):
                named = {r["key"]: r for r in rs}
                for key, n in sorted(extra.items()):
                    if key in other_keys:
                        r = named[key]
                        print(f"  EXTRA {side} {r['mnemonic']} {r['target']}"
                              f" ({n} more copies)")
        for side, rs, others in (("before", ra, rb), ("after", rb, ra)):
            n, found, same = misses(rs, others)
            print(f"  cacheable spawns not found in the cache {side}: {n}; "
                  f"the other side found {found} of them in the cache "
                  f"under the same digest, {same} with the same outputs")
        compare_outputs(ra, rb)
