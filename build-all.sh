#!/usr/bin/env bash
# Kernel + in-tree vendor drivers + out-of-tree vendor techpacks in one run.
#
# Usage: ./build-all.sh <kernel_platform> <modules-6.12 checkout> <out-dir>
#
# Stages every .ko (Kleaf dist and techpacks) in <out-dir>/stage and writes
# <out-dir>/modules.load in dependency order.
set -euo pipefail
KP="$(readlink -f "$1")"; MODS="$(readlink -f "$2")"; OUT="$(readlink -f "$3")"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"

(cd "$KP" && python3 build_with_bazel.py -t lahaina perf)
"$HERE/build.sh" "$KP" "$MODS" "$OUT"

REL=$(cat "$OUT/modules_prepare_out/include/config/kernel.release")
STAGE="$OUT/stage"; MDIR="$STAGE/lib/modules/$REL"
rm -rf "$STAGE"; mkdir -p "$MDIR"
find "$KP/out/msm-kernel-lahaina-perf/dist" "$MODS" -name '*.ko' -exec cp -f {} "$MDIR/" \;
depmod -b "$STAGE" "$REL"

python3 - "$MDIR" > "$OUT/modules.load" <<'PY'
import sys, os
d = sys.argv[1]
deps = {}
for line in open(os.path.join(d, "modules.dep")):
    mod, _, rest = line.partition(":")
    deps[os.path.basename(mod)] = [os.path.basename(x) for x in rest.split()]
done, order = set(), []
def visit(m):
    if m in done:
        return
    done.add(m)
    for x in deps.get(m, []):
        visit(x)
    order.append(m)
for m in sorted(deps):
    visit(m)
print("\n".join(order))
PY
echo "Staged $(ls "$MDIR"/*.ko | wc -l) modules for $REL; load order in $OUT/modules.load"
