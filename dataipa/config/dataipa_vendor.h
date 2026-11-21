/* SPDX-License-Identifier: GPL-2.0-only */
/*
* Copyright (c) 2021, The Linux Foundation. All rights reserved.
* Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
*/

#define CONFIG_GSI 1
#define CONFIG_IPA3 1
#define CONFIG_RMNET_IPA3 1
#define CONFIG_RNDIS_IPA 1
#define CONFIG_IPA_WDI_UNIFIED_API 1
#define CONFIG_IPA_VENDOR_DLKM 1
#define CONFIG_IPA3_REGDUMP 1
#define CONFIG_IPA3_REGDUMP_IPA_5_5 1
#define CONFIG_IPA_KERNEL_TESTS_MODULE 1
#define CONFIG_NCM_IPA 1

/*
 * qcom_scm_mem_protect_region_id() and qcom_scm_get_sec_dump_state() are
 * real, exported functions -- but only from soc-repo's own qcom-scm.ko,
 * whose richer qcom_scm.h never wins the #include search against the base
 * kernel's own (incomplete) linux/firmware/qcom/qcom_scm.h at the same
 * relative path, since LINUXINCLUDE's -I always precedes ccflags-y's.
 * Declared here instead of fighting include order; the real symbols come
 * from soc-repo's qcom-scm via build.sh's KBUILD_EXTRA_SYMBOLS.
 */
#include <linux/types.h>
extern int qcom_scm_mem_protect_region_id(phys_addr_t paddr, size_t size);
extern int qcom_scm_get_sec_dump_state(u32 *dump_state);
