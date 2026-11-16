def register_modules(registry):
    registry.register(
        name = "drivers/input/touchscreen/cap1296",
        out = "cap1296.ko",
        config = "CONFIG_TOUCHSCREEN_CAP1296",
        srcs = [
            # do not sort
            "drivers/input/touchscreen/cap1296.c",
            "drivers/input/touchscreen/cap1296.h",
        ],
    )

    registry.register(
        name = "drivers/input/touchscreen/focaltech_nothing/fts_tp",
        out = "fts_tp.ko",
        config = "CONFIG_TOUCHSCREEN_NOTHING",
        srcs = [
            # do not sort
            "drivers/input/touchscreen/focaltech_nothing/focaltech_core.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_core.h",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_common.h",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_config.h",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_ex_fun.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_ex_mode.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_gesture.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_esdcheck.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_point_report_check.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_flash.c",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_flash.h",
            "drivers/input/touchscreen/focaltech_nothing/focaltech_spi.c",
            "drivers/input/touchscreen/focaltech_nothing/include/firmware/FT3680_WXN_M146_V27_D01_20220706_app.h",
            "drivers/input/touchscreen/focaltech_nothing/include/firmware/fw_sample.h",
        ],
        deps = [
            # do not sort
            "drivers/soc/qcom/panel_event_notifier",
        ],
    )
