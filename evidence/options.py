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

"""Compares the options of two sets of BuildBuddy invocations.

Reads the records fetch.sh wrote in a directory, before-<id>.json and
after-<id>.json, and takes from each the canonical command line Bazel
reports: the command, its targets, and every startup and command option
with its values in order. Options which describe the run rather than the
build (the build metadata, the client's environment, the rc files read
and the start time) are left out, as are the options named with --ignore.
It prints how many invocations on each side have identical options, each
invocation with no counterpart, and, for each set of identical options,
the invocations on each side, which compare.py then compares pair by pair.
It also prints the rc files each side read.

Usage: python3 -I options.py <directory> [--ignore <option name>]...
"""
import collections
import glob
import json
import os
import sys

RUN_OPTIONS = {"build_metadata", "client_env", "rc_source", "startup_time"}


def load(path, ignored):
    inv = json.load(open(path))["invocation"][0]
    command, targets, options, rc_files = "", (), [], []
    for event in inv["event"]:
        line = event.get("buildEvent", {}).get("structuredCommandLine")
        if not line or line.get("commandLineLabel") != "canonical":
            continue
        for section in line["sections"]:
            label = section.get("sectionLabel")
            if label == "command":
                command = " ".join(section["chunkList"]["chunk"])
            elif label == "residual":
                targets = tuple(section.get("chunkList", {}).get("chunk", []))
            elif label == "startup options":
                for option in section.get("optionList", {}).get("option", []):
                    options.append(("startup " + option.get("optionName", ""),
                                    option.get("optionValue", "")))
            elif label == "command options":
                for option in section.get("optionList", {}).get("option", []):
                    name = option.get("optionName", "")
                    value = option.get("optionValue", "")
                    if name == "rc_source":
                        rc_files.append(value)
                    if name in RUN_OPTIONS or name in ignored:
                        continue
                    options.append((name, value))
    per = collections.defaultdict(list)
    for name, value in options:
        per[name].append(value)
    key = (command, targets, tuple(sorted((k, tuple(v)) for k, v in per.items())))
    return key, tuple(rc_files)


def main():
    directory = sys.argv[1]
    rest = sys.argv[2:]
    ignored = {rest[i + 1] for i in range(len(rest) - 1) if rest[i] == "--ignore"}
    groups = collections.defaultdict(lambda: {"before": [], "after": []})
    rc = {"before": set(), "after": set()}
    for side in ("before", "after"):
        for path in sorted(glob.glob(os.path.join(directory, side + "-*.json"))):
            key, rc_files = load(path, ignored)
            groups[key][side].append(os.path.basename(path)[len(side) + 1:-5])
            rc[side].add(rc_files)
    counts = {side: sum(len(g[side]) for g in groups.values())
              for side in ("before", "after")}
    paired = sum(min(len(g["before"]), len(g["after"])) for g in groups.values())
    print(f"invocations: {counts['before']} before, {counts['after']} after")
    print(f"paired with identical options: {paired}")
    for (command, targets, _), g in sorted(groups.items()):
        print(f"{command} {' '.join(targets)}")
        print(f"  before: {' '.join(g['before']) or '(none)'}")
        print(f"  after:  {' '.join(g['after']) or '(none)'}")
    for side in ("before", "after"):
        for rc_files in sorted(rc[side]):
            print(f"rc files {side}: {' '.join(rc_files)}")


main()
