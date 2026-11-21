/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * qcom_register_early_ssr_notifier()/qcom_unregister_early_ssr_notifier()
 * are real, exported functions -- but only from soc-repo's own extended
 * drivers/remoteproc/qcom_common.c, whose richer qcom_rproc.h never wins
 * the #include search against the base kernel's own (incomplete) copy at
 * the same relative path (linux/remoteproc/qcom_rproc.h), since
 * LINUXINCLUDE's -I always precedes ccflags-y's/KCFLAGS'. Declared here
 * instead of fighting include order; the real symbols come from
 * soc-repo's own build via build.sh's KBUILD_EXTRA_SYMBOLS ($EXTRA).
 */
#ifndef __ICNSS2_QCOM_RPROC_COMPAT_H
#define __ICNSS2_QCOM_RPROC_COMPAT_H

/*
 * Forward-declared only, not #include'd -- this file is force-included
 * (-include) at the very top of each TU, ahead of the kernel's own
 * compiler_types.h/printk.h setup and each .c file's own pre-include
 * "#define pr_fmt(...)" idiom. Pulling in qcom_rproc.h/notifier.h here
 * previously broke both (undeclared "bool", redefined pr_fmt).
 */
struct notifier_block;

void *qcom_register_early_ssr_notifier(const char *name, struct notifier_block *nb);
int qcom_unregister_early_ssr_notifier(void *notify, struct notifier_block *nb);

#endif
