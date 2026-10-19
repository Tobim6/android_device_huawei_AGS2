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

# Inherit from hi6250-common
$(call inherit-product, device/huawei/hi6250-common/hi6250.mk)
