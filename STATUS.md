# Spacewar 6.12 status

Last updated 2026-11-25. Verified on build 53.

| Area | State | Notes |
|---|---|---|
| Boot to userspace | ✅ | Normal boot, `eng` build |
| Remoteprocs | ✅ | ADSP, CDSP, MPSS and WPSS run |
| Wi-Fi | ✅ | WCN6750, 802.1X works. Multicast DMS MAC ignored, qcacld generates one |
| IPA / rmnet | 🟡 | IPA inits, `rmnet_ipa0` exists. No data session yet |
| RIL, SIM | 🟡 | Seccomp kills fixed. `qcrilNrd` now aborts in `dsi_init` because `netmgrd` is down (needs TIPC); SIM state still empty |
| Mobile data | ⛔ | `netmgrd` exits 255: no `AF_TIPC` socket. `tipc.ko` is not loaded; a live load plus netmgrd start bootlooped the phone once |
| USB (adb) | ✅ | Legacy typec partner sets the DWC3 role to device |
| Audio | ⛔ | No sound card. `adsp-notify` node added but not enough. TFA9873 amps probe |
| Bluetooth | 🟡 | `btpower` loads and the HAL stays up, but the Settings toggle does not work |
| Camera | ⛔ | 0 devices. ICP FW init -110 (needs uncached heap hunk from redwood `cam_mem_mgr.c`), every CCI read on cci1 times out |
| Video codecs (HW) | ⛔ | No `msm_vidc`/venus driver, no DT node. Software codecs only |
| Haptics | ⛔ | Vibrator HAL up, RichTap effects not ported |
| Recorder app | ⛔ | Crashes in PairIP (`libpairipcore.so`), app-side |

## Known gotchas

- `make M=` module builds lose Bazel `CONFIG_*` defines, so headers become empty stubs. Compare `llvm-nm -u` against the installed module after every rebuild.
- `rfkill` is a signed GKI module outside `modules.dep`; it is loaded by path after `vendor.modprobe` stops.
- `qti-init.mk` gates the legacy qcrild rc by `TARGET_KERNEL_VERSION`; 6.12 needs it packaged explicitly.
- Reference tree for most fixes: `~/Nothing/redwood-6.18`.
