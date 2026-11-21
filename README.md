# Nothing Phone (1) "Spacewar" - Linux 6.12

Linux 6.12 kernel for the **Nothing Phone (1)** (`Spacewar`, Qualcomm
**SM7325**, platform `yupik`, Kleaf target `lahaina`), built from Qualcomm's
official 6.12 release for this chip.

## What it runs on

| | |
|---|---|
| Device | Nothing Phone (1), codename `Spacewar` |
| SoC | Qualcomm SM7325 (`yupik` devicetree, `lahaina` Kleaf target) |
| Kernel | Android GKI `android16-6.12`, Linux 6.12.81 |
| Qualcomm release | CodeLinaro `KERNEL.PLATFORM.5.0.r48-00400-kernel.0` |
| Build system | Kleaf / Bazel, clang `r563880c` |
| Target ROM | [Neoteric](https://github.com/Neoteric-OS) (Android 17) |

## Repository layout

One repository, one branch per role. The branches have unrelated histories.
Every branch carries this same README base; the part below it is specific to
the branch.

| Branch | Role |
|---|---|
| [`kernel-6.12`](../../tree/kernel-6.12) | GKI kernel source (`kernel_platform/common`) |
| [`soc-6.12`](../../tree/soc-6.12) | SoC tree, Kleaf targets, vendor drivers (`kernel_platform/soc-repo`) |
| [`devicetree-6.12`](../../tree/devicetree-6.12) | Board devicetree (`kernel_platform/qcom/opensource/devicetree`) |
| [`modules-6.12`](../../tree/modules-6.12) | Out-of-tree vendor modules |
| [`build-6.12`](../../tree/build-6.12) | Build script, bring-up tooling, toolchain glue |

The device tree (BoardConfig, sepolicy, vintf) lives in a separate repo,
`spacewar-6.12-device`.

## Credits

The structure of this project follows the work of
**[@redducc](https://github.com/redducc)** on the Nothing Phone (2) "Pong":
[redducc/kernel_nothing_pong](https://github.com/redducc/kernel_nothing_pong.git).
Thank you, redducc!

Also thanks to:

- [suvojeet-sengupta](https://github.com/suvojeet-sengupta) for the redwood
  (SM7325) port, which this builds on.
- Qualcomm / CodeLinaro for the kernel platform and techpack sources.
- Nothing for the open-source Phone (1) kernel and devicetree.
- Google / AOSP for the Android common kernel.

## License

Kernel code is GPL-2.0. Vendor drivers and devicetrees keep their own
headers.

---

# `build-6.12` - build script, bring-up tooling, toolchain glue

How the other branches are put together and built. No kernel source here.

| Path | Purpose |
|---|---|
| `build.sh` | Builds the vendored techpacks from [`modules-6.12`](../../tree/modules-6.12) against a Kleaf-built `kernel_platform`. |
| `bringup/` | Minimal init with a USB debug shell, and a packer for bring-up boot images. |
| `kleaf/` | The clang `r563880c` Kleaf toolchain files. |
| `docs/` | Older notes. |

## Workspace

The pins come from the CodeLinaro release
`KERNEL.PLATFORM.5.0.r48-00400-kernel.0`
([manifest repo](https://git.codelinaro.org/clo/la/kernelplatform/manifest)).
Our three source trees replace the matching manifest projects:

- `kernel-6.12` at `kernel_platform/common`
- `soc-6.12` at `kernel_platform/soc-repo`
- `devicetree-6.12` at `kernel_platform/qcom/opensource/devicetree`

`soc-repo/arch/arm64/boot/dts/vendor` must be a symlink to
`../../../../../qcom/opensource/devicetree`.

## Build

From the `kernel_platform` root:

```
python3 build_with_bazel.py -t lahaina perf
```
