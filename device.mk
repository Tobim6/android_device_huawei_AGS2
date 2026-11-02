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
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_o.mk)

# call the proprietary setup
$(call inherit-product-if-exists, vendor/huawei/AGS2/AGS2-vendor.mk)
$(call inherit-product-if-exists, vendor/huawei/AGS2/AGS2-vendor-odm.mk)

PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xhdpi
PRODUCT_AAPT_PREBUILT_DPI := xhdpi hdpi

# Local overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay \
    $(LOCAL_PATH)/overlay-lineage

# This is a tablet
PRODUCT_CHARACTERISTICS := tablet

# Boot animation
# MediaPad T5 (AGS2) 10.1" panel, 1920x1200 (FHD). Confirmed from public
# hardware spec; re-verify against a running stock unit if this differs
# for your specific AGS2 sub-model.
TARGET_SCREEN_HEIGHT := 1200
TARGET_SCREEN_WIDTH := 1920

# The EMUI8-generation Mali GPU driver blob (swapped in to match our EMUI8
# kernel) needs android::CallStack, which this AOSP tree split out of
# libutils.so into a separate libutilscallstack.so -- and libutils.so isn't
# an LLNDK library the sphal namespace can reach from the system partition
# either way. See device/huawei/AGS2/libutils_vendor_compat/Android.bp for
# the full explanation; this installs a vendor-local libutils.so that
# re-exports CallStack alongside the normal libutils API.
PRODUCT_PACKAGES += \
    libutils_vendor_callstack_compat_as_libutils_64 \
    libutils_vendor_callstack_compat_as_libutils_32

# Inherit from hi6250-common
$(call inherit-product, device/huawei/hi6250-common/hi6250.mk)

# The stock vendor audio policy (vendor/etc/audio_policy_configuration.xml) xi:includes its
# module configs from /vendor/etc, but the proprietary modules install them to /system/etc only.
# Without them the A2DP (Bluetooth audio), USB and r_submix modules fail to load.
PRODUCT_COPY_FILES += \
    vendor/huawei/AGS2/proprietary/etc/a2dp_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_audio_policy_configuration.xml \
    vendor/huawei/AGS2/proprietary/etc/usb_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usb_audio_policy_configuration.xml \
    vendor/huawei/AGS2/proprietary/etc/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml

# Dalvik heap for a 10" xhdpi tablet with 2 GB RAM (without this apps get ART's 16 MB default limit)
$(call inherit-product, frameworks/native/build/tablet-10in-xhdpi-2048-dalvik-heap.mk)

# TEEOS native-CA whitelist + keys that stock EMUI8 ships in the ramdisk. teecd pushes
# /res/native_packages.xml (alongside /system/etc and /vendor/etc copies) to TEEOS via
# TC_NS_set_nativeCA_hash; without all lists TEEOS rejects TA sessions.
# (native_packages.xml is a binary blob, so it is installed by a plain cp rule in Android.mk: PRODUCT_COPY_FILES
# would run xmllint on it because of the .xml extension and fail the build)
PRODUCT_COPY_FILES += \
    device/huawei/AGS2/rootdir/res/keys:root/res/keys

# The install zip repartitions the eMMC from "preas" on (see repartition/repartition.sh): system = filesystem used space + 300 MiB for GApps,
# vendor = used space + 50 MiB, userdata = the rest. The images therefore must be sized by their content (dynamic partition size, reserve
# set in BoardConfig.mk) and the zip needs the script and a static parted (verified build supplied by the maintainer) in install/bin.
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true
PRODUCT_COPY_FILES += \
    device/huawei/AGS2/repartition/parted:install/bin/parted \
    device/huawei/AGS2/repartition/repartition.sh:install/bin/repartition.sh

# Release signing: vendor/ags2-keys/tobim6 must hold releasekey, platform, shared, media, networkstack, bluetooth, nfc, ... .{pk8,x509.pem}
# (the app keys named in LOCAL_CERTIFICATE resolve next to the default release key). The private keys are NOT part of any repo:
# generate them with openssl (CN=Tobim6) and symlink the directory to vendor/ags2-keys/tobim6. Without them the AOSP test keys are used
# and the build says so; work/build_bacon_final.sh refuses to build unsigned.
ifneq ($(wildcard vendor/ags2-keys/tobim6/releasekey.pk8),)
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/ags2-keys/tobim6/releasekey
PRODUCT_EXTRA_RECOVERY_KEYS := vendor/ags2-keys/tobim6/releasekey
else
$(warning AGS2: vendor/ags2-keys/tobim6 not found, signing with the AOSP test keys)
endif

