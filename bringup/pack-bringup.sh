#!/usr/bin/env bash
# Bring-up images for Spacewar's 6.12 kernel: the kernel_platform's own
# Image with a ramdisk that holds only the bring-up shell (bringup/shell.c)
# and the first-stage modules, plus the slot's own vendor_boot header/
# cmdline/dtb (left unmodified: it's SoC-base-level only, not where the
# board overlay lives) and this build's own dtbo.img. The real board
# overlay (yupik-spacewar-overlay.dtbo, validated to merge onto yupik.dtb
# cleanly -- see devicetree_nothing_sm7325-6.12) is one of the 53 entries
# already bundled into that dtbo.img; the bootloader picks it by the real
# board-id/msm-id it reads off the hardware, same as a normal boot.
#
# Unlike redwood's pack-bringup618.sh, this kernel_platform is Kleaf/Bazel-
# built, not plain `make modules_install`: `python3 build_with_bazel.py -t
# lahaina perf` already stages Image, vendor_boot.img, every built .ko
# flat, and modules.dep/modules.load/vendor_boot.modules.load under
# out/msm-kernel-lahaina-perf/dist/, so this script reads from there
# directly instead of running its own modules_install.
#
# Usage: ./pack-bringup.sh <kernel_platform> <slot's vendor_boot.img> <out-dir>
set -euo pipefail

KP="$(readlink -f "$1")"
VBOOT="$(readlink -f "$2")"
OUT="$(readlink -f "$3")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$KP/out/msm-kernel-lahaina-perf/dist"
W="$OUT/pack"

UNPACK=(python3 "$KP/tools/mkbootimg/unpack_bootimg.py")
MK=(python3 "$KP/tools/mkbootimg/mkbootimg.py")
# -print -quit (not `| head -1`) so find never writes a second match into a
# pipe head already closed -- a rebuild can leave more than one match (a
# real output path plus a stale sandbox_stash copy from the same action),
# and head -1 closing early on the first SIGPIPEs find under pipefail.
REL=$(cat "$(find "$KP/bazel-cache" -not -path "*/sandbox_stash/*" -path "*/common/kernel_aarch64/include/config/kernel.release" -print -quit 2>/dev/null)")

# $DIST (Kleaf's own board/GKI output) is only half the picture: the nine
# vendor techpacks modules-repo/build.sh builds -- including display-
# drivers' msm_drm.ko, the entire reason for this bring-up test -- land in
# clo-vendor-6.12, a sibling of clo-platform-6.12, never in $DIST. This
# script has only ever read from $DIST, so msm_drm.ko has never once made
# it onto a bring-up ramdisk. Pool every .ko from both pipelines into one
# staging tree and run depmod over it for real cross-pipeline dependency
# resolution (msm_drm.ko's own deps -- llcc-qcom, qcom-scm, clk-qcom, etc.
# -- are dist-built; depmod resolves that correctly, $DIST/modules.dep
# alone never could since it doesn't know msm_drm.ko exists).
VENDOR="$(dirname "$(dirname "$KP")")/clo-vendor-6.12"

rm -rf "$W"; mkdir -p "$W"
POOL="$W/pool/lib/modules/${REL:-$(uname -r)}"
mkdir -p "$POOL"
declare -A KOPATH
while IFS= read -r f; do
	KOPATH["$(basename "$f")"]="$f"
	cp "$f" "$POOL/"
done < <(find "$DIST" "$VENDOR" -maxdepth 6 -name "*.ko")
depmod -b "$W/pool" "${REL:-$(uname -r)}"
DEP="$POOL/modules.dep"
echo "module pool: ${#KOPATH[@]} .ko total ($(find "$DIST" -maxdepth 1 -name "*.ko" | wc -l) dist, $(find "$VENDOR" -maxdepth 6 -name "*.ko" | wc -l) vendor)"
"${UNPACK[@]}" --boot_img "$VBOOT" --out "$W/vb" >/dev/null

"$HERE/build.sh" "$KP" "$W"

