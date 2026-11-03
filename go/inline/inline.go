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

// Package inline runs go vet's inline analyzer under nogo. The analyzer
// reads the source of each function marked "//go:fix inline" through
// pass.ReadFile, which rules_go's nogo leaves unset, so that it fails on
// any package with such a function; the other analyzers fall back to
// os.ReadFile, and this one is given it.
package inline

import (
	"os"

	"golang.org/x/tools/go/analysis"
	xinline "golang.org/x/tools/go/analysis/passes/inline"
)

// Analyzer is go vet's inline analyzer, with pass.ReadFile set when nogo
// leaves it unset.
var Analyzer = &analysis.Analyzer{
	Name:      xinline.Analyzer.Name,
	Doc:       xinline.Analyzer.Doc,
	URL:       xinline.Analyzer.URL,
	Requires:  xinline.Analyzer.Requires,
	FactTypes: xinline.Analyzer.FactTypes,
	Run: func(pass *analysis.Pass) (any, error) {
		if pass.ReadFile == nil {
			pass.ReadFile = os.ReadFile
		}
		return xinline.Analyzer.Run(pass)
	},
}
