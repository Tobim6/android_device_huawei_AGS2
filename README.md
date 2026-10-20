# LineageOS 16.0 device tree for Huawei MediaPad T5 (AGS2)

## Device identity

| | |
|---|---|
| Internal Huawei codename | **Dallas** |
| SoC / board platform | **hi6250** (HiSilicon Kirin 659) |
| Retail model codes | AGS2-W09 (WiFi-only), AGS2-L09 / AGS2-AL00 (cellular) |
| Android version | 9 (Pie), SDK 28 |
| Treble | enabled, `BOARD_VNDK_VERSION := current` |
| Screen | 1920x1200 (10.1" FHD), density 480 |
| Kernel | Linux 4.9.148, `merge_hi6250_defconfig` |

Confirmed directly from a stock HarmonyOS 2.0 (build 102.0.0.040) firmware
dump: `/hw_odm/AGS2-L09/...` and `ro.product.odm.device=Dallas` in the odm
partition's `build.prop`. The odm audio config files are internally
labelled `AGASSI2`/`AGASSI2_normal` — a secondary internal codename
variant, same hardware.

The firmware used as the extraction source is the **cellular** AGS2-L09/
AL00 variant (it bundles `MODEM_FW.img`/modem NVM), kept intentionally so
telephony/modem support isn't stripped from this tree — even though the
primary target device for this port is the WiFi-only AGS2-W09, keeping
cellular support lets AGS2-L09/AL00 users run this ROM too.

## Base tree

This is a thin device-specific tree on top of the real, existing
LineageOS **hi6250-common** tree (shared with other Kirin 659 devices —
Honor 9 Lite, P smart, Y9 2018, etc.):

- `device/huawei/hi6250-common` — `LineageOS/android_device_huawei_hi6250-common`, branch `lineage-16.0`
- reference per-device pattern followed: `hi6250-dev/android_device_huawei_figo`, branch `lineage-16.0`

AGS2 did not have an existing device tree in that family (it's a tablet;
the family is otherwise all phones), which is what this repo adds.

## Kernel

Uses its own kernel tree (`kernel/huawei/AGS2`) rather than sharing
hi6250-common's, because this exact firmware's GPL kernel release carries
the correct tablet-specific panel/touch/sensor drivers for AGS2 — imported
from `Code_Opensource/kernel` in the stock firmware package, Linux
4.9.148, baseline defconfig `merge_hi6250_defconfig`. Diffing against
`LineageOS/android_kernel_huawei_hi6250` (lineage-16.0) shows the LOS
config delta over stock is small and mechanical: `CONFIG_LOCALVERSION`,
`CONFIG_TCP_NODELAY`, disabling a few Huawei-only features
(`CONFIG_HW_VOWIFI`, `CONFIG_HUAWEI_HISHOW`), and disabling
`CONFIG_EROFS_FS` entirely (LOS builds its own system/vendor images as
plain ext4, it never needs to read Huawei's EROFS at runtime). That same
delta should be layered onto `merge_hi6250_defconfig` for this tree too —
not yet done; whoever picks this up next should diff and apply it, then
do a real `aarch64-linux-android-4.9` (or clang, matching whatever
toolchain the synced LOS16 manifest brings) build to confirm the kernel
boots.

## Proprietary blobs

`proprietary-files.txt` was generated from a **static dump** of the stock
firmware (not a live `adb pull`), covering `/vendor`, `/product`, and
`/odm` in full. The stock images use EROFS, but it's Huawei's original
2017-2018 on-disk format (`CONFIG_EROFS_FS_HUAWEI_EXTENSION`) — not
compatible with current `erofs-utils` or even this machine's own
(non-Huawei) kernel's `erofs.ko`. A standalone decoder for this exact
format was written against the GPL kernel source and used to do the
actual extraction; see `vendor/huawei/AGS2`'s commit message / the
decoder itself for details if you need to re-extract from a different
firmware dump. End result: **100% of regular files and symlinks** in
`/vendor`, `/product`, and `/odm` were recovered and verified (ELF
headers/dynamic sections/symbol tables and APK zip structure spot-checked
clean).

`lineage-16.0`'s `extract_utils.sh` (vendor/lineage/build/tools) has no
native `odm` partition support (that was added in later LineageOS
branches) — the `odm/`-prefixed lines in `proprietary-files.txt` will
extract fine via `extract-files.sh`, but `setup-makefiles.sh` won't
auto-generate an odm Android.mk. Whoever builds this will likely need to
either hand-write `PRODUCT_COPY_FILES`/packages for the odm blobs, or
backport `write_odm_packages` from a newer `extract_utils.sh`.

`/system` was also fully extracted for reference/diffing during this
port but is intentionally **not** in `proprietary-files.txt` — Treble
means LOS's own system image replaces stock Huawei's entirely; pulling
stock system blobs would fight that, not help it.

## Known hardware limitations

- **No hardware video encode/decode acceleration.** The kernel's
  `drivers/vcodec/imagination/D5500/` tree (Imagination/PowerVR D5500
  video codec IP, gated by `CONFIG_IMAGINATION_D5500_VCODEC` /
  `_DRM_VCODEC`) is present in the Makefile/Kconfig structure of this GPL
  release, but `encode/platform/hisi/` is genuinely empty — the
  IP-encumbered platform glue was not included by Huawei. Build fails
  with `No rule to make target .../sysdev.o` until these configs are
  disabled. This is a real functional loss (camera video recording,
  video calls etc. fall back to software encode/decode), not a build
  workaround, and there's no source available to fix it short of finding
  a prebuilt `.ko`/platform blob from another release.

## Status (updated during active build-iteration)

A full LineageOS 16.0 source tree has been synced and this device tree,
`kernel/huawei/AGS2`, and `vendor/huawei/AGS2` dropped into it;
`breakfast AGS2` resolves cleanly. Build-iterating via `mka bootimage`
turned up (and fixed) real issues along the way:

- `device/huawei/hi6250-common/Android.mk` hardcoded a device allowlist
  (`anne figo`) excluding `AGS2` — added.
- Host tools (`scripts/dtc` etc.) fail to link on a modern host GCC
  (`-fno-common` default breaks old bison/flex-generated tentative
  definitions) — fixed with `-fcommon` in the kernel `Makefile`'s
  `HOSTCFLAGS`.
- LOS-matching defconfig deltas applied directly to
  `arch/arm64/configs/merge_hi6250_defconfig` (not yet split into a
  separately-named AGS2 defconfig — this file *is* the AGS2 one now):
  `CONFIG_LOCALVERSION`/`_AUTO`, `CONFIG_TCP_NODELAY`, disabling
  `CONFIG_DM_SNAPSHOT`, `CONFIG_HW_VOWIFI`, `CONFIG_TYPEC_CAP_CUSTOM_SRC2`,
  `CONFIG_HUAWEI_HISHOW`, `CONFIG_EROFS_FS`, plus disabling the D5500
  vcodec configs above.

## Known open work

- [ ] Finish getting `mka bootimage` (kernel) to build clean, then move
      to `mka bacon` for a full ROM build — currently mid-iteration.
- [ ] Generate `vendor/huawei/AGS2/Android.mk` for real via
      `extract-files.sh`/`setup-makefiles.sh` from `proprietary-files.txt`
      (blobs are already in place; the Android.mk was hand-skipped since
      the blobs came from a static firmware dump, not a live device/zip
      that `extract_utils.sh` expects as `$SRC`).
- [ ] Wire up odm blob packaging (see above).
- [ ] `breakfast AGS2 && mka bacon`, fix build breakage as it comes up
      (expect HAL/HIDL mismatches given the stock build's VNDK is
      reported as 26.0.0 despite being an SDK 28 build — likely stale
      metadata, but worth double-checking against `BOARD_VNDK_VERSION`).
- [ ] Flash and test on real hardware — not done in this session (no
      physical device attached).