# First stage list: the slot's own modules.load, minus what our build
# doesn't ship (no vermagic match otherwise). Spacewar's real vendor_boot
# ramdisk is gzip, not lz4 (redwood's board used lz4, confirmed by
# actually unpacking a real vendor_boot_stock.img from the device's own
# C5.0 release) -- detect by magic bytes rather than assuming either.
mkdir -p "$W/vr"
VR="$W/vb/vendor_ramdisk00"
[ -f "$VR" ] || VR="$W/vb/vendor_ramdisk"
case "$(head -c2 "$VR" | xxd -p)" in
1f8b) DECOMP="gzip -dc" ;;
*) DECOMP="lz4 -dc" ;;
esac
(cd "$W/vr" && $DECOMP "$VR" | cpio -id --quiet)
# Spacewar's real vendor_ramdisk has a short top-level lib/modules/
# modules.load (just msm_drm.ko, a late/display-only list) and the real
# first-stage list nested under lib/modules/5.4-gki/modules.load (ufs-
# qcom, pinctrl, smmu, clocks, etc.) -- pick whichever modules.load has
# the most entries rather than assuming the top-level path, since that's
# the one that's actually useful for bring-up.
LOAD=""
while IFS= read -r f; do
	[ -z "$LOAD" ] && LOAD="$f"
	[ "$(wc -l < "$f")" -gt "$(wc -l < "$LOAD")" ] && LOAD="$f"
done < <(find "$W/vr/lib/modules" -name "modules.load")
[ -n "$LOAD" ] || { echo "no modules.load anywhere under lib/modules in the vendor ramdisk"; exit 1; }
echo "using $LOAD ($(wc -l < "$LOAD") entries)"

# Ramdisk: shell + modules flat in lib/modules/<release>
RD="$W/rd"; MD="$RD/lib/modules/${REL:-$(uname -r)}"
mkdir -p "$MD" "$RD/dev" "$RD/proc" "$RD/sys"
cp "$W/shell" "$RD/init"; chmod 755 "$RD/init"
# Entry points: the slot's own first-stage list (ufs-qcom etc, listed by
# name in modules.load so shell.c's load_list() calls load() on them) plus
# dwc3-msm/its USB3 PHY, which that list never names at all (the real
# Android boot loads USB peripheral drivers much later, from a late-stage
# modules.load this script never reads; shell.c needs them for its own
# gadget_up()). Either way, naming a module isn't enough on its own: the
# slot's list was generated against the 5.4 kernel's dependency graph, not
# this 6.12 build's -- found the hard way when ufs-qcom.ko itself turned
# out to be missing three of its own real deps (qcom_ice, sched-walt,
# socinfo) that the stock list never names, so load("ufs-qcom.ko") was
# failing from shell.c's very first line regardless of anything else.
# Compute the real transitive closure from $DIST/modules.dep for every
# entry point instead of trusting either list to be complete.
: > "$W/missing.txt"; : > "$MD/modules.load"
ENTRY=()
while read -r m; do
	if [ -n "${KOPATH[$m]:-}" ]; then
		ENTRY+=("$m")
		echo "$m" >> "$MD/modules.load"
	else
		echo "$m" >> "$W/missing.txt"
	fi
done < "$LOAD"
# msm_drm.ko: not in any slot's modules.load (it's a vendor-pipeline
# module the slot's own 5.4 list never names), but the actual point of
# this bring-up test -- added explicitly rather than relying on the USB
# entry points above to pull it in, since nothing else depends on it.
EXTRA="dwc3-msm.ko phy-msm-ssusb-qmp.ko msm_drm.ko"
for m in $EXTRA; do
	ENTRY+=("$m")
	grep -qxF "$m" "$MD/modules.load" || echo "$m" >> "$MD/modules.load"
done

declare -A seen
work=("${ENTRY[@]}")
while [ "${#work[@]}" -gt 0 ]; do
	m="${work[0]}"; work=("${work[@]:1}")
	[ -n "${seen[$m]:-}" ] && continue
	seen[$m]=1
	# depmod writes bare "mod.ko: dep.ko ..." lines for our flat $POOL
	# (no subdirs to prefix with a path), unlike $DIST/modules.dep's own
	# path-prefixed format -- match either so this works against both.
	deps=$(grep -E "(^|/)$m:" "$DEP" | sed -E "s#^[^:]*:##; s#[^ ]*/([^ ]+)#\1#g") || true
	for d in $deps; do work+=("$d"); done
done
for m in "${!seen[@]}"; do
	[ -f "$MD/$m" ] && continue
	f="${KOPATH[$m]:-}"
	[ -n "$f" ] && [ -f "$f" ] && cp "$f" "$MD/"
done
# modules.dep with bare names, as shell.c's read_deps() wants them
sed -E "s#[^ :]*/##g" "$DEP" > "$MD/modules.dep"
echo "entry points: $(wc -l < "$MD/modules.load") listed, $(wc -l < "$W/missing.txt") of the slot's not built here"
echo "full closure: $(for m in "${!seen[@]}"; do [ -f "$MD/$m" ] && echo x; done | wc -l)/${#seen[@]} copied," \
	"$(ls "$MD"/*.ko 2>/dev/null | wc -l) .ko files on the ramdisk"
