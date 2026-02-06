/**
 * sys/sysinfo.h stub for iOS
 *
 * This header doesn't exist on iOS/macOS. Snapcast's utils.hpp includes it
 * behind a `#if !defined(WINDOWS) && !defined(FREEBSD)` guard.
 * Rather than misdefining FREEBSD, we provide this stub so the include
 * succeeds and we can use the correct MACOS define instead.
 */

#pragma once

#ifdef IOS

struct sysinfo {
    long uptime;
};

// sysinfo() is not available on iOS - always fail
static inline int sysinfo(struct sysinfo* info __attribute__((unused))) {
    return -1;
}

#endif // IOS
