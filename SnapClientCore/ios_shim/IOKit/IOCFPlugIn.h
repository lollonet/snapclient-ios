/**
 * IOKit/IOCFPlugIn.h stub for iOS
 *
 * IOKit is a macOS-only framework. On iOS, we stub the functions used
 * by getHostId() in utils.hpp. IORegistryEntryCreateCFProperty returns
 * a constant empty CFString (safe to use with CFStringGetCString and
 * CFRelease) so the caller doesn't crash on NULL.
 */

#pragma once

#ifdef IOS

#include <CoreFoundation/CoreFoundation.h>
#include "IOKit/IOTypes.h"

#define kIOPlatformUUIDKey "IOPlatformUUID"

static inline io_registry_entry_t IORegistryEntryFromPath(
    unsigned int masterPort __attribute__((unused)),
    const char* path __attribute__((unused)))
{
    return 0;
}

static inline CFTypeRef IORegistryEntryCreateCFProperty(
    io_registry_entry_t entry __attribute__((unused)),
    CFStringRef key __attribute__((unused)),
    CFAllocatorRef allocator __attribute__((unused)),
    unsigned int options __attribute__((unused)))
{
    // Return a constant empty string. CFSTR("") is immortal, so:
    // - CFStringGetCString returns true with an empty string
    // - CFRelease is a safe no-op on constant strings
    return CFSTR("");
}

#endif // IOS
