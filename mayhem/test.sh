#!/usr/bin/env bash
# hicolor/mayhem/test.sh — RUN hicolor's OWN functional suite (tests/hicolor.test) against the
# normal-flags `hicolor` that mayhem/build.sh produced → CTRF. PATCH-grade oracle: never compiles.
#
# tests/hicolor.test is a Tcl `tcltest` suite that drives the real `hicolor` CLI and asserts
# BEHAVIOR / KNOWN ANSWERS, not merely exit status:
#   * encode-2.* assert `hicolor info <encoded>` prints the exact version+dimensions ("5 640 427",
#     "6 640 427") for each -5/-6/--15-bit/--16-bit flag combination — i.e. the encoder produced a
#     HiColor file with the correct header.
#   * data-integrity-* round-trip encode→decode and compare the result to the original with
#     GraphicsMagick (`gm compare -metric rmse`), asserting the RMSE is within a tight band — a true
#     differential / golden-output check of the quantizer+codec math.
#   * encode-3.*/decode-1.*/quantize-2.* assert the exact error message on malformed input.
# A no-op / `exit(0)` "patch" to hicolor emits no/garbage output and FAILS these asserted-output and
# RMSE checks, so it cannot reward-hack this oracle.
#
# The `gm`-constrained data-integrity tests run only when GraphicsMagick is present (installed in the
# image); tcltest reports them as Skipped otherwise — counted as skipped, never as failures.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

HICOLOR="$SRC/build-tests/hicolor"
[ -x "$HICOLOR" ] || { echo "missing $HICOLOR — run mayhem/build.sh first" >&2; emit_ctrf "tcltest" 0 1 0; exit 2; }
command -v tclsh >/dev/null 2>&1 || { echo "tclsh not found" >&2; emit_ctrf "tcltest" 0 1 0; exit 2; }

# Point the suite at the normal-flags oracle binary (tests/hicolor.test honors $HICOLOR_COMMAND).
# tcltest's cleanupTests prints a summary line: "<file>:  Total N  Passed P  Skipped S  Failed F".
out="$(HICOLOR_COMMAND="$HICOLOR" tclsh "$SRC/tests/hicolor.test" 2>&1)"; rc=$?
echo "$out"

summary="$(printf '%s\n' "$out" | grep -E 'Total[[:space:]]+[0-9]+.*Passed' | tail -1)"
passed=$( printf '%s\n' "$summary" | sed -n 's/.*Passed[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p')
skipped=$(printf '%s\n' "$summary" | sed -n 's/.*Skipped[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p')
failed=$( printf '%s\n' "$summary" | sed -n 's/.*Failed[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p')
: "${passed:=0}" "${skipped:=0}" "${failed:=0}"

# If we couldn't parse a summary at all, treat the run's exit code as the verdict (fail loudly).
if [ -z "$summary" ]; then
  echo "test.sh: could not parse tcltest summary (rc=$rc)" >&2
  emit_ctrf "tcltest" 0 1 0
  exit 1
fi

echo "hicolor tcltest: passed=$passed failed=$failed skipped=$skipped" >&2
emit_ctrf "tcltest" "$passed" "$failed" "$skipped"
