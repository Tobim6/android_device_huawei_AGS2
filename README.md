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
branches) — the `odm/`-prefixed lines in `proprietary-files.txt` extract
fine via `extract-files.sh`, but `setup-makefiles.sh` won't auto-generate
an odm Android.mk. **Resolved**: `vendor/huawei/AGS2/AGS2-vendor-odm.mk`
is hand-generated (`work/tools/gen_odm_mk.py`) as a plain
`PRODUCT_COPY_FILES` block into `$(TARGET_COPY_OUT_ODM)`.

**However**: this specific AOSP-9/LineageOS-16.0 `build/make` core has no
`odm.img` build rule at all — not just no `extract_utils.sh` support, the
whole image-packaging step for a separate ODM partition doesn't exist
yet in this AOSP vintage (full ODM-partition image building landed in
later AOSP). `TARGET_COPY_OUT_ODM := odm` plus
`BOARD_ODMIMAGE_PARTITION_SIZE`/`_FILE_SYSTEM_TYPE` in
`device/huawei/AGS2/BoardConfig.mk` stage real content into
`out/target/product/AGS2/odm/` (confirmed: camera calibration data,
per-carrier `.ato` network configs, etc. — ~800 files after dropping
broken symlinks, see below), but nothing ever turns that staging
directory into `odm.img` or bundles it into the OTA zip. **Workaround**:
flash the stock HarmonyOS `ODM.img` (Android sparse image,
`/home/tobim6/Downloads/AGS2 HMOS/ODM.img` in the original firmware
dump) unmodified to the `odm` partition alongside this ROM's
`boot`/`vendor`/`product`/`system`. It's literally the same data our
`proprietary-files.txt` was extracted from, and since it's flashed to
its own real, separately-mounted partition, the on-device-absolute-path
symlinks inside it (`/odm/hw_odm/ncfg/...` etc. — see below) resolve
correctly there, unlike in our static extraction tree. Porting real
`odm.img` build support from a later AOSP revision is tracked as open
work below but not attempted this session.

`/system` was also fully extracted for reference/diffing during this
port but is intentionally **not** in `proprietary-files.txt` — Treble
means LOS's own system image replaces stock Huawei's entirely; pulling
stock system blobs would fight that, not help it.

## Flashing — this device has no `boot` partition

**Critical, confirmed directly from the stock firmware's own partition
list (`UPDATE.APP` extraction) — do not flash `boot.img` to a `boot`
partition on this device, it doesn't exist.** This AGS2/HarmonyOS 2.0
firmware's GPT has a dedicated **`KERNEL`** partition instead, holding
just the kernel image with **zero ramdisk** — no separate `RAMDISK`
partition for normal boot either (only `RECOVERY_RAMDISK.img`/
`ERECOVERY_RAMDISK.img` exist, for the two recovery modes, and those
*are* standard combined AOSP bootimgs with a real ramdisk — only
*normal* boot is ramdiskless).

Investigated and resolved:
- `KERNEL.img` (from the firmware dump) is a standard AOSP bootimg
  (`header_version 0`, `ANDROID!` magic) wrapped in ~4096 bytes of
  leading data — unpacking it with **AIK-Linux**
  (`maximus-sallam/android-image-kitchen-complete` fork; the upstream
  `osm0sis/Android-Image-Kitchen` `AIK-Linux` branch's own git history
  never actually included the compiled Linux binaries it needs) finds
  the real header automatically and confirms: `BOARD_KERNEL_BASE
  0x00478000`, page size 2048, and genuinely **no ramdisk** (`Warning:
  No ramdisk found to be unpacked!`).
- Turns out this isn't a problem to solve from scratch — **our build
  was already producing a ramdiskless `boot.img`**, because
  `device/huawei/hi6250-common/BoardConfigCommon.mk` (the real,
  upstream hi6250-common tree this device tree is built on) already
  sets `BOARD_BUILD_SYSTEM_ROOT_IMAGE := true` (system-as-root), which
  the other phones in this hi6250/Kirin659 family already rely on.
  AOSP's own `mka bacon` output for this device gives the exact same
  "no ramdisk" result as the stock `KERNEL.img`. The actual gap was
  purely the **partition name/packaging**, not the boot mechanism.
