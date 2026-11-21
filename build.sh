#!/usr/bin/env bash
# Builds Spacewar's out-of-tree vendor modules (display, GPU, TrustZone)
# against a Kleaf-built kernel_platform checkout.
#
# Usage: ./build.sh <kernel_platform> <vendor-checkouts-dir> <out-dir>
#
#   <kernel_platform>      path to the kernel_platform tree already built
#                          once with `python3 build_with_bazel.py -t lahaina perf`
#   <vendor-checkouts-dir> directory containing display-drivers/, mm-drivers/,
#                          graphics-kernel/, graphics-devicetree/,
#                          securemsm-kernel/ checked out at the branches/tags
#                          in README.md, with this repo's patches/ applied
#   <out-dir>              scratch dir this script creates: modules_prepare_out/
#                          and the combined soc-repo symvers file
set -euo pipefail

KP="$(readlink -f "$1")"
VENDOR="$(readlink -f "$2")"
OUT="$(readlink -f "$3")"
SOC="$KP/soc-repo"
MPO="$OUT/modules_prepare_out"
EXTRA="$OUT/soc-repo-combined.symvers"

export PATH="$KP/prebuilts/clang/host/linux-x86/clang-r563880c/bin:$PATH"

BAZEL_EXECROOT=$(find "$KP/bazel-cache" -maxdepth 3 -type d -path "*/bazel-cache/*/execroot" | head -1)/_main/bazel-out/k8-fastbuild/bin

# Kleaf's real KERNELRELEASE (what dist/ and the running kernel actually
# use) -- see the modules_prepare override below for why this has to be
# forced in rather than left to Kbuild's own setlocalversion guess.
REL=$(cat "$(find "$KP/bazel-cache" -not -path "*/sandbox_stash/*" -path "*/common/kernel_aarch64/include/config/kernel.release" -print -quit)")

# --- seed modules_prepare_out with Kleaf's own lahaina_perf config ---
mkdir -p "$MPO"
cp -a "$BAZEL_EXECROOT/soc-repo/lahaina_perf_config/out_dir/." "$MPO/"

# protected_module_names_list: the GKI module-signing config
# (CONFIG_MODULE_SIG_PROTECT_LIST) expects this at $(objtree)/, but plain
# `modules_prepare` never generates it -- Kleaf's own setup scripts only
# copy it conditionally, so a fresh out dir is missing it.
cp "$BAZEL_EXECROOT/common/kernel_aarch64_config/out_dir/protected_module_names_list" "$MPO/"

make -C "$KP/common" O="$MPO" ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang -j"$(nproc)" modules_prepare

# the dist/Module.symvers Kleaf copies out is empty; the real core-kernel
# symbol table lives in the Bazel sandbox under common/kernel_aarch64/.
cp "$BAZEL_EXECROOT/common/kernel_aarch64/Module.symvers" "$MPO/Module.symvers"

# modules_prepare computes its own KERNELRELEASE via plain Kbuild's
# setlocalversion (e.g. "6.12.81-4k-g<hash>[-dirty]"), completely
# independent of Kleaf's own Bazel-injected release string (e.g.
# "6.12.81-android16-6-maybe-dirty-4k", the one in dist/ and the one
# actually running on the device). Every module built against the
# modules_prepare value gets that wrong vermagic baked in and the running
# kernel refuses to load it -- not a staleness issue, this mismatches on
# every run regardless of how fresh modules_prepare is, since Kbuild
# never consults Kleaf's value on its own. Overwrite modules_prepare's
# generated kernel.release with Kleaf's real one before building anything
# against it; Kbuild only regenerates this file when it's older than
# common/Makefile, so this sticks for every module build below. The
# actual vermagic baked into each .ko comes from the UTS_RELEASE macro in
# include/generated/utsrelease.h though, not this file directly --
# modules_prepare already generated that header from the wrong value by
# the time we get here, and nothing regenerates it afterwards (no later
# `make modules` call re-runs the full prepare step), so both files need
# the correction or only kernel.release itself would change.
echo "$REL" > "$MPO/include/config/kernel.release"
echo "#define UTS_RELEASE \"$REL\"" > "$MPO/include/generated/utsrelease.h"

