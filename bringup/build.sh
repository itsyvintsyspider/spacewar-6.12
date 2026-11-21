#!/usr/bin/env bash
# Builds the Spacewar bring-up shell (bringup/shell.c) as a static aarch64
# binary, using the kernel_platform's own clang and a vendored, fuller
# nolibc (bringup/nolibc/) -- the vendor-stripped kernel_platform/common's
# own tools/include/nolibc is missing snprintf/vsnprintf/strstr/access,
# which shell.c needs; nolibc is a self-contained, droppable header
# library by design, so a newer copy builds fine against this kernel.
#
# Usage: ./build.sh <kernel_platform> <out-dir>
set -euo pipefail

KP="$(readlink -f "$1")"
OUT="$(readlink -f "$2")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLANGBIN=$(find "$KP/prebuilts/clang" -maxdepth 4 -type d -name bin | head -1)
export PATH="$CLANGBIN:$PATH"

mkdir -p "$OUT"
clang --target=aarch64-linux-gnu -nostdlib -static -Os \
	-I "$HERE/nolibc" \
	-o "$OUT/shell" "$HERE/shell.c"

file "$OUT/shell"
echo "Built: $OUT/shell"
