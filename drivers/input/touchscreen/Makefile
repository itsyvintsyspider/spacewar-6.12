# SPDX-License-Identifier: GPL-2.0

ccflags-y += -I$(src)

obj-$(CONFIG_TOUCHSCREEN_CAP1296) += cap1296.o

fts_tp-y += focaltech_nothing/focaltech_core.o
fts_tp-y += focaltech_nothing/focaltech_ex_fun.o
fts_tp-y += focaltech_nothing/focaltech_ex_mode.o
fts_tp-y += focaltech_nothing/focaltech_gesture.o
fts_tp-y += focaltech_nothing/focaltech_esdcheck.o
fts_tp-y += focaltech_nothing/focaltech_point_report_check.o
fts_tp-y += focaltech_nothing/focaltech_flash.o
fts_tp-y += focaltech_nothing/focaltech_spi.o

obj-$(CONFIG_TOUCHSCREEN_NOTHING) += fts_tp.o

