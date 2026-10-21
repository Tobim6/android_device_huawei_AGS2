LOCAL_PATH := $(call my-dir)

# The EMUI8-generation Mali GPU driver blob (vendor/lib64/egl/libGLES_mali.so,
# swapped in to match our EMUI8 kernel) was built against an older AOSP tree
# where android::CallStack still lived directly inside libutils.so. This AOSP
# tree split CallStack out into a separate libutilscallstack.so, so the vendor
# blob's DT_NEEDED "libutils.so" can never resolve
# _ZN7android9CallStackC1EPKci (android::CallStack::CallStack(char const*,
# int)) through the system partition's libutils.so -- and libutils.so isn't
# an LLNDK library, so the sphal namespace can't reach the system copy
# cross-namespace either way.
#
# sphal's own search path includes /vendor/${LIB} directly, so a vendor-local
# "libutils.so" that re-exports CallStack alongside the normal libutils API
# satisfies the vendor blob without touching the real system libutils.so at
# all. This mirrors the same "private vendor copy of a system library"
# pattern Treble's VNDK-SP snapshots use for exactly this kind of ABI gap.
#
# BUILD_SHARED_LIBRARY explicitly refuses LOCAL_MODULE_STEM ("Cannot set
# module stem for a library"), so this builds under its own module name
# first, then two ETC-class copy modules (which don't have that restriction)
# install it under the final "libutils.so" name per architecture.
include $(CLEAR_VARS)
LOCAL_MODULE := libutils_vendor_callstack_compat
LOCAL_MODULE_TAGS := optional
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MULTILIB := both
LOCAL_SRC_FILES := CallStack.cpp
LOCAL_WHOLE_STATIC_LIBRARIES := libutils
LOCAL_SHARED_LIBRARIES := liblog libcutils libdl libvndksupport
LOCAL_CFLAGS := -Wall -Werror
include $(BUILD_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := libutils_vendor_callstack_compat_as_libutils_64
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_STEM := libutils.so
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/lib64
LOCAL_PREBUILT_MODULE_FILE := $(TARGET_OUT_VENDOR)/lib64/libutils_vendor_callstack_compat.so
LOCAL_REQUIRED_MODULES := libutils_vendor_callstack_compat
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := libutils_vendor_callstack_compat_as_libutils_32
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_STEM := libutils.so
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/lib
LOCAL_PREBUILT_MODULE_FILE := $(TARGET_OUT_VENDOR)/lib/libutils_vendor_callstack_compat.so
LOCAL_REQUIRED_MODULES := libutils_vendor_callstack_compat
include $(BUILD_PREBUILT)
