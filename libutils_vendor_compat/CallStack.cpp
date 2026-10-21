/*
 * Copyright (C) 2007 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Minimal stub reimplementation for the vendor-local libutils.so compat shim
// (see Android.mk for why this exists). The real implementation needs
// libbacktrace, which is vendor_available: false -- not usable from vendor
// code at all, not just a link-order issue. The Mali GPU driver blob this
// is built for only needs these symbols to exist so the dynamic linker can
// resolve them; CallStack is used there purely for diagnostic logging on
// rare error paths, not normal operation, so never capturing a real
// backtrace here is an acceptable tradeoff.

#define LOG_TAG "CallStack"

#include <utils/CallStack.h>

#include <utils/Printer.h>
#include <utils/Errors.h>
#include <utils/Log.h>

namespace android {

CallStack::CallStack() {
}

CallStack::CallStack(const char* logtag, int32_t ignoreDepth) {
    this->update(ignoreDepth+1);
    this->log(logtag);
}

CallStack::~CallStack() {
}

void CallStack::update(int32_t /*ignoreDepth*/, pid_t /*tid*/) {
    mFrameLines.clear();
    mFrameLines.push_back(String8("<call stack capture not available>"));
}

void CallStack::log(const char* logtag, android_LogPriority priority, const char* prefix) const {
    LogPrinter printer(logtag, priority, prefix, /*ignoreBlankLines*/false);
    print(printer);
}

void CallStack::dump(int fd, int indent, const char* prefix) const {
    FdPrinter printer(fd, indent, prefix);
    print(printer);
}

String8 CallStack::toString(const char* prefix) const {
    String8 str;

    String8Printer printer(&str, prefix);
    print(printer);

    return str;
}

void CallStack::print(Printer& printer) const {
    for (size_t i = 0; i < mFrameLines.size(); i++) {
        printer.printLine(mFrameLines[i]);
    }
}

}; // namespace android
