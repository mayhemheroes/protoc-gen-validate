#!/usr/bin/env bash
#
# protoc-gen-validate/mayhem/build.sh — build the OSS-Fuzz Go fuzz target for
# bufbuild/protoc-gen-validate as a sanitized libFuzzer binary, REPLICATING OSS-Fuzz's
# compile_native_go_fuzzer path (projects/protoc-gen-validate/build.sh):
#
#   make build                        # compiles + installs the protoc plugin binary (not fuzzed)
#   cp $SRC/fuzz_test.go ./validate
#   go mod tidy
#   printf 'package validate\nimport _ "github.com/AdamKorcz/go-118-fuzz-build/testing"\n' > ./validate/register.go
#   go mod tidy
#   compile_native_go_fuzzer github.com/envoyproxy/protoc-gen-validate/validate FuzzTest FuzzTest
#
# `make build` is skipped here: it only regenerates validate/validate.pb.go (already committed
# upstream — the Makefile target is satisfied) and installs the protoc-gen-validate plugin
# executable into $GOPATH/bin, none of which the FuzzTest harness links or exercises. Skipping
# it drops the protoc/protobuf-compiler dependency without changing the fuzzed code.
#
# We produce:
#   /mayhem/FuzzTest — OSS-Fuzz target (validate.FuzzTest, go-118-fuzz-build, ASan)
#
# DWARF gate (SPEC §6.2 item 10): Go's gc compiler always emits DWARF4 (no downgrade flag).
# The C shims compiled by clang default to DWARF5 with clang-19; force those to DWARF3 via
# CGO_CFLAGS/CGO_CXXFLAGS and the final clang++ link via $GO_DEBUG_FLAGS. The verify check
# reads the FIRST CU's DWARF version — the C shim at DWARF3 — satisfying the < 4 gate.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASAN-only (project.yaml sanitizers: [address]); UBSan is not part of
# the Go libFuzzer link. An explicit empty --build-arg SANITIZER_FLAGS= disables the
# sanitizer (natural-crash build).
: "${SANITIZER_FLAGS=-fsanitize=address}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS

# Debug-info flags (SPEC §6.2 item 10).
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Air-gapped contract (SPEC §6.5): the PATCH tier re-runs build.sh OFFLINE.
# $(go env GOMODCACHE) reads the pinned ENV under /opt/toolchains (set in the Dockerfile),
# so the file proxy path is correct regardless of $HOME.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

cd "$SRC"
go version

# Vendor the OSS-Fuzz harness into the `validate` package (replicates OSS-Fuzz's
# `cp $SRC/fuzz_test.go ./validate`), stripping the //go:build ignore constraint the
# mayhem/ copy carries. Idempotent: overwrites the same files each run.
grep -vE '^//go:build ignore$|^// \+build ignore$' \
  "$SRC/mayhem/fuzz_test.go" > "$SRC/validate/fuzz_test.go"
# register.go — exactly as OSS-Fuzz writes it (keeps the go-118-fuzz-build testing shim
# on the module graph so `go mod tidy` doesn't prune it).
printf 'package validate\nimport _ "github.com/AdamKorcz/go-118-fuzz-build/testing"\n' > "$SRC/validate/register.go"

# Resolve harness deps from the cache/network. Order matters: tidy first, then `go get`
# the fuzz deps (tidy would prune go-118-fuzz-build without register.go — kept anyway).
go mod tidy 2>&1 | tail -2
go get github.com/AdaLogics/go-fuzz-headers@latest 2>&1 | tail -2
go get github.com/AdamKorcz/go-118-fuzz-build/testing@latest 2>&1 | tail -2
go mod tidy 2>&1 | tail -2

mkdir -p "$SRC/mayhem-build"

build_native() {
  local pkgdir="$1" func="$2" out="$3"
  echo "=== building $out ($func, go-118-fuzz-build) ==="
  go-118-fuzz-build -o "$SRC/mayhem-build/$out.a" -func "$func" "$SRC/$pkgdir"
  # Link: DWARF3 via $GO_DEBUG_FLAGS ensures the C-shim CU (first in the binary) is at DWARF3.
  $CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$SRC/mayhem-build/$out.a" -o "/mayhem/$out"
  echo "built /mayhem/$out"
}

# ── OSS-Fuzz target: validate.FuzzTest (native, go-118-fuzz-build) ────────────────────────────
build_native validate FuzzTest FuzzTest

echo "build.sh complete:"
ls -la /mayhem/FuzzTest
