#
# Copyright (C) 2026 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Inherit from the common hi6250 (Kirin 659) tree.
-include device/huawei/hi6250-common/BoardConfigCommon.mk

DEVICE_PATH := device/huawei/AGS2

# Assert
TARGET_OTA_ASSERT_DEVICE := AGS2,hi6250,agassi2,anne,prague

# Kernel
# AGS2 has its own GPL kernel release rather than sharing hi6250-common's
# phone-oriented kernel tree, since it carries the tablet-specific panel/
# touch/sensor drivers for this device. Source is now EMUI8 (Linux
# 4.4.23), not the originally-extracted HarmonyOS 2.0 one (4.9.148) --
# real hardware testing showed HarmonyOS 2.0's bootloader chain
# (XLOADER/FASTBOOT/TEEOS/TRUSTFIRMWARE) AVB-enforces the kernel
# partition against a key we don't have, with no software workaround
# found (see kernel_huawei_AGS2 commit "Switch kernel base..." for the
# full investigation). The user has real, prior, firsthand success
# getting a custom kernel booting on this exact device's EMUI8-era
# firmware, so the whole boot chain target is now EMUI8, not just the
# kernel. Baseline defconfig is stock Huawei's merge_hi6250_defconfig
# (present in both generations' source, confirmed compatible).
TARGET_KERNEL_SOURCE := kernel/huawei/AGS2
TARGET_KERNEL_CONFIG := merge_hi6250_defconfig

# EMUI8 uses the traditional ramdisk-based boot convention (confirmed by
# unpacking the stock EMUI8 RAMDISK.img: a real, populated gzip cpio
# ramdisk with /init, /init.rc, fstab.zram* variants etc, paired at boot
# time with the separate, ramdisk-less "kernel" partition) -- NOT the
# ramdisk-less system-as-root scheme HarmonyOS 2.0/EMUI9 use, which is
# what hi6250-common's BOARD_BUILD_SYSTEM_ROOT_IMAGE := true assumes.
# Overriding to false so the build produces and expects a real ramdisk
# instead, matching the boot chain we're now actually targeting.
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false

# hi6250-common's shared fstab.hi6250 mounts the system partition at "/"
# (the system-as-root convention, matching its BOARD_BUILD_SYSTEM_ROOT_
# IMAGE := true). Now that we're non-SAR, ota_from_target_files'
# edify_generator.py looks up fstab['/system'] when generating the OTA
# backup step and hard-fails with "KeyError: '/system'" against the
# shared fstab -- override with an AGS2-specific copy that mounts
# system at /system instead.
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.AGS2

# hi6250-common's shared BOARD_KERNEL_CMDLINE is missing two things the
# real stock cmdline (and a previously-working LineageOS bring-up on a
# related device) both have:
#   - coherent_pool=512K / slub_min_objects=12 -- memory tuning params
#     present in the stock KERNEL.img cmdline for this exact device.
#   - androidboot.selinux=permissive -- without this, SELinux defaults
#     to enforcing; this device tree's sepolicy is almost certainly
#     incomplete for all the proprietary HALs/services pulled in from
#     the stock vendor blobs, and an early SELinux denial killing a
#     critical process can hang boot completely silently (no visible
#     output at all, since nothing gets far enough to redraw the
#     screen past the bootloader's last frame) -- a well-known class of
#     custom-ROM bring-up failure, not something dmesg/pstore catches.
BOARD_KERNEL_CMDLINE := loglevel=4 coherent_pool=512K page_tracker=on slub_min_objects=12 unmovable_isolate1=2:192M,3:224M,4:256M printktimer=0xfff0a000,0x534,0x538 androidboot.selinux=permissive

# This device has no "boot" partition at all -- confirmed from the stock
# firmware's own partition list, it uses a dedicated "KERNEL" partition
# for the kernel (updater-script already correctly targets
# /dev/block/bootdevice/by-name/kernel, inherited from hi6250-common)
# plus a separate "ramdisk" partition for EMUI8's real, populated
# ramdisk (see BOARD_BUILD_SYSTEM_ROOT_IMAGE note above).
# hi6250-common's shared BOARD_KERNEL_BASE (0x00400000) is a generic
# default sized for other phones in this family, not this device's real
# hardware memory map -- confirmed by unpacking the stock EMUI8
# KERNEL.img with AIK-Linux: real base is 0x00478000, with
# ramdisk_offset/second_offset/tags_offset also differing from
# mkbootimg's own built-in defaults. mkbootimg does NOT derive those
# three from --base (verified: changing base alone left them
# unchanged) -- all four set explicitly below to match the stock
# EMUI8 header exactly (ramdisk_offset is EMUI8-specific -- 0x07b88000,
# not the 0x0ff88000 value HarmonyOS 2.0/EMUI9 use -- confirmed by
# byte-for-byte field comparison via AIK-Linux unpack of the real
# stock EMUI8 KERNEL.img).
BOARD_KERNEL_BASE := 0x00478000
BOARD_MKBOOTIMG_ARGS += --kernel_offset 0x00008000 --ramdisk_offset 0x07b88000 --second_offset 0x00e88000 --tags_offset 0x07988000

# Partitions
# Sizes below are the raw (post-sparse-expansion) byte sizes measured
# directly from the stock HarmonyOS 2.0 (build 102.0.0.040) firmware dump
# for this exact device, overriding the hi6250-common defaults which were
# sized for a different (phone) device sharing the same SoC.
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2441084928
BOARD_VENDORIMAGE_PARTITION_SIZE := 549453824
BOARD_PRODUCTIMAGE_PARTITION_SIZE := 1132462080
BOARD_ODMIMAGE_PARTITION_SIZE := 134217728
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_ODM := odm

# RIL
# This device has its own Huawei/Balong-modem libril.so and bin/hw/rild
# (extracted into vendor/huawei/AGS2/proprietary) -- without these,
# AOSP's generic hardware/ril/{libril,rild} reference implementations
# would win the module-name collision, which don't speak to this modem
# at all (confirmed: different size/hash from the real Huawei blobs).
# Both AOSP modules check for exactly this opt-out before defining
# themselves, so this lets our real prebuilts be the sole "libril"/
# "rild" module instead of dropping them.
BOARD_PROVIDES_LIBRIL := true
ENABLE_VENDOR_RIL_SERVICE := true
