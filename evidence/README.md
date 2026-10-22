# Evidence tools

These tools show whether a change leaves a consumer's build as intended.
They compare the BuildBuddy invocations of a consumer's CI jobs on two
branches: one before the change and one after it. They showed that
rowkeydb's adoption of this repository left its build unchanged, and each
later change is shown with them again.

They need curl, jq, zstd, protoc and Python 3 with the protobuf package;
they were last run with protoc 3.21.12 and protobuf 6.33.5. They also need a
BuildBuddy API key, read from `~/.config/buildbuddy/api-key` unless
`BUILDBUDDY_API_KEY_FILE` names another file.

- `fetch.sh` downloads each invocation's record and its compact execution
  log.
- `options.py` compares the canonical command lines of the two sets,
  startup options included. It prints how many invocations have
  identical options and groups the invocations that can be paired.
- `decode.py` turns an execution log into one JSON line per action. Each
  line holds the action's arguments, environment, platform, fully
  expanded inputs and outputs, but not its timing. A spawn's line also
  gives its runner, whether it was a cache hit, and the digest of each
  output, which describe the run, not the action.
- `compare.py` compares two decoded logs by action digest and by content.
  For each action that differs, it names the fields that differ. For each
  side, it also counts the cacheable actions that were not found in the
  cache, how many of them the other side found in the cache under the same
  action digest, and how many of those produced the same outputs. When the
  other side ran first, such an action had been evicted from the cache in
  between, its key unchanged; when this side ran first, it is the action
  whose result the other side then found. Last, it pairs the spawns of the
  two sides by content and compares the digests of their outputs, counting
  each set of outputs as often as it occurs. Four options serve a
  comparison by content, which a change of image needs, since it changes
  every action digest, and which two runs of one commit also need, since
  some files vary from run to run; each reports what it affected.
  `--strip-property` removes a platform property from the
  content and prints, for each side, every value the property had.
  `--varying` names, by a regular expression which must match the whole
  path, files which differ from run to run; their digests are left out of
  the comparison of outputs and, where they are inputs, out of the
  content, and the paths each expression matched are printed.
  `--test-duration` leaves out the test's duration from the arguments of
  the spawn which writes `test.xml`. A fourth, `--rename`, replaces a
  part of each path, for files whose names differ from run to run, and
  prints every path it changed. A fifth, `--strip-arg`, leaves out of the
  content every argument a regular expression matches whole, for a change
  of compiler options made on purpose, and prints each argument left out
  with the number of spawns; what remains must then pair.
- `find.py` prints the digest and size of each file entry in an execution
  log whose path matches a regular expression, and `fetch_blob.sh`
  downloads such a file from BuildBuddy's cache and checks its digest.
- `lcov_records.py` prints an lcov coverage report's records without
  their counts: each source file and the set of lines, functions and
  branches listed for it.
- `rcexpand.py` expands two rc files as Bazel's client does. It then
  compares every option of every configuration in them, including the
  configurations no CI job runs.
- `spawn.proto` is Bazel 7.6.1's `src/main/protobuf/spawn.proto`, copied
  unchanged (SHA-256
  `381bcb109e2855d4055fdc75988cc2144e0a92aa8586298123bb662cdefa6afe`).
  It must match the Bazel version in `.bazelversion`. When that version
  changes, replace it with the new version's file.

## Procedure

1. Create two branches of the consumer: `before` and `after`. Both run
   the same CI jobs, and the jobs pass `--execution_log_compact_file`.
   The shared options' `buildbuddy` configuration sets it, and BuildBuddy
   keeps the log with the invocation. Put a tag on each branch's commit,
   so that the commits remain after the branches are deleted.
2. Fetch both sides into one directory:
   `evidence/fetch.sh <dir> before- <invocation id>...` and
   `evidence/fetch.sh <dir> after- <invocation id>...`. Keep that
   directory on disk with the record: BuildBuddy's cache evicts the
   execution logs in time.
3. Compare the options: `python3 -I evidence/options.py <dir>`. Add
   `--ignore <option>` for each option the change sets on purpose.
