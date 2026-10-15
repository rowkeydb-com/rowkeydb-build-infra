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

"""Prints an lcov report without its execution counts.

What remains is the report's shape: each source file, and the set of
lines, functions and branches the report lists for it. The counts are left
out, since a test with threads may execute a line a different number of
times, or take a different branch, from one run to the next. So are the
totals of lines, functions and branches found and hit, which follow from
the records, and repeated records: Bazel's merger may list a branch that
no test executed once or several times. Files are printed in order of their
paths, and the records of each file in sorted order, so that the order in
which the report was merged does not matter.

Usage: python3 -I lcov_shape.py report.dat
"""
import collections
import sys

# Records whose values are counts, or totals which follow from the records.
SKIPPED = ("FNDA:", "LF:", "LH:", "FNF:", "FNH:", "BRF:", "BRH:")

files = collections.defaultdict(set)
source = ""
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if line.startswith("SF:"):
        source = line
        files[source]
        continue
    if line == "end_of_record":
        source = ""
        continue
    if line.startswith(SKIPPED):
        continue
    if line.startswith("DA:"):
        # DA:<line>,<count>[,<checksum>]
        line = "DA:" + line[3:].split(",")[0]
    elif line.startswith("BRDA:"):
        # BRDA:<line>,<block>,<branch>,<taken>
        line = "BRDA:" + ",".join(line[5:].split(",")[:3])
    files[source].add(line)

for source in sorted(files):
    print(source)
    for line in sorted(files[source]):
        print(line)
