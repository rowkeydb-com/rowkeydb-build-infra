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

"""The analyzers of the nogo target in BUILD.bazel: those golangci-lint
2.15.0 runs with its default settings for the linters govet, staticcheck,
errcheck, ineffassign and unused, at the versions of golangci-lint's
go.mod, which go.mod here repeats."""

# govet: the analyzers of go vet in Go 1.27.3, cmd/vet's suite, which with
# inline are golangci-lint's default set. cgocall is left out: it reads the
# sources cgo generates, and the shared options build Go without cgo.
# inline runs through //go/inline, which gives it the pass.ReadFile nogo
# leaves unset.
GOVET = ["@org_golang_x_tools//go/analysis/passes/" + name for name in [
    "appends", "asmdecl", "assign", "atomic", "bools", "buildtag", "composite",
    "copylock", "defers", "directive", "errorsas", "framepointer", "hostport",
    "httpresponse", "ifaceassert", "loopclosure", "lostcancel",
    "nilfunc", "printf", "shift", "sigchanyzer", "slog", "stdmethods",
    "stdversion", "stringintconv", "structtag", "testinggoroutine", "tests",
    "timeformat", "unmarshal", "unreachable", "unsafeptr", "unusedresult",
    "waitgroup",
]] + ["//go/inline"]

# staticcheck v0.8.2: every check in the lists of its packages staticcheck,
# simple, stylecheck and quickfix, which golangci-lint enables as "all",
# except ST1000, ST1003, ST1016, ST1020, ST1021 and ST1022, which
# golangci-lint turns off by default. Each check is a package of its own
# which exports its analyzer. SA5011 is in no list: staticcheck disabled it.
STATICCHECK = [
    "@co_honnef_go_tools//%s/%s" % (family, name)
    for family, names in [
        ("staticcheck", [
            "sa1000", "sa1001", "sa1002", "sa1003", "sa1004", "sa1005",
            "sa1006", "sa1007", "sa1008", "sa1010", "sa1011", "sa1012",
            "sa1013", "sa1014", "sa1015", "sa1016", "sa1017", "sa1018",
            "sa1019", "sa1020", "sa1021", "sa1023", "sa1024", "sa1025",
            "sa1026", "sa1027", "sa1028", "sa1029", "sa1030", "sa1031",
            "sa1032", "sa2000", "sa2001", "sa2002", "sa2003", "sa3000",
            "sa3001", "sa4000", "sa4001", "sa4003", "sa4004", "sa4005",
            "sa4006", "sa4008", "sa4009", "sa4010", "sa4011", "sa4012",
            "sa4013", "sa4014", "sa4015", "sa4016", "sa4017", "sa4018",
            "sa4019", "sa4020", "sa4021", "sa4022", "sa4023", "sa4024",
            "sa4025", "sa4026", "sa4027", "sa4028", "sa4029", "sa4030",
            "sa4031", "sa4032", "sa5000", "sa5001", "sa5002", "sa5003",
            "sa5004", "sa5005", "sa5007", "sa5008", "sa5009", "sa5010",
            "sa5012", "sa6000", "sa6001", "sa6002", "sa6003", "sa6005",
            "sa6006", "sa9001", "sa9002", "sa9003", "sa9004", "sa9005",
            "sa9006", "sa9007", "sa9008", "sa9009", "sa9010",
        ]),
        ("simple", [
            "s1000", "s1001", "s1002", "s1003", "s1004", "s1005", "s1006",
            "s1007", "s1008", "s1009", "s1010", "s1011", "s1012", "s1016",
            "s1017", "s1018", "s1019", "s1020", "s1021", "s1023", "s1024",
            "s1025", "s1028", "s1029", "s1030", "s1031", "s1032", "s1033",
            "s1034", "s1035", "s1036", "s1037", "s1038", "s1039", "s1040",
        ]),
        ("stylecheck", [
            "st1001", "st1005", "st1006", "st1008", "st1011", "st1012",
            "st1013", "st1015", "st1017", "st1018", "st1019", "st1023",
        ]),
        ("quickfix", [
            "qf1001", "qf1002", "qf1003", "qf1004", "qf1005", "qf1006",
            "qf1007", "qf1008", "qf1009", "qf1010", "qf1011", "qf1012",
        ]),
    ]
    for name in names
]

# errcheck v1.30.0 and ineffassign v0.2.0, whose defaults are
# golangci-lint's: errcheck excludes its default symbols and checks neither
# assignments to the blank identifier nor type assertions. unused reports
# what staticcheck's U1000 finds.
OTHERS = [
    "@com_github_gordonklaus_ineffassign//pkg/ineffassign",
    "@com_github_kisielk_errcheck//errcheck",
    "//go/unused",
]
