/**
 * IOKit/IOTypes.h stub for iOS
 *
 * IOKit is a macOS-only framework. Snapcast's utils.hpp includes this
 * under #ifdef MACOS for hardware UUID retrieval. On iOS we provide
 * stubs that compile but return failure, causing getHostId() to fall
 * through to getHostName().
 */

#pragma once

#ifdef IOS

typedef unsigned int io_object_t;
typedef io_object_t io_registry_entry_t;

#define kIOMasterPortDefault 0

static inline void IOObjectRelease(io_object_t obj) {
    (void)obj;
}

#endif // IOS