# Kleaf builds soc-repo (and common/'s own modules, e.g. qmi_helpers.ko)
# as hundreds of per-module Module.symvers files instead of one combined
# one; concatenate them for KBUILD_EXTRA_SYMBOLS. dist/ already has every
# module's symvers flattened to one directory, soc-repo's own or common's.
find "$BAZEL_EXECROOT/soc-repo/lahaina_perf" "$KP/out/msm-kernel-lahaina-perf/dist" \
	-name "*_Module.symvers" -not -path "*.runfiles*" \
	| sort -u | xargs cat | sort -u -k2,2 > "$EXTRA"

# --- display-drivers ---
make -C "$KP/common" O="$MPO" M="$VENDOR/display-drivers" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang DISPLAY_ROOT="$VENDOR/display-drivers" \
	CONFIG_ARCH_LAHAINA=y CONFIG_ARCH_YUPIK=y CONFIG_DRM_MSM=m \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	SOCINCLUDE="-I$SOC/include -I$SOC/include/uapi" \
	-j"$(nproc)" modules

# --- graphics-kernel (needs mm-drivers' hw_fence/sync_fence headers too) ---
make -C "$KP/common" O="$MPO" M="$VENDOR/graphics-kernel" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang KGSL_PATH="$VENDOR/graphics-kernel" \
	CONFIG_ARCH_LAHAINA=y CONFIG_ARCH_YUPIK=y \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	SOCINCLUDE="-I$SOC/include -I$SOC/include/uapi \
		-I$VENDOR/mm-drivers/hw_fence/include \
		-I$VENDOR/mm-drivers/sync_fence/include \
		-I$VENDOR/mm-drivers/sync_fence/include/uapi \
		-I$KP/common/drivers/devfreq" \
	-j"$(nproc)" modules

# --- securemsm-kernel (its tracepoint headers expect a sibling
#     vendor/qcom/opensource/securemsm-kernel next to kernel_platform) ---
mkdir -p "$KP/../vendor/qcom/opensource"
ln -sfn "$VENDOR/securemsm-kernel" "$KP/../vendor/qcom/opensource/securemsm-kernel"

make -C "$KP/common" O="$MPO" M="$VENDOR/securemsm-kernel" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang SSG_MODULE_ROOT="$VENDOR/securemsm-kernel" \
	CONFIG_ARCH_LAHAINA=y CONFIG_ARCH_YUPIK=y \
	CONFIG_DISABLE_TEST_MODULES=y CONFIG_QSEECOM=m \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	SOCINCLUDE="-I$SOC/include -I$SOC/include/uapi" \
	-j"$(nproc)" modules

echo "Built: $VENDOR/display-drivers/msm/msm_drm.ko"
echo "Built: $VENDOR/graphics-kernel/msm_kgsl.ko"
echo "Built: $(find "$VENDOR/securemsm-kernel" -name '*.ko' | wc -l) securemsm-kernel modules"

# --- mobile data stack (rmnet_mem, dataipa, datarmnet) ---
# dataipa/datarmnet/datarmnet-ext ship only Kleaf/Bazel ddk_module()
# definitions, no plain Kbuild -- ddk2kbuild.py (Suvojeet Sengupta's,
# chip/board-agnostic) evaluates each define_modules.bzl macro call and
# generates the Kbuild a plain `make M=` build needs. Build order matters:
# rmnet_mem's Module.symvers feeds dataipa, and both feed datarmnet.
DDK="python3 $(dirname "$0")/bringup/ddk2kbuild.py"
LAH="--set CONFIG_ARCH_LAHAINA=y --set CONFIG_ARCH_YUPIK=y"

$DDK "$VENDOR/datarmnet-ext/mem" "$VENDOR/datarmnet-ext/mem/define_mem.bzl" \
	'define_mem("lahaina", "perf")' $LAH
make -C "$KP/common" O="$MPO" M="$VENDOR/datarmnet-ext/mem" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang -j"$(nproc)" modules

