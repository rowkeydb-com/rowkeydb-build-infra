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

// Package unused reports the unused code which staticcheck's U1000 finds.
// U1000 returns its findings as its result and reports none of them, so
// nogo would never fail on them; this analyzer reports each one, as
// golangci-lint's unused linter does.
package unused

import (
	"fmt"
	"go/token"

	"golang.org/x/tools/go/analysis"
	scunused "honnef.co/go/tools/unused"
)

// Analyzer reports each object U1000 finds unused. U1000 runs with its
// default options, which equal golangci-lint's.
var Analyzer = &analysis.Analyzer{
	Name:     "unused",
	Doc:      "reports unused constants, variables, functions, types and fields",
	Requires: []*analysis.Analyzer{scunused.Analyzer.Analyzer},
	Run:      run,
}

func run(pass *analysis.Pass) (any, error) {
	result := pass.ResultOf[scunused.Analyzer.Analyzer].(scunused.Result)
	used := make(map[string]bool, len(result.Used))
	for _, object := range result.Used {
		used[key(object)] = true
	}
	for _, object := range result.Unused {
		// As in golangci-lint: an unused type parameter is not reported,
		// and neither is an object which U1000 also finds used, as it can
		// when it reaches the same object twice.
		if object.Kind == "type param" || used[key(object)] {
			continue
		}
		pass.Report(analysis.Diagnostic{
			Pos:     position(pass, object.Position),
			Message: fmt.Sprintf("%s %s is unused", object.Kind, object.Name),
		})
	}
	return nil, nil
}

// key identifies an object by its file, line and name, as golangci-lint
// does.
func key(object scunused.Object) string {
	return fmt.Sprintf("%s %d %s", object.Position.Filename, object.Position.Line, object.Name)
}

// position finds, in the pass's file set, the position which U1000 gives
// as a file name, a line and a column; a diagnostic needs the former.
func position(pass *analysis.Pass, at token.Position) token.Pos {
	for _, file := range pass.Files {
		tokenFile := pass.Fset.File(file.Pos())
		if tokenFile == nil || tokenFile.Name() != at.Filename {
			continue
		}
		if at.Line < 1 || at.Line > tokenFile.LineCount() {
			break
		}
		offset := tokenFile.Offset(tokenFile.LineStart(at.Line)) + max(at.Column-1, 0)
		return tokenFile.Pos(min(offset, tokenFile.Size()))
	}
	return token.NoPos
}
