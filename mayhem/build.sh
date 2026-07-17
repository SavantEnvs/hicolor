#!/usr/bin/env bash
# hicolor/mayhem/build.sh — build the `hicolor` CLI (cli.c + the single-header hicolor.h library) as
# the FILE-INPUT fuzz target, plus a clean normal-flags build of the same CLI for hicolor's OWN Tcl
# tcltest suite (tests/hicolor.test, run by mayhem/test.sh).
#
# hicolor is a tiny C99 program: cli.c #defines HICOLOR_IMPLEMENTATION and #includes hicolor.h (the
# whole 15/16-bit-color HiColor encoder/decoder library), linking against libpng + zlib. The Mayhem
# target is FILE-INPUT (CLI): `hicolor encode @@ /dev/null` feeds the fuzz bytes as a PNG to the
# `encode` command, exercising libpng's PNG reader AND hicolor's own quantize/header-write code on
# the decoded pixels. (`encode` was the original mayhemheroes integration's target — preserved here
# so Mayhem run history stays continuous.) No libFuzzer harness: the natural fuzz surface is the CLI
# itself on a file, like lacc.
#
# Two builds from the same in-tree source (the Makefile builds `hicolor` in the repo root, so they
# can't coexist — build the test oracle first, stash it, then the sanitized target):
#   (1) NORMAL-flags build -> /mayhem/build-tests/hicolor  (honest oracle for test.sh; no sanitizer noise)
#   (2) SANITIZED build     -> /mayhem/hicolor             (the file-input Mayhem target)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty
# value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the program's natural crash).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# libpng / zlib link + compile flags from pkg-config (libpng-dev + zlib1g-dev installed in the image).
PNG_CFLAGS="$(pkg-config --cflags libpng zlib)"
PNG_LIBS="$(pkg-config --libs libpng zlib) -lm"

BASE_CFLAGS="-std=c99 -Wall -Wextra $PNG_CFLAGS"

# ---------------------------------------------------------------------------
# (1) TEST build — hicolor's OWN flags, NO sanitizer. This is the honest oracle that test.sh runs;
#     keeping it sanitizer-free avoids ASan/UBSan noise in the functional suite. Stashed under
#     build-tests/ before the sanitized build overwrites ./hicolor.
# ---------------------------------------------------------------------------
rm -f hicolor
$CC cli.c -o hicolor $BASE_CFLAGS $DEBUG_FLAGS -O2 $PNG_LIBS
mkdir -p "$SRC/build-tests"
cp -f hicolor "$SRC/build-tests/hicolor"
echo "build.sh: test-oracle hicolor -> $SRC/build-tests/hicolor"

# ---------------------------------------------------------------------------
# (2) FUZZ build — the CLI compiled WITH $SANITIZER_FLAGS so the FUZZED CODE (cli.c + hicolor.h's
#     parser/quantizer, and the libpng reader path) is instrumented (ASan+UBSan, halting, default).
#     The file-input Mayhem target lands at /mayhem/hicolor.
#
#     We also link mayhem/asan_default_options.c, which bakes a weak __asan_default_options =
#     "detect_leaks=0" into the binary: hicolor's run-once CLI deliberately doesn't free every
#     allocation before exit, so leak detection would fire on nearly every input and bury the real
#     memory-safety bugs. (Only meaningful when ASan is in the flags; harmless otherwise.)
# ---------------------------------------------------------------------------
ASAN_OPTS_SRC=""
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  ASAN_OPTS_SRC="mayhem/asan_default_options.c"
fi

rm -f hicolor
$CC cli.c $ASAN_OPTS_SRC -o /mayhem/hicolor $BASE_CFLAGS $SANITIZER_FLAGS $DEBUG_FLAGS $PNG_LIBS

echo "build.sh: built /mayhem/hicolor (sanitized file-input fuzz target) and $SRC/build-tests/hicolor (test oracle)"
ls -l /mayhem/hicolor "$SRC/build-tests/hicolor"
