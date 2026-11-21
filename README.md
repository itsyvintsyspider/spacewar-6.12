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

# `kernel-6.12` - GKI kernel source

The Android common kernel from Qualcomm's platform release, plus the small set
of changes Spacewar needs in `common`. In a Kleaf workspace this branch is
checked out at `kernel_platform/common`.

- **Base:** CodeLinaro `kernel/common`, branch `ks-kernel.lnx.5.0.r80-rel`,
  Linux 6.12.81.
- **History:** the full upstream history is kept, with our commits on top.
- **Config:** the GKI config. The lahaina vendor config lives in
  [`soc-6.12`](../../tree/soc-6.12).

Not built standalone; see [`build-6.12`](../../tree/build-6.12) for the
workspace.

---

# Original README of this branch

The text below is the upstream `README.md` of the Android common kernel,
unchanged.

# How do I submit patches to Android Common Kernels

1. BEST: Make all of your changes to upstream Linux. If appropriate, backport to the stable releases.
   These patches will be merged automatically in the corresponding common kernels. If the patch is already
   in upstream Linux, post a backport of the patch that conforms to the patch requirements below.
   - Do not send patches upstream that contain only symbol exports. To be considered for upstream Linux,
additions of `EXPORT_SYMBOL_GPL()` require an in-tree modular driver that uses the symbol -- so include
the new driver or changes to an existing driver in the same patchset as the export.
   - When sending patches upstream, the commit message must contain a clear case for why the patch
is needed and beneficial to the community. Enabling out-of-tree drivers or functionality is not
a persuasive case.

2. LESS GOOD: Develop your patches out-of-tree (from an upstream Linux point-of-view). Unless these are
   fixing an Android-specific bug, these are very unlikely to be accepted unless they have been
   coordinated with kernel-team@android.com. If you want to proceed, post a patch that conforms to the
   patch requirements below.

# Common Kernel patch requirements

- All patches must conform to the Linux kernel coding standards and pass `scripts/checkpatch.pl`
- Patches shall not break gki_defconfig or allmodconfig builds for arm, arm64, x86, x86_64 architectures
(see  https://source.android.com/setup/build/building-kernels)
- If the patch is not merged from an upstream branch, the subject must be tagged with the type of patch:
`UPSTREAM:`, `BACKPORT:`, `FROMGIT:`, `FROMLIST:`, or `ANDROID:`.
- All patches must have a `Change-Id:` tag (see https://gerrit-review.googlesource.com/Documentation/user-changeid.html)
- If an Android bug has been assigned, there must be a `Bug:` tag.
- All patches must have a `Signed-off-by:` tag by the author and the submitter

Additional requirements are listed below based on patch type

## Requirements for backports from mainline Linux: `UPSTREAM:`, `BACKPORT:`

- If the patch is a cherry-pick from Linux mainline with no changes at all
    - tag the patch subject with `UPSTREAM:`.
    - add upstream commit information with a `(cherry picked from commit ...)` line
    - Example:
        - if the upstream commit message is
```
        important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>
```
>- then Joe Smith would upload the patch for the common kernel as
```
        UPSTREAM: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        (cherry picked from commit c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

- If the patch requires any changes from the upstream version, tag the patch with `BACKPORT:`
instead of `UPSTREAM:`.
    - use the same tags as `UPSTREAM:`
    - add comments about the changes under the `(cherry picked from commit ...)` line
    - Example:
```
        BACKPORT: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        (cherry picked from commit c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
        [joe: Resolved minor conflict in drivers/foo/bar.c ]
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

## Requirements for other backports: `FROMGIT:`, `FROMLIST:`,

- If the patch has been merged into an upstream maintainer tree, but has not yet
been merged into Linux mainline
    - tag the patch subject with `FROMGIT:`
    - add info on where the patch came from as `(cherry picked from commit <sha1> <repo> <branch>)`. This
must be a stable maintainer branch (not rebased, so don't use `linux-next` for example).
    - if changes were required, use `BACKPORT: FROMGIT:`
    - Example:
        - if the commit message in the maintainer tree is
```
        important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>
```
>- then Joe Smith would upload the patch for the common kernel as
```
        FROMGIT: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        (cherry picked from commit 878a2fd9de10b03d11d2f622250285c7e63deace
         https://git.kernel.org/pub/scm/linux/kernel/git/foo/bar.git test-branch)
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```


- If the patch has been submitted to LKML, but not accepted into any maintainer tree
    - tag the patch subject with `FROMLIST:`
    - add a `Link:` tag with a link to the submittal on lore.kernel.org
    - add a `Bug:` tag with the Android bug (required for patches not accepted into
a maintainer tree)
    - if changes were required, use `BACKPORT: FROMLIST:`
    - Example:
```
        FROMLIST: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Link: https://lore.kernel.org/lkml/20190619171517.GA17557@someone.com/
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

- If a patch has been submitted to the community, but rejected, do NOT use the
  `FROMLIST:` tag to try to hide this fact.  Use the `ANDROID:` tag as
  described below as this must be considered as an Android-specific submission,
  not an upstream submission as the community will not accept these changes
  as-is.

## Requirements for Android-specific patches: `ANDROID:`

- If the patch is fixing a bug to Android-specific code
    - tag the patch subject with `ANDROID:`
    - add a `Fixes:` tag that cites the patch with the bug
    - Example:
```
        ANDROID: fix android-specific bug in foobar.c

        This is the detailed description of the important fix

        Fixes: 1234abcd2468 ("foobar: add cool feature")
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

- If the patch is a new feature
    - tag the patch subject with `ANDROID:`
    - add a `Bug:` tag with the Android bug (required for android-specific features)

