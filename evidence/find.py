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

"""Prints the path, digest and size of each file in an execution log whose
path the regular expression matches whole, one line each, so that the file
can be fetched with fetch_blob.sh.

Usage: zstd -dc log.zst | python3 -I find.py spawn.desc REGEX
"""
import re
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
pattern = re.compile(sys.argv[2])

data = sys.stdin.buffer.read()
pos = 0
while pos < len(data):
    n, pos = _DecodeVarint(data, pos)
    e = Entry()
    e.ParseFromString(data[pos:pos + n])
    pos += n
    if e.WhichOneof("type") == "file" and pattern.fullmatch(e.file.path):
        print(e.file.path, e.file.digest.hash, e.file.digest.size_bytes)
