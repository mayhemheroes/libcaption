#!/usr/bin/env bash
#
# mayhem/build.sh — build libcaption's fuzz harness + the functional test suite.
#
# Produces, under /mayhem:
#   ts2srt              in-process libFuzzer harness over the MPEG-TS -> caption -> SRT path
#   ts2srt-standalone   run-once reproducer for the same harness (no libFuzzer runtime)
# and, under build/ (project's NORMAL flags, so mayhem/test.sh only RUNS them):
#   build/test_wrap             upstream unit binary (unit_tests/test_wrap.c)
#   build/libcaption_selftest   additive behavioral known-answer oracle
set -euo pipefail

# clang rejects an empty SOURCE_DATE_EPOCH — unset it rather than pass "".
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

INCS="-I$SRC/caption -I$SRC/examples"

# 1) Sanitized library build (instruments the FUZZED code, DWARF < 4). Release build type keeps
#    CMake from injecting its own -g (DWARF-5); $DEBUG_FLAGS' -gdwarf-3 is the last debug flag so it wins.
cmake -S . -B build-fuzz \
    -DBUILD_EXAMPLES=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target caption
FUZZ_LIB="$SRC/build-fuzz/libcaption.a"

# 2) The harness, twice: libFuzzer engine binary + standalone run-once reproducer. ts.c (the TS demux
#    helper the original ts2srt example used) is compiled in alongside the library.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/ts2srt/ts2srt.c" "$SRC/examples/ts.c" $INCS "$FUZZ_LIB" \
    -o /mayhem/ts2srt
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" \
    "$SRC/mayhem/ts2srt/ts2srt.c" "$SRC/examples/ts.c" $INCS "$FUZZ_LIB" \
    -o /mayhem/ts2srt-standalone

# 3) Test suite with the project's NORMAL flags (a clean, separate build) so test.sh never compiles.
#    $COVERAGE_FLAGS (empty by default) instruments this build when a coverage image is requested.
cmake -S . -B build \
    -DBUILD_EXAMPLES=OFF \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS"
cmake --build build -j"$MAYHEM_JOBS" --target caption test_wrap
$CC -O2 $COVERAGE_FLAGS -I"$SRC/caption" \
    "$SRC/mayhem/libcaption_selftest.c" "$SRC/build/libcaption.a" \
    -o "$SRC/build/libcaption_selftest"

echo "build.sh: done"