D='$(src)/drivers/platform/msm'
# CONFIG_IPA_RMNET_MEM is deliberately not passed here -- dataipa's own
# Bazel module list already bakes it into several files' local_defines,
# and adding it again via ccflags-y collides with that per-file -D
# (clang treats it as -Werror,-Wmacro-redefined).
$DDK "$VENDOR/dataipa" "$VENDOR/dataipa/define_modules.bzl" \
	'define_modules("lahaina", "perf")' $LAH \
	--conf "$VENDOR/dataipa/config/dataipa_GKI.conf" \
	--only gsim --only ipam --only ipanetm \
	--cflags "-include \$(src)/config/dataipa_vendor.h -Wno-error=shift-count-overflow -I$SOC/include -I$SOC/include/uapi -I$D/include -I$D/include/linux -I$D/include/uapi -I$D/gsi -I$D/gsi/gsihal -I$D/ipa -I$D/ipa/ipa_v3 -I$D/ipa/ipa_v3/ipahal -I$D/ipa/ipa_clients -I$D/ipa/ipa_v3/dump -I$D/ipa/ipa_v3/dump/ipa5.5 -I$VENDOR/datarmnet-ext/mem -I$VENDOR/datarmnet/core"
make -C "$KP/common" O="$MPO" M="$VENDOR/dataipa" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	KBUILD_EXTRA_SYMBOLS="$VENDOR/datarmnet-ext/mem/Module.symvers $EXTRA" \
	-j"$(nproc)" modules

$DDK "$VENDOR/datarmnet" "$VENDOR/datarmnet/define_modules.bzl" \
	'define_rmnet_core_module("lahaina", "perf"); define_rmnet_ctl_module("lahaina", "perf")' $LAH \
	--set CONFIG_RMNET_CORE=m --set CONFIG_RMNET_CTL=m --set CONFIG_RMNET_LA_PLATFORM=y --set CONFIG_IPA3=y \
	--cflags "-I\$(src)/core -I$SOC/include -I$VENDOR/dataipa/drivers/platform/msm/include -I$VENDOR/dataipa/drivers/platform/msm/include/uapi -I$VENDOR/datarmnet-ext/mem"
make -C "$KP/common" O="$MPO" M="$VENDOR/datarmnet" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	KBUILD_EXTRA_SYMBOLS="$VENDOR/datarmnet-ext/mem/Module.symvers $VENDOR/dataipa/Module.symvers $EXTRA" \
	-j"$(nproc)" modules

echo "Built: $(find "$VENDOR/datarmnet-ext/mem" "$VENDOR/dataipa" "$VENDOR/datarmnet" -name '*.ko' | wc -l) mobile data stack modules"

# --- camera-kernel (Spectra ISP, camera.ko) ---
# Kbuild.spacewar (this repo's own file, adapted from Sengupta's
# Kbuild.redwood -- Qualcomm's stock lahaina camera.ko module list, minus
# the LRME node redwood's HAL needs but Nothing's doesn't) replaces the
# tree's own Makefile/Kbuild, the same swap his build-misc618.sh does.
cp "$VENDOR/camera-kernel/Kbuild.spacewar" "$VENDOR/camera-kernel/Kbuild"
rm -f "$VENDOR/camera-kernel/Makefile"
make -C "$KP/common" O="$MPO" M="$VENDOR/camera-kernel" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	CAMERA_KERNEL_ROOT="$VENDOR/camera-kernel" SOC_INCLUDE="$SOC/include" \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	-j"$(nproc)" modules

echo "Built: $(find "$VENDOR/camera-kernel" -name '*.ko' | wc -l) camera-kernel modules"

