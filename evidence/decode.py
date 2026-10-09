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

"""Decoder of a Bazel 7.6.1 compact execution log.

Reads the zstd-decompressed log on stdin, parses each varint-delimited
ExecLogEntry with the protobuf runtime from the descriptor set compiled from
spawn.proto at 7.6.1 (see README.md), and writes one JSON line per spawn and per symlink
action, with every field that describes the action (not its timing), its
inputs fully expanded (files, directory contents, unresolved symlinks and
runfiles trees with their custom symlinks, root symlinks, empty files and
repo mapping manifest) and its outputs resolved to paths.

Usage: zstd -dc log.zst | python3 -I decode.py spawn.desc > spawns.jsonl
"""
import hashlib
import json
import sys

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
from google.protobuf.internal.decoder import _DecodeVarint

fds = descriptor_pb2.FileDescriptorSet()
fds.ParseFromString(open(sys.argv[1], "rb").read())
pool = descriptor_pool.DescriptorPool()
for f in fds.file:
    pool.Add(f)
Entry = message_factory.GetMessageClass(
    pool.FindMessageTypeByName("tools.protos.ExecLogEntry"))

data = sys.stdin.buffer.read()
pos = 0
entries = {}
out = []


def resolve_input(i, seen):
    """Returns sorted (path, kind, digest) tuples for entry id i."""
    e = entries[i]
    kind = e.WhichOneof("type")
    if kind == "file":
        return [(e.file.path, "file", e.file.digest.hash)]
    if kind == "directory":
        if not e.directory.files:
            return [(e.directory.path + "/", "emptydir", "")]
        return [(e.directory.path + "/" + f.path, "dirfile", f.digest.hash)
                for f in e.directory.files]
    if kind == "unresolved_symlink":
        return [(e.unresolved_symlink.path, "symlink",
                 e.unresolved_symlink.target_path)]
    if kind == "runfiles_tree":
        r = e.runfiles_tree
        res = [(r.path, "runfiles", "")]
        for p, k, d in expand_set(r.input_set_id, set()):
            res.append((r.path + "::canonical::" + p, k, d))
        for name, tgt in expand_symlinks(r.symlinks_id, set()):
            for p, k, d in resolve_input(tgt, set()):
                res.append((r.path + "::symlink::" + name + "->" + p, k, d))
        for name, tgt in expand_symlinks(r.root_symlinks_id, set()):
            for p, k, d in resolve_input(tgt, set()):
                res.append((r.path + "::rootsymlink::" + name + "->" + p, k, d))
        for ef in r.empty_files:
            res.append((r.path + "::empty::" + ef, "empty", ""))
        if r.HasField("repo_mapping_manifest"):
            res.append((r.path + "::_repo_mapping", "file",
                        r.repo_mapping_manifest.digest.hash))
        res.append((r.path + "::legacy_external", "flag",
                    str(r.legacy_external_runfiles)))
        return res
    raise ValueError(f"entry {i} of type {kind} used as an input")


def expand_set(sid, seen):
    if not sid:
        return []
    if sid in seen:
        return []
    seen.add(sid)
    s = entries[sid].input_set
    res = []
    for t in s.transitive_set_ids:
        res.extend(expand_set(t, seen))
    for i in s.input_ids:
        res.extend(resolve_input(i, set()))
    return res


def expand_symlinks(sid, seen):
    if not sid or sid in seen:
        return []
    seen.add(sid)
    s = entries[sid].symlink_entry_set
    res = []
    for t in s.transitive_set_ids:
        res.extend(expand_symlinks(t, seen))
    res.extend(sorted(s.direct_entries.items()))
    return res


while pos < len(data):
    n, pos = _DecodeVarint(data, pos)
    e = Entry()
    e.ParseFromString(data[pos:pos + n])
    pos += n
    kind = e.WhichOneof("type")
    if e.id:
        entries[e.id] = e
    if kind == "spawn":
        s = e.spawn
        outputs = []
        for o in s.outputs:
            if o.WhichOneof("type") == "output_id":
                outputs.extend(p for p, _, _ in resolve_input(o.output_id, set()))
            else:
                outputs.append("invalid:" + o.invalid_output_path)
        inputs = sorted(set(expand_set(s.input_set_id, set())))
        tools = sorted(set(expand_set(s.tool_set_id, set())))
        rec = {
            "kind": "spawn",
            "mnemonic": s.mnemonic,
            "target": s.target_label,
            "digest": s.digest.hash,
            "args": list(s.args),
            "env": sorted((v.name, v.value) for v in s.env_vars),
            "platform": sorted((p.name, p.value) for p in s.platform.properties),
            "inputs": inputs,
            "tools": tools,
            "outputs": sorted(outputs),
            "exit_code": s.exit_code,
            "timeout_millis": s.timeout_millis,
            "remotable": s.remotable,
            "cacheable": s.cacheable,
            "remote_cacheable": s.remote_cacheable,
        }
        rec["content"] = hashlib.sha256(json.dumps(
            {k: v for k, v in rec.items() if k != "digest"},
            sort_keys=True).encode()).hexdigest()
        out.append(rec)
    elif kind == "symlink_action":
        a = e.symlink_action
        rec = {"kind": "symlink", "mnemonic": a.mnemonic,
               "target": a.target_label, "input": a.input_path,
               "output": a.output_path}
        rec["content"] = hashlib.sha256(
            json.dumps(rec, sort_keys=True).encode()).hexdigest()
        out.append(rec)
    elif kind == "invocation":
        sys.stderr.write("invocation: " + str(e.invocation).replace("\n", " ")
                         + "\n")

for rec in out:
    print(json.dumps(rec, sort_keys=True))
