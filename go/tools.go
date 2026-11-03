// Copyright 2026 Chanzo
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//go:build tools

// Package tools imports the analyzers which nogo runs, so that go mod tidy
// keeps their Go modules, and every module they need, in go.mod. Only
// Bazel builds the analyzers, through the nogo target in BUILD.bazel,
// which Gazelle is told to leave this file out of.
package tools

import (
	_ "github.com/gordonklaus/ineffassign/pkg/ineffassign"
	_ "github.com/kisielk/errcheck/errcheck"
	_ "golang.org/x/tools/go/analysis/passes/appends"
	_ "golang.org/x/tools/go/analysis/passes/asmdecl"
	_ "golang.org/x/tools/go/analysis/passes/assign"
	_ "golang.org/x/tools/go/analysis/passes/atomic"
	_ "golang.org/x/tools/go/analysis/passes/bools"
	_ "golang.org/x/tools/go/analysis/passes/buildtag"
	_ "golang.org/x/tools/go/analysis/passes/composite"
	_ "golang.org/x/tools/go/analysis/passes/copylock"
	_ "golang.org/x/tools/go/analysis/passes/defers"
	_ "golang.org/x/tools/go/analysis/passes/directive"
	_ "golang.org/x/tools/go/analysis/passes/errorsas"
	_ "golang.org/x/tools/go/analysis/passes/framepointer"
	_ "golang.org/x/tools/go/analysis/passes/hostport"
	_ "golang.org/x/tools/go/analysis/passes/httpresponse"
	_ "golang.org/x/tools/go/analysis/passes/ifaceassert"
	_ "golang.org/x/tools/go/analysis/passes/inline"
	_ "golang.org/x/tools/go/analysis/passes/loopclosure"
	_ "golang.org/x/tools/go/analysis/passes/lostcancel"
	_ "golang.org/x/tools/go/analysis/passes/nilfunc"
	_ "golang.org/x/tools/go/analysis/passes/printf"
	_ "golang.org/x/tools/go/analysis/passes/shift"
	_ "golang.org/x/tools/go/analysis/passes/sigchanyzer"
	_ "golang.org/x/tools/go/analysis/passes/slog"
	_ "golang.org/x/tools/go/analysis/passes/stdmethods"
	_ "golang.org/x/tools/go/analysis/passes/stdversion"
	_ "golang.org/x/tools/go/analysis/passes/stringintconv"
	_ "golang.org/x/tools/go/analysis/passes/structtag"
	_ "golang.org/x/tools/go/analysis/passes/testinggoroutine"
	_ "golang.org/x/tools/go/analysis/passes/tests"
	_ "golang.org/x/tools/go/analysis/passes/timeformat"
	_ "golang.org/x/tools/go/analysis/passes/unmarshal"
	_ "golang.org/x/tools/go/analysis/passes/unreachable"
	_ "golang.org/x/tools/go/analysis/passes/unsafeptr"
	_ "golang.org/x/tools/go/analysis/passes/unusedresult"
	_ "golang.org/x/tools/go/analysis/passes/waitgroup"
	_ "honnef.co/go/tools/quickfix"
	_ "honnef.co/go/tools/simple"
	_ "honnef.co/go/tools/staticcheck"
	_ "honnef.co/go/tools/stylecheck"
)