# --- wlan (WCN6750/QCA6750 Wi-Fi: icnss2 platform drivers + qcacld wlan.ko) ---
# Both trees already ship a plain Kbuild (no ddk2kbuild.py conversion
# needed here, unlike dataipa/datarmnet). phone1_defconfig confirms
# CONFIG_CNSS_QCA6750=y -- the same WCN chip as redwood, so its
# WLAN_PROFILE/qcacld build flags carry over unchanged.
P="$VENDOR/wlan/platform"
make -C "$KP/common" O="$MPO" M="$P" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	CONFIG_ICNSS2=m CONFIG_ICNSS2_QMI=y CONFIG_CNSS_UTILS=m CONFIG_CNSS_GENL=m \
	CONFIG_WCNSS_MEM_PRE_ALLOC=m CONFIG_CNSS_QMI_SVC=m CONFIG_CNSS_OUT_OF_TREE=y \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	KCFLAGS="-I$SOC/include -I$P/inc -I$P/cnss_utils -I$P/cnss2 -I$P/icnss2 -I$P/cnss_prealloc -include $P/icnss2/qcom_rproc_compat.h -Wno-error=array-bounds" \
	-j"$(nproc)" modules

Q="$VENDOR/wlan/qcacld-3.0"
make -C "$KP/common" O="$MPO" M="$Q" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	WLAN_ROOT="$Q" WLAN_PROFILE=lahaina_gki_qca6750 MODNAME=wlan BUILD_DIAG_VERSION=y \
	CONFIG_QCA_CLD_WLAN=m CONFIG_QCA_WIFI_ISOC=0 CONFIG_QCA_WIFI_2_0=1 QCA_WIFI_FTM_NL80211=y \
	KBUILD_EXTRA_SYMBOLS="$P/Module.symvers $EXTRA" \
	KCFLAGS="-I$SOC/include -I$P/inc -I$VENDOR/wlan/inc-net -include $Q/configs/kbuild_defines.h -include $Q/configs/config_to_feature.h -include $Q/configs/grep_defines_lahaina.h -Wno-macro-redefined -DWLAN_OPEN_SOURCE -Wno-error=missing-prototypes -Wno-error=unused-variable -Wno-error=unused-but-set-variable" \
	-j"$(nproc)" modules

echo "Built: $(find "$VENDOR/wlan" -name '*.ko' | wc -l) wlan modules"

# --- msm_ext_display (mm-drivers; audio-kernel's HDMI/DP codec needs its
#     msm_ext_disp_register_audio_codec() etc., exported from this module) ---
EXTDISP="$VENDOR/mm-drivers/msm_ext_display"
make -C "$KP/common" O="$MPO" M="$EXTDISP" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	CONFIG_ARCH_LAHAINA=y CONFIG_ARCH_YUPIK=y CONFIG_MSM_EXT_DISPLAY=m \
	-j"$(nproc)" modules

# --- audio-kernel (ADSP/Q6, Bolero macros, WCD codecs, SoundWire) ---
# audio-kernel only ships a Bazel registry for lahaina; audiokbuild.py
# (Sengupta's, audio-specific -- its own audio_modules.bzl shape doesn't
# fit the generic ddk2kbuild.py) generates the Kbuild from it.
rm -f "$VENDOR/audio-kernel/Makefile"
python3 "$(dirname "$0")/bringup/audiokbuild.py" "$VENDOR/audio-kernel"
make -C "$KP/common" O="$MPO" M="$VENDOR/audio-kernel" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	KBUILD_EXTRA_SYMBOLS="$EXTRA $EXTDISP/Module.symvers" \
	KCFLAGS="-I$SOC/include -I$SOC/include/uapi -I$EXTDISP/include -Wno-array-bounds" \
	-j"$(nproc)" modules

echo "Built: $(find "$VENDOR/audio-kernel" -name '*.ko' | wc -l) audio-kernel modules"

