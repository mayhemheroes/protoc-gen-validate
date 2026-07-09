//go:build ignore

// mayhem/fuzz_test.go — the OSS-Fuzz harness for protoc-gen-validate (verbatim from
// google/oss-fuzz projects/protoc-gen-validate/fuzz_test.go). build.sh copies this file
// (stripping the ignore constraint) into ./validate as package `validate` and builds it
// with go-118-fuzz-build, replicating OSS-Fuzz's
//   compile_native_go_fuzzer github.com/envoyproxy/protoc-gen-validate/validate FuzzTest FuzzTest
// It drives the generated protobuf surface of FloatRules via go-fuzz-headers'
// struct generator: accessors, String(), ProtoReflect(), Reset().

// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package validate

import (
	"testing"

	fuzz "github.com/AdaLogics/go-fuzz-headers"
)

func FuzzTest(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		ff := fuzz.NewConsumer(data)
		x := &FloatRules{}
		ff.GenerateStruct(x)
		x.String()
		x.ProtoReflect()
		x.Descriptor()
		x.GetConst()
		x.GetLt()
		x.GetLte()
		x.GetGt()
		x.GetGte()
		x.GetIn()
		x.GetNotIn()
		x.GetIgnoreEmpty()
		x.Reset()
	})
}