4. Compile the descriptor:

   ```
   protoc --include_imports --descriptor_set_out=spawn.desc \
       -I evidence evidence/spawn.proto
   ```

5. Decode each log:

   ```
   zstd -dc <dir>/<side>-<id>.zst |
       python3 -I evidence/decode.py spawn.desc > <side>-<id>.jsonl
   ```

6. Compare each pair that `options.py` grouped:
   `python3 -I evidence/compare.py before-<id>.jsonl after-<id>.jsonl`.
7. Compare the configurations no CI job runs:

   ```
   python3 -I evidence/rcexpand.py <before .bazelrc> <after .bazelrc> \
       <before checkout> <after checkout>
   ```

   Each checkout resolves `%workspace%` in its own side's imports, so that
   a change of an imported file, such as the copy of the shared options,
   is compared.

A pair whose actions are identical builds the same outputs from the same
inputs. A pair that differs needs an account of each difference.
RowKeyDB's `design/shared_build_architecture.md` gives one for each of the
three that rowkeydb's adoption showed.

When the image changes, both branches run every action: each adds
`build --noremote_accept_cached` to its `.bazelrc`, so that each action
runs in its own branch's image. The procedure then differs as follows.

- The branch tags must not begin with `v`, which rowkeydb's release
  workflow takes for a release.
- The before branch's jobs are run twice, one run after the other. The
  second run is fetched into a directory of its own, under the prefix
  `after-`, since `options.py` reads only the prefixes `before-` and
  `after-`. The two runs are compared with `--test-duration` and a
  `--varying` expression for each file the design names in advance: each
  test's `test.log` and `test.xml`; and, from coverage, `lcov_files.tmp`,
  the counters each test writes (the `.gcda` files, Go's
  `go_coverage.<number>.dat` files and each test's `coverage.dat`) and the
  merged report, `_coverage_report.dat`. The random number in the name of
  Go's files is replaced with `--rename`, so that the spawns which write
  and read them pair.
  Every spawn must be paired by content; every path whose digest differs
  within a pair is a further file which varies from run to run, and is
  added to the expressions given to `--varying`. The comparison is
  repeated with each expression added until every spawn is paired and no
  pair's outputs differ, since a varying file may also be the input of a
  later spawn. An expression must
  match the whole path, so a literal path has its special characters,
  such as `.`, escaped.
- The options are compared with `--ignore remote_default_exec_properties`
  as well, since that option names the image; the lock files are still
  compared.
- Each pair is compared with `--strip-property container-image`,
  `--test-duration`, that `--rename` and those `--varying` expressions.
  The pair is equal when no spawn was a cache hit, every spawn and every
  symlink action is paired by content, each side names only its own image,
  and no pair's outputs differ.

When a change is meant to change the build, as the later changes of
RowKeyDB's design are, the procedure differs again.

- The before side may be the kept logs of an earlier comparison's after
  branch, if every spawn in them, run or taken from the cache, names that
  branch's image, since a hit's recorded outputs are those of its digest
  under that image; no before branch runs again.
- The after branch adds the evidence workflow only. A new image changes
  every remote action's key, so every remote action runs without
  `--noremote_accept_cached`; the spawns which run in the client container
  may be cache hits, and are named in the record.
- Each pair is compared with `--strip-arg` as well, one expression for
  each compiler option the change adds or moves, listed in advance. What
  fails to pair, and each output which differs, must be what the change
  intends, and is accounted for in the record.
- The merged coverage reports vary in their counts, so their records
  without counts are compared instead, and must be equal; which lines and
  branches were executed is then not compared. For each side's coverage
  invocation:

  ```
  zstd -dc <dir>/<side>-<id>.zst | python3 -I evidence/find.py \
      spawn.desc 'bazel-out/_coverage/_coverage_report\.dat'
  evidence/fetch_blob.sh <side>-report.dat <id> <digest> <size>
  python3 -I evidence/lcov_records.py <side>-report.dat \
      > <side>-records.txt
  ```

  and then `diff before-records.txt after-records.txt`.