# --- tfa98xx (NXP/Goodix smart speaker amplifier) ---
# Spacewar's stock 5.4 techpack/audio/asoc/codecs/tfa98xx (CONFIG_SND_SOC_TFA98XX,
# i2c compatible "tfa,tfa98xx" + per-chip variants) is the old, Qualcomm-
# techpack-embedded version of this same driver. We import the actively
# maintained upstream fork (github.com/Goodix-vas/tfa98xx) instead -- same
# 4 source files (tfa98xx.c/tfa_container.c/tfa_dsp.c/tfa_init.c), cleaner
# inc/+src/ layout, and it's fully self-contained (no msm/qcom/audio-kernel
# symbol deps at all -- confirmed by grep and by modpost resolving every
# undefined symbol straight from the base kernel), so it builds as its own
# standalone module here rather than inside audio-kernel's own Kbuild tree.
# Its own Makefile is already Kbuild-compatible (same `ifneq($(KERNELRELEASE),)`
# shape every other M= build here uses) -- no ddk2kbuild.py-style conversion
# needed, just -I.../inc via KCFLAGS (the tree's own EXTRA_CFLAGS computes
# this via $(realpath -f ...), which isn't real `make` syntax and silently
# resolves to nothing).
#
# Real 6.12 API-break fixes applied directly to the imported source (not
# speculative -- each confirmed against this kernel's own headers):
#   - i2c_driver.probe dropped its `const struct i2c_device_id *id` arg
#     (unused by this driver anyway) and .remove is now void-returning.
#   - struct snd_soc_dai_driver's symmetric_rates/symmetric_samplebits
#     fields were renamed to symmetric_rate/symmetric_sample_bits.
#   - FW_ACTION_HOTPLUG was renamed to FW_ACTION_UEVENT (same value).
#   - GPIOF_DIR_IN was renamed to GPIOF_IN; devm_gpio_free() was removed
#     outright (devm_gpio_request_one()'s own devres cleanup already frees
#     the GPIO on device teardown, so the explicit calls in i2c_remove()
#     were redundant, not a real gap -- just deleted).
#   - SLAB_MEM_SPREAD was removed (had been a no-op for years before
#     removal) -- dropped from the kmem_cache_create() flags.
# Two genuine upstream (not kernel-version-related) bugs also fixed, both
# confirmed by reading the surrounding code rather than guessed:
#   - tfa_container.c's tfaContBfEnumByNameRevid() had an exact duplicate
#     `case 0x61`/`case 0x63` pair (copy-paste), which is a hard C error
#     (duplicate case value), not just a warning -- removed the dead repeat.
#   - tfa_dsp.c's tfatfd_irq_info[] debug-name table had the same two
#     entries ("Qpump fail"/"Overvoltage protection") pasted in twice,
#     missing a comma between them (string-literal concatenation) *and*
#     outnumbering the real 14-entry tfd1015_irq enum by one -- removed
#     the duplicate pair instead of just adding the comma, since adding
#     only the comma would've left the table at the wrong length and
#     silently misnamed every IRQ bit from "Undervoltage VDDP" onward.
#   - tfa_dev_start()/tfa_dev_stop()/tfa_dev_set_state()/tfa_dev_mtp_set()
#     are declared returning the newer `enum tfa_error` but their bodies
#     use the older `enum Tfa98xx_Error` throughout (an incomplete
#     upstream refactor) -- the two enums' values genuinely diverge past
#     index 2, so this was already a latent correctness issue, not
#     something introduced by porting. Added explicit casts at exactly
#     the crossing points (the same casts the implicit conversion was
#     already silently doing) rather than redesigning the enum taxonomy,
#     which is out of scope for a kernel port.
TFA="$VENDOR/tfa98xx"
make -C "$KP/common" O="$MPO" M="$TFA" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	CONFIG_SND_SOC_TFA98XX=m \
	KCFLAGS="-I$TFA/inc" \
	-j"$(nproc)" modules

echo "Built: $TFA/snd-soc-tfa98xx.ko"

# --- cvp-kernel (Qualcomm EVA/CVP video-codec coprocessor) + its real
#     dependency chain, all enabled by Qualcomm's own lahaina.bzl:
#     synx-kernel (cross-core sync fences), dsp-kernel's frpc-adsprpc
#     (ADSP RPC, msm-cvp.ko needs none of its other modules), mmrm-driver
#     (MM resource manager). None of these four trees exist in Sengupta's
#     redwood-6.18-modules (he doesn't build CVP at all) -- a from-scratch
#     port. cvp-kernel's own Kbuild/Makefile is stale (only supports
#     waipio and references source files that no longer exist), so it
#     needs ddk2kbuild.py the same as dataipa/datarmnet, just against its
#     eva_modules.bzl/eva_module_build.bzl registry shape instead of a
#     flat define_modules() -- ddk2kbuild.py's Starlark-emulation env
#     needed three generic fixes for this shape (struct()/type() were
#     stubbed wrong for real Python, native.glob() and
#     kernel_module_group were missing, load() was a no-op) rather than
#     anything cvp-specific.
SYNX="$VENDOR/synx-kernel"
DSP="$VENDOR/dsp-kernel"
MMRM="$VENDOR/mmrm-driver"
CVP="$VENDOR/cvp-kernel"