(cd "$RD" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet) | lz4 -l -12 --favor-decSpeed -q > "$W/ramdisk.lz4"

# vendor_boot: the slot's own header/cmdline, unmodified, but NOT the
# slot's own dtb -- our dtbo overlay's fragments (&ramoops_mem etc) target
# labels that only exist in this build's own base devicetree. Reusing the
# stock vendor_boot's real dtb left those phandle references unresolved
# (confirmed: grepping the stock dtb's decompiled source for "ramoops_mem"
# gets zero matches, despite it being a real label in ours), which
# silently made the bootloader abort the whole boot attempt before ever
# reaching the kernel -- every "stuck in fastboot" result all session,
# regardless of what was actually in the overlay. Swap in $DIST/yupik.dtb,
# the matching base this overlay was built against, keeping everything
# else from the slot's own vendor_boot as-is.
VARGS=$("${UNPACK[@]}" --boot_img "$VBOOT" --out "$W/vb" --format=mkbootimg)
eval "set -- $VARGS"
args=(); while [ $# -gt 0 ]; do
	case "$1" in
	--vendor_boot) shift 2 ;;
	--dtb) shift 2 ;;
	*) args+=("$1"); shift ;;
	esac
done
args+=(--dtb "$DIST/yupik.dtb")
"${MK[@]}" "${args[@]}" --vendor_boot "$W/vendor_boot.img"

# boot: our Image and the bring-up ramdisk; BOOTARGS lets this RAM-boot
# work regardless of which vendor_boot/dtb the active slot actually has.
# --header_version matters: mkbootimg.py defaults to 0 (the legacy
# pre-Android-9 monolithic layout), but this device's own real boot.img
# (confirmed via unpack_bootimg.py --format=mkbootimg against the stock
# C5.0 release) uses header v3 -- a different field layout entirely. With
# the default, the bootloader was very likely misreading our header (or
# never locating the ramdisk at all), which would explain every earlier
# attempt staying completely silent regardless of what was actually on
# the ramdisk.
args=(--kernel "$DIST/Image" --ramdisk "$W/ramdisk.lz4" --header_version 3)
[ -n "${BOOTARGS:-}" ] && args+=(--cmdline "$BOOTARGS")
"${MK[@]}" "${args[@]}" --output "$W/boot.img"

# Not a plain copy of $DIST/dtbo.img: Kleaf's dtbo rule has no attribute
# for mkdtimg's page_size (it only reads it from an $MKDTIMG_FLAGS env var
# the sandboxed genrule action never receives), so it silently falls back
# to mkdtimg's own default of 2048 -- but this device's real stock
# dtbo.img (confirmed by dumping it) uses 4096, and a mismatched page_size
# means the bootloader reads every entry after the first at the wrong
# offset. Repack with the real page_size ourselves instead of patching
# Kleaf's own framework file. Also: our board's msm-id/board-id is
# deliberately identical to the stock yupik-qrd-overlay.dtbo (same reason
# noted in yupik-spacewar-overlay.dtso itself), so a dtbo.img carrying
# every stock board next to ours leaves which one the bootloader picks on
# an ID match ambiguous -- for a RAM-boot test of this one device, pack
# our overlay alone so there's nothing else for it to match.
"$KP/prebuilts/kernel-build-tools/linux-x86/bin/mkdtimg" create "$W/dtbo.img" --page_size=4096 "$DIST/yupik-spacewar-overlay.dtbo"

ls -la "$W/boot.img" "$W/vendor_boot.img" "$W/dtbo.img"
sha256sum "$W/boot.img" "$W/vendor_boot.img" "$W/dtbo.img"
echo
echo "Never flashed automatically. To test on the device yourself:"
echo "  fastboot flash vendor_boot $W/vendor_boot.img"
echo "  fastboot flash dtbo $W/dtbo.img"
echo "  fastboot boot $W/boot.img"
echo "vendor_boot.img DOES need flashing this time, not just dtbo.img: it"
echo "carries our own base dtb (dtbo.img's overlay targets labels that"
echo "only exist there, not in the slot's real stock dtb), with the"
echo "slot's own cmdline/ramdisk otherwise left as-is. boot.img already"
echo "embeds both the kernel and the bring-up ramdisk, so fastboot refuses"
echo "a second file alongside it (\"cannot boot a boot.img *and* ramdisk\")"
echo "-- pass boot.img alone to the boot command."
