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

"""Expands two bazelrc files as Bazel 7's client and ConfigExpander do, and
compares, for each command and each set of configurations, every option's
values in order.

Model: an `import` is read at its line; for a command, the rc options of
each command in its inheritance chain (common, build, test, coverage) are
taken in file order; `--config=X` is replaced, at its position, by the
lines `<cmd>:X` of every command in the chain, in chain order and then file
order, recursively; `--enable_platform_specific_config` is followed, at its
position, by the expansion of the platform's configuration (linux); the
command line's `--config` options follow the rc options.

Usage: python3 -I rcexpand.py before.bazelrc after.bazelrc <workspace>
(the workspace directory resolves %workspace% in an import).
"""
import collections
import itertools
import shlex
import sys


def read(path, workspace):
    lines = []
    for raw in open(path):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        words = shlex.split(raw, comments=True)
        if words[0] in ("import", "try-import"):
            lines.extend(read(words[1].replace("%workspace%", workspace),
                              workspace))
            continue
        cmd, _, cfg = words[0].partition(":")
        lines.append((cmd, cfg, words[1:]))
    return lines


CHAINS = {
    "build": ["common", "build"],
    "test": ["common", "build", "test"],
    "coverage": ["common", "build", "test", "coverage"],
    "run": ["common", "build", "run"],
}


def expansion(lines, chain, cfg, stack):
    if cfg in stack:
        raise ValueError(f"config cycle {stack + [cfg]}")
    out = []
    for cmd in chain:
        for c, k, opts in lines:
            if c == cmd and k == cfg:
                out.extend(expand_opts(lines, chain, opts, stack + [cfg]))
    return out


def expand_opts(lines, chain, opts, stack):
    out = []
    for o in opts:
        if o.startswith("--config="):
            out.append(o)
            out.extend(expansion(lines, chain, o[len("--config="):], stack))
        elif o.startswith("--enable_platform_specific_config"):
            out.append(o)
            out.extend(expansion(lines, chain, "linux", stack))
        else:
            out.append(o)
    return out


def options(lines, command, configs):
    chain = CHAINS[command]
    base = []
    for cmd in chain:
        for c, k, opts in lines:
            if c == cmd and k == "":
                base.extend(opts)
    result = expand_opts(lines, chain, base, [])
    result += expand_opts(lines, chain, [f"--config={c}" for c in configs], [])
    per = collections.defaultdict(list)
    for o in result:
        name, _, value = o.partition("=")
        per[name].append(value)
    return per


before = read(sys.argv[1], sys.argv[3])
after = read(sys.argv[2], sys.argv[3])
names = sorted({k for _, k, _ in before + after if k} - {"linux", "macos",
                                                         "windows"})
print("configurations in the files:", " ".join(names))
# No configuration, each configuration alone, and the combinations
# rowkeydb's CI jobs and release scripts select.
combos = [[]] + [[n] for n in names] + [
    ["release", "lto"], ["buildbuddy-tsan", "tsan"],
    ["buildbuddy-msan", "msan"], ["buildbuddy", "asan-ubsan"],
    ["buildbuddy", "clang-tidy"], ["buildbuddy", "release", "lto"],
    ["laptop", "buildbuddy", "release"], ["laptop", "buildbuddy"],
    ["clang", "asan"], ["msan", "libcxx"]]
differences = collections.Counter()
for command in CHAINS:
    for combo in combos:
        a = options(before, command, combo)
        b = options(after, command, combo)
        for n in sorted(set(a) | set(b)):
            if a.get(n) != b.get(n):
                differences[(n, str(a.get(n)), str(b.get(n)))] += 1
print(f"{len(CHAINS) * len(combos)} command and configuration combinations")
for (n, x, y), count in sorted(differences.items()):
    print(f"differs in {count} combinations: {n}\n  before {x}\n  after  {y}")
