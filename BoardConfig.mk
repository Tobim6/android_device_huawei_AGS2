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
TARGET_OTA_ASSERT_DEVICE := AGS2,hi6250

# Kernel
# AGS2 has its own GPL kernel release (from the stock HarmonyOS 2.0 firmware)
# rather than sharing hi6250-common's phone-oriented kernel tree, since it
# carries the tablet-specific panel/touch/sensor drivers for this device.
# Baseline defconfig is stock Huawei's merge_hi6250_defconfig; expect to fork
# this into an AGS2-specific defconfig once Treble/selinux/f2fs-crypto
# deltas (see device/huawei/hi6250-common's kernel for reference) are
# layered on top.
TARGET_KERNEL_SOURCE := kernel/huawei/AGS2
TARGET_KERNEL_CONFIG := merge_hi6250_defconfig

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
