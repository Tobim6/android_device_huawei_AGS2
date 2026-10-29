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

# WARNING: Everything listed here will be built on ALL platforms,
# including x86, the emulator, and the SDK.  Modules must be uniquely
# named (liblights.tuna), and must build everywhere, or limit themselves
# to only building on ARM if they include assembly. Individual makefiles
# are responsible for having their own logic, for fine-grained control.

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),AGS2)
# Binary TEEOS whitelist for the ramdisk (/res/native_packages.xml); see device.mk
AGS2_NATIVE_PACKAGES := $(PRODUCT_OUT)/root/res/native_packages.xml
$(AGS2_NATIVE_PACKAGES): $(LOCAL_PATH)/rootdir/res/native_packages.xml
	@mkdir -p $(dir $@)
	$(hide) cp -f $< $@
ALL_DEFAULT_INSTALLED_MODULES += $(AGS2_NATIVE_PACKAGES)

# The EMUI8 bootloader loads the real ramdisk from its own partition ("ramdisk", mmcblk0p31) as a kernel-less boot-format image;
# the boot.img the build makes only carries the kernel in effect. Wrap ramdisk.img the same way and ship it as RADIO/ramdisk_p31.img
# (flashed by releasetools.py FullOTA_InstallEnd).
AGS2_DEVICE_PATH := $(LOCAL_PATH)
AGS2_RAMDISK_P31 := $(PRODUCT_OUT)/ramdisk_p31.img
$(AGS2_RAMDISK_P31): $(INSTALLED_RAMDISK_TARGET) $(MKBOOTIMG) $(AGS2_DEVICE_PATH)/tools/wrap_ramdisk.py $(AGS2_DEVICE_PATH)/prebuilt/ramdisk_p31_header.bin
	@echo "Target ramdisk partition image: $@"
	$(hide) python3 $(AGS2_DEVICE_PATH)/tools/wrap_ramdisk.py $(MKBOOTIMG) $(INSTALLED_RAMDISK_TARGET) $(AGS2_DEVICE_PATH)/prebuilt/ramdisk_p31_header.bin $@
INSTALLED_RADIOIMAGE_TARGET += $(AGS2_RAMDISK_P31)

# TWRP (built separately, see twrp_device_huawei_AGS2) goes into recovery_ramdisk (mmcblk0p32); it borrows the kernel partition.
# Point AGS2_TWRP_RAMDISK at the packed TWRP-*-recovery_ramdisk.img to include it (RADIO/twrp_recovery_ramdisk.img).
ifneq ($(AGS2_TWRP_RAMDISK),)
AGS2_TWRP_RADIO := $(PRODUCT_OUT)/twrp_recovery_ramdisk.img
$(AGS2_TWRP_RADIO): $(AGS2_TWRP_RAMDISK)
	@echo "Target TWRP recovery ramdisk: $@"
	$(hide) cp -f $< $@
INSTALLED_RADIOIMAGE_TARGET += $(AGS2_TWRP_RADIO)
endif

include $(call all-makefiles-under,$(LOCAL_PATH))
endif
