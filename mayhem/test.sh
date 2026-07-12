#!/usr/bin/env bash
#
# mayhem/test.sh — RUN libcaption's functional oracle (built by mayhem/build.sh). Never compiles.
# Behavioral: it diffs the upstream test_wrap binary's output against a committed golden file and
# runs a known-answer selftest, so a patch that no-ops the library FAILS here (not exit-0-hackable).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASS=0 FAIL=0

TW="$SRC/build/test_wrap"
GOLDEN="$SRC/mayhem/testdata/test_wrap.expected"
if [ ! -x "$TW" ]; then
  echo "test.sh: missing $TW (build.sh should have produced it)" >&2
  FAIL=$((FAIL+1))
else
  # test_wrap writes its wrapped lines to stderr; compare byte-for-byte with the golden.
  got="$("$TW" 2>&1 1>/dev/null)"
  if [ "$got" = "$(cat "$GOLDEN")" ]; then
    echo "ok   - unit_tests/test_wrap matches golden"; PASS=$((PASS+1))
  else
    echo "FAIL - unit_tests/test_wrap output differs from golden"; FAIL=$((FAIL+1))
    diff <(printf '%s\n' "$got") "$GOLDEN" | sed 's/^/        /' || true
  fi
fi

ST="$SRC/build/libcaption_selftest"
if [ ! -x "$ST" ]; then
  echo "test.sh: missing $ST (build.sh should have produced it)" >&2
  FAIL=$((FAIL+1))
else
  out="$("$ST")"; rc=$?
  echo "$out"
  sp="$(printf '%s\n' "$out" | sed -n 's/.*PASSED=\([0-9]*\).*/\1/p' | tail -1)"
  sf="$(printf '%s\n' "$out" | sed -n 's/.*FAILED=\([0-9]*\).*/\1/p' | tail -1)"
  if [ "$rc" -eq 0 ] && [ -n "$sp" ] && [ "${sf:-1}" = 0 ]; then
    PASS=$((PASS + sp))
  else
    # Count reported failures, and at least one if the binary produced nothing (neutered).
    FAIL=$((FAIL + ${sf:-1}))
    [ -n "$sp" ] && PASS=$((PASS + sp))
    [ -z "$sp$sf" ] && FAIL=$((FAIL+1))
  fi
fi

emit_ctrf "libcaption-oracle" "$PASS" "$FAIL"
