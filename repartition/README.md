# AGS2 repartitioning (built into the install zip)

The install zip repartitions `mmcblk0` from **`preas`** on, so the ROM gets a smaller system/vendor and a bigger userdata.

| # | partition | size |
|---|-----------|------|
| 1..51 | everything before `preas` (incl. `preload`, `odm`, `cache`, recovery, kernel, ...) | **never touched** |
| 52 | `system`  | filesystem used space + 300 MiB (GApps reserve) |
| 53 | `vendor`  | filesystem used space + 50 MiB |
| 54 | `userdata`| everything that is left |

`preas`, `preavs`, `cust`, `version` and `product` are not recreated. Stock was `preas 52, preavs 53, system 54, cust 55, version 56, vendor 57,
product 58, userdata 59` (userdata 9.7 GB).

## How it works
* **Sizes come from the build.** `device.mk` sets `PRODUCT_USE_DYNAMIC_PARTITION_SIZE`, `BoardConfig.mk` sets
  `BOARD_SYSTEMIMAGE_PARTITION_RESERVED_SIZE` (300 MiB) and `BOARD_VENDORIMAGE_PARTITION_RESERVED_SIZE` (50 MiB) and no fixed sizes, so
  `system.img`/`vendor.img` are content + reserve. `hi6250-common/releasetools/releasetools.py` (`FullOTA_InstallBegin`) reads those image
  sizes from the target files and runs `install/bin/repartition.sh <system MiB> <vendor MiB>` first thing in the updater-script.
  The existing `resize2fs` step after flashing grows the system filesystem to the (MiB rounded) partition.
* **`repartition.sh` decides:**
  1. last partitions already `system`/`vendor`/`userdata` as 52/53/54 and big enough for this zip -> **no repartition** (a new OTA of a
     slightly different size therefore does not wipe `/data`);
  2. the stock layout for `preas` and everything after it matches **exactly** (sector numbers of the verified `parted print`, disk size
     30777344 sectors) -> repartition;
  3. anything else, or already repartitioned but too small -> **abort, nothing written**.
* Before writing it saves the old primary GPT (and the parted print) to `/cache` (`ags2_gpt_primary_before_repartition.bin`), refuses if the
  install zip lies on a partition that is about to disappear, requires those partitions to be unmounted, and after writing verifies that
  partitions 1..51 are byte-for-byte the same table entries, that 52/53/54 are as planned, and that the kernel sees them (by-name links).
  Then it formats userdata (`make_f2fs -g android`, deliberately **without** `extra_attr`/`project_quota`: the 4.4 kernel panics on those).
* `parted` here is the statically linked aarch64 build supplied by the maintainer (md5 `cb061761e0dd6404662becbcf3ea47c2`).

## Using it
1. Put the zip on the **SD card** and install it from there. Internal storage is deleted by this step (the script refuses otherwise).
2. In TWRP unmount Data (and System/Vendor if mounted) first if the script says something is still mounted.
3. This **destroys /data and the internal storage** of the old layout. The first install of this zip is the only one that repartitions.

Rollback of the partition table (contents of the old partitions are NOT restored): in TWRP,
`dd if=/cache/ags2_gpt_primary_before_repartition.bin of=/dev/block/mmcblk0 bs=512 count=34` and reboot recovery.

## Caveats
* The Huawei bootloader/`fastboot` may still use its own old layout for the names `system`, `vendor` and `userdata`: after this do **not** use
  `fastboot erase|flash` on them (use TWRP / this zip). Partitions before `preas` (bootloader, kernel, recovery) are untouched.
* The ROM no longer has `cust`, `version`, `product` (stock EMUI product files) or `preas`/`preavs`. Their mounts no longer wait
  (`init.hi6250.rc`), `fstab.AGS2` and the TWRP fstabs dropped them. The device tree fstab (`/proc/device-tree/firmware/android/fstab`) still
  lists them: if first-stage mount or AVB insists on them the ROM will not boot; recovery will (kernel and recovery partitions are untouched).
* Not tested on the tablet: only against disk images (below) and a unit test of the releasetools hook.

## Tests
`test/run_tests.sh` builds disk images from the tablet's real primary GPT (`test/primary_gpt_real.bin`) and runs the script with the shipped
parted through `qemu-aarch64-static`: stock table, repartition, skip, abort on every mismatch, rollback (25 checks).