# synx-kernel: same stale-Kbuild situation as cvp-kernel (its plain Kbuild
# references synx_global.c/synx_compat.c/ipclite.c etc., none of which
# exist in this checkout -- synx_modules.bzl's srcs list is the real one).
$DDK "$SYNX" "$SYNX/synx_modules.bzl" \
	'define_target_variant_modules("lahaina", "perf", synx_modules, ["synx-driver"], ["TARGET_SYNX_ENABLE"])'
make -C "$KP/common" O="$MPO" M="$SYNX" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	KCFLAGS="-I$SOC/include -I$SYNX/include -I$SYNX/include/uapi -I$SYNX/include/uapi/synx/media -I$VENDOR/mm-drivers/hw_fence/include" \
	-j"$(nproc)" modules

# dsp-kernel: real plain Kbuild, no board gating needed for lahaina. Its
# fastrpc_trace.h is found via a hardcoded .../vendor/qcom/opensource/
# dsp-kernel/ relative path, same sibling-symlink trick as securemsm-kernel.
# Only frpc-adsprpc.ko is built -- cdsp-loader.ko has a real 6.12
# platform_driver.remove() API break and is commented out of Qualcomm's
# own board module list anyway, so it's not needed.
mkdir -p "$KP/../vendor/qcom/opensource"
ln -sfn "$DSP" "$KP/../vendor/qcom/opensource/dsp-kernel"
make -C "$KP/common" O="$MPO" M="$DSP" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang DSP_ROOT="$DSP" \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	KCFLAGS="-I$SOC/include" \
	-j"$(nproc)" frpc-adsprpc.ko

# mmrm-driver: real plain Kbuild; CONFIG_MSM_MMRM=y is generic (not
# actually waipio-specific despite the config file's name).
make -C "$KP/common" O="$MPO" M="$MMRM" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang MMRM_ROOT="$MMRM" CONFIG_MSM_MMRM=y \
	KBUILD_EXTRA_SYMBOLS="$EXTRA" \
	KCFLAGS="-I$SOC/include" \
	-j"$(nproc)" modules

# cvp-kernel itself. msm_cvp_core.h/msm_smem.c/msm_cvp_buf.h's
# `#include <linux/ion.h>` resolves to soc-repo's *uapi* ion.h (not a
# kernel-side ION driver, which 6.12 doesn't have) once -I.../include/uapi
# is on the path -- they only use it for the ION_FLAG_CACHED/SECURE
# constants, not any real ION driver API.
$DDK "$CVP" "$CVP/eva_modules.bzl" \
	'define_target_variant_modules("lahaina", "perf", eva_modules, ["msm-cvp"], ["TARGET_SYNX_ENABLE","TARGET_DSP_ENABLE","TARGET_MMRM_ENABLE","CONFIG_EVA_CANOE","CONFIG_MSM_MMRM"])'
make -C "$KP/common" O="$MPO" M="$CVP" \
	ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
	KBUILD_EXTRA_SYMBOLS="$SYNX/Module.symvers $DSP/Module.symvers $MMRM/Module.symvers $EXTRA" \
	KCFLAGS="-I$SOC/include -I$SOC/include/uapi -I$CVP/include -I$CVP/include/uapi -I$CVP/include/uapi/eva -I$SYNX/include -I$SYNX/include/uapi -I$SYNX/include/uapi/synx/media -I$SYNX/msm/synx -I$DSP/include/linux -I$DSP/include/uapi -I$MMRM/driver/inc -I$MMRM/driver/inc/internal" \
	-j"$(nproc)" modules

echo "Built: $(find "$SYNX" "$DSP" "$MMRM" "$CVP" -name '*.ko' | wc -l) cvp-kernel + dependency modules"