- Fix: unpack the stock `KERNEL.img` with AIK, replace only the
  embedded kernel payload (`out/target/product/AGS2/kernel` — a plain
  `Image.gz`, no appended DTB, exactly matching the stock payload
  format) with ours, and repack — keeping the stock header's
  hardware-tuned memory offsets (`base`/`kernel_offset`/etc., tuned to
  this SoC's real DDR map) and empty ramdisk exactly as-is, changing
  nothing but the kernel binary itself. Output saved at
  `work/out_flashable/KERNEL.img` (12,288,000 bytes). **Flash this to
  the `KERNEL` partition specifically, not `boot`** — the exact
  fastboot/flashing command to use (partition name as this
  bootloader's `fastboot getvar` sees it) hasn't been verified against
  real hardware this session.
- DTB is unaffected by any of this — already handled separately (see
  Kernel section above): this device uses Huawei's own stock `DTS.img`
  at flash time, not a from-source DTB.

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

## Status

**`mka bacon` succeeds end-to-end with the real hardware blobs actually
packaged, including the real (hash-verified) RIL and WiFi HAL blobs.**
A full `lineage-16.0-20261020-UNOFFICIAL-AGS2.zip` OTA package (759MB)
builds cleanly, fingerprint `HUAWEI/lineage_AGS2/AGS2:9/.../userdebug/
test-keys`. This is a real milestone over an earlier "successful" build
that silently excluded all
vendor content:

| image | size | contents |
|---|---|---|
| `vendor.img` | 400MB | real `libril.so` (**hash-verified** against the stock blob — not AOSP's generic reference RIL, see below), `libwifi-hal-bcm.so` (real Broadcom WiFi HAL), `camera.device@*-impl.so`, GPU/sensor/audio HAL libs |
| `product.img` | 426MB | bundled apps, region configs, display/camera effect data |
| `odm/` staging | 95MB, ~800 files | camera calibration (bshutter/davinci/hwbeauty/smartae configs), 294 per-carrier `.ato` network configs — **not currently packaged into any image, see odm.img caveat above** |
| `boot.img` | 12MB | built by `mka bacon`, but **not directly flashable as-is** — see the no-`boot`-partition section above. Repacked into `work/out_flashable/KERNEL.img` for the real `KERNEL` partition instead. |
| final OTA zip | 759MB | |

**Caught and fixed before calling this done**: an earlier "successful"
build was actually shipping AOSP's *generic reference* `libril.so` in
vendor.img, not Huawei's real Balong-modem one — same module name, so
the collision-avoidance logic below had quietly dropped ours and let
AOSP's win (different file size/hash, confirmed by hashing both).
Telephony was an explicit project goal (cellular firmware was
deliberately the extraction source precisely so LTE variant users
aren't left out), so this got a real fix rather than a documented
caveat:

- `hardware/ril/libril` and `hardware/ril/rild` both check an opt-out
  flag before defining their own generic module
  (`BOARD_PROVIDES_LIBRIL` / `ENABLE_VENDOR_RIL_SERVICE`, set in
  `device/huawei/AGS2/BoardConfig.mk`) — exactly for this situation.
  `libreference-ril`/`librilutils` have no such guard and are
  unconditionally pulled into every product by
  `build/target/product/base.mk`, so those two genuinely can't be
  overridden and stay dropped (no functional loss believed —
  `librilutils` is generic IPC glue, and the generic
  `libreference-ril` is simulator-oriented and inert once Huawei's
  real `libril`/`rild` are doing the work).
- `libwifi-hal`/`libwifi-hal-bcm` (the real Broadcom WiFi HAL) were
  dropped on the same false assumption — neither `hi6250-common` nor
  this device tree ever actually selects AOSP's same-named module into
  `PRODUCT_PACKAGES`, so demoting to a plain copy-file avoids the
  `ckati` parse-time name collision with no risk of a competing ninja
  install rule for the same output path.
- Un-dropping `libril` then exposed a **second**, much more systemic
  bug: this LineageOS 16.0 `extract_utils.sh` never sets
  `LOCAL_PROPRIETARY_MODULE`/`LOCAL_PRODUCT_MODULE` on any
  `SHARED_LIBRARIES`-class `BUILD_PREBUILT` stanza it generates (the
  vendor-placement override is literally commented out in that
  script's `write_packages()`) — all ~256 of our vendor/product `.so`
  modules were implicitly tagged `native:platform` instead of
  `native:vendor`/`native:product`. Unnoticed for 27 build iterations
  because nothing had an explicit dependency on any of them that would
  trigger `build/make`'s Treble `check_link_type.py` consistency
  check — until `libreference-ril`'s dependency on `libril` did:
  `libreference-ril (native:vendor) should not link to libril
  (native:platform)`. Fixed generically (not just for `libril`) with a
  post-processing pass over the generated `Android.mk`
  (`work/tools/fix_prebuilt_partition_flags.py`, wired into
  `gen_vendor_makefiles.sh`) that tags every `SHARED_LIBRARIES` stanza
  with the correct partition flag based on its source path.

`vendor/huawei/AGS2/AGS2-vendor.mk` + `Android.mk` +
`BoardConfigVendor.mk` + `AGS2-vendor-odm.mk` are generated from
`proprietary-files.txt` via a categorizer script
(`work/tools/split_proprietary_files.py`) feeding LineageOS's own
`extract_utils.sh`, rather than hand-written. Getting from "generic
AOSP vendor, builds but no hardware support" to this took ~20 build
iterations, each one `extract_utils.sh` (designed for live-device
extraction, not a comprehensive static dump of ~6,000 files) hitting a
different implicit convention or edge case:

- HIDL (`*@X.Y-impl*.so`) and legacy (`lib{,64}/hw/*.so`) HAL
  implementation libraries must stay plain copy-files, never named
  `PRODUCT_PACKAGES` modules — they collide with AOSP's own default HAL
  module of the same name at `ckati` parse time.
- ~71 module names (sepolicy/toybox/init/vndservice infra, mostly —
  plus a few genuinely hardware-specific losses: `libreference-ril`,
  `librilutils`, some audio effect libs) collide with an AOSP/LOS
  module elsewhere in the tree and have no build-flag opt-out, so stay
  dropped; excluded by diffing our full module list against every
  `LOCAL_MODULE`/`Android.bp` name in the synced source tree.
  `libril`/`rild`/`libwifi-hal{,-bcm}` were in this category too until
  properly recovered — see the RIL/WiFi section below.
- ~300 basenames (camera calibration configs, regional carrier files,
  generic lib/bin names like `custom`) collide with each other across
  different source paths — `write_packages` names modules by bare
  basename with no path disambiguation; demoted to copy-files.
- 53 `.apk`/`.jar` files (per-SKU regional overlays, China-only service
  apps) live at paths `write_product_packages` doesn't recognize as an
  app category (`overlay/`, `region_comm/.../app/NAME/`, etc.) and can't
  go through plain `PRODUCT_COPY_FILES` either (`use BUILD_PREBUILT
  instead!`) — dropped entirely.
- 1170 symlinks under `odm/` use on-device-absolute-path targets
  (`/odm/hw_odm/...`, `/vendor/preavs/...`, `/system/lib/...`) — valid
  once partitions are mounted at runtime, unresolvable in our offline
  extraction tree. Every case checked has its real content packaged
  separately under a real (non-symlink) path; dropped with no loss.
- 79 files have a `.xml` extension but are genuinely binary content —
  74 are real XML mislabeled with the unsupported legacy `GB2312`
  encoding (re-encoded to UTF-8 with `iconv`, content unchanged), 5 are
  actually binary/encrypted Huawei "cust" policy blobs (`file`/`xxd`
  confirmed high-entropy bytes from byte 0, not real XML at all —
  dropped; the categorizer now runs `xmllint` on every `.xml` entry at
  categorization time so this is caught automatically on any future
  re-extraction).
- 2 `.hap` (HarmonyOS "Feature Ability" package, not an Android APK)
  files sitting in the same `app/` dir as a real `.apk` got treated as
  a packageable APK module and sent through `signapk`, which crashed
  (`No AndroidManifest.xml in APK`) — dropped; the real `.apk` in the
  same directory is still packaged.
- A stray `readme.txt` bundled inside a vendor SDK's `lib64/` directory
  got module-ified as a `SHARED_LIBRARIES` target and sent through
  `strip`, which hard-fails on non-ELF input — any `lib`/`lib64`-
  category entry now requires an actual `.so` extension to get module
  treatment.

All of this lives in `work/tools/split_proprietary_files.py`'s
exclusion logic, so re-running the full pipeline against a fresh
extraction (e.g. a newer firmware dump) should reproduce a working
build without re-discovering each of these by hand.

Build-iteration also turned up (and fixed) several environment/build
issues along the way — kept here since they'll very likely recur on a
fresh checkout of this same tree:

- `device/huawei/hi6250-common/Android.mk` hardcoded a device allowlist
  (`anne figo`) excluding `AGS2` — added.
- Host tools (`scripts/dtc` etc.) fail to link on a modern host GCC
  (`-fno-common` default breaks old bison/flex-generated tentative
  definitions) — fixed with `-fcommon` in the kernel `Makefile`'s
  `HOSTCFLAGS`.
- LOS16-era build scripts are Python 2; a modern host only has Python 3.
  Fix: a PATH-prepended shim directory with `python`/`python2`/
  `python2.7` symlinked to the genuinely-functional Python 2.7 already
  bundled at `prebuilts/gdb/linux-x86/bin/python2.7` (meant for gdb, but
  works standalone) — export that dir first in PATH before sourcing
  `envsetup.sh`.
- `external/chromium-webview`'s prebuilt `webview.apk` (all 4 ABIs)
  ships as a Git LFS pointer; plain `repo sync` doesn't fetch LFS
  content. Fix: `git-lfs install --local` then `git lfs pull` run with
  explicit `GIT_DIR=.repo/projects/external/chromium-webview/prebuilt/<arch>.git`
  / `GIT_WORK_TREE=external/chromium-webview/prebuilt/<arch>` per ABI
  (repo-tool checkouts don't have a normal top-level `.git`).
- Killing/restarting a build mid-flight can leave stale, incomplete
  intermediates in `out/` (a `classes-header.jar` or similar that's a
  few bytes of garbage, not real content) that cause confusing,
  unrelated-looking downstream failures. If a failure mentions a class
  that obviously exists in source, check the actual intermediate
  file's size before chasing the wrong lead; `rm -rf` just that
  module's `*_intermediates` directory, don't do a full clean.
- LOS-matching defconfig deltas applied directly to
  `arch/arm64/configs/merge_hi6250_defconfig` (not yet split into a
  separately-named AGS2 defconfig — this file *is* the AGS2 one now):
  `CONFIG_LOCALVERSION`/`_AUTO`, `CONFIG_TCP_NODELAY`, disabling
  `CONFIG_DM_SNAPSHOT`, `CONFIG_HW_VOWIFI`, `CONFIG_TYPEC_CAP_CUSTOM_SRC2`,
  `CONFIG_HUAWEI_HISHOW`, `CONFIG_EROFS_FS`, plus disabling the D5500
  vcodec configs above.
- `hi6250-common`'s QTI/Qualcomm IMS telephony jar
  (`TARGET_PROVIDES_QTI_TELEPHONY_JAR`, `qti-telephony-common`,
  `telephony-ext`) is irrelevant boilerplate for this device's Huawei
  Balong modem — removed as cleanup (the actual `ims-ext-common`
  compile errors hit along the way turned out to be the stale-
  intermediates issue above, not this, but it's dead weight either way).

## Known open work

- [x] Generate `vendor/huawei/AGS2/AGS2-vendor.mk`/`Android.mk` from
      `proprietary-files.txt` and get the real extracted blobs actually
      packaged into `vendor.img`/`product.img` — done, see Status above.
- [x] Wire up odm blob packaging as `PRODUCT_COPY_FILES` (hand-written,
      `extract_utils.sh` in this LOS version has no native odm support).
- [ ] **Port real `odm.img` build support** from a later AOSP revision,
      or confirm whether this device can run acceptably with the stock
      `ODM.img` flashed unmodified long-term (current workaround — see
      caveat in Proprietary blobs section above). This is now the main
      remaining gap.
- [x] **No `boot` partition on this device — confirmed from the stock
      firmware's own partition list.** Normal boot uses a dedicated
      `KERNEL` partition with zero ramdisk; `BOARD_BUILD_SYSTEM_ROOT_IMAGE
      := true` (already inherited from hi6250-common) means our own
      `mka bacon` output already matches that (ramdiskless `boot.img`)
      — the only real gap was packaging/partition naming, not the boot
      mechanism. Repacked via AIK-Linux into `work/out_flashable/
      KERNEL.img`. **Not yet verified against real hardware** — the
      correct fastboot partition name/flash command needs confirming
      before this is actually flashed.
- [x] `libril`/`rild`/`libwifi-hal{,-bcm}` recovered (real hash-verified
      blobs now packaged, not AOSP's generic reference versions) — see
      Status above.
- [ ] A few remaining genuinely hardware-specific modules stay dropped
      because their AOSP/LOS collision has no build-flag opt-out
      (`libreference-ril`, `librilutils`, some audio effect libs) —
      believed to be no real functional loss (see Status above for the
      reasoning on each), but not verified on real hardware.
- [ ] Double-check `BOARD_VNDK_VERSION := current` resolves sanely given
      the stock build's VNDK metadata said 26.0.0 despite being SDK 28.
- [ ] Flash and test on real hardware — not done in this session (no
      physical device attached). This is explicitly the user's own
      next step.
