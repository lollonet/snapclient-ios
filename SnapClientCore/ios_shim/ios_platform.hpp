/**
 * ios_platform.hpp
 *
 * Platform compatibility shim for iOS.
 * Snapcast was originally written for Linux/macOS - this header provides
 * iOS-compatible replacements for missing headers and functions.
 *
 * Note: This file is NOT auto-included. The actual compatibility is
 * achieved through:
 *  - ios_shim/sys/sysinfo.h        (stub header found via include path)
 *  - ios_shim/IOKit/IOTypes.h       (stub for IOKit types)
 *  - ios_shim/IOKit/IOCFPlugIn.h    (stub for IOKit functions)
 *  - ios_shim/CoreAudio/CoreAudio.h (stub for macOS AudioHardware APIs)
 *  - ios_shim/ios_popen_override.h  (force-included: disables popen/fork)
 *  - CMake defines: IOS, MACOS, HAS_COREAUDIO
 */

#pragma once

#ifdef IOS

// iOS uses AudioToolbox instead of CoreAudio for AudioQueue
#include <AudioToolbox/AudioToolbox.h>

// Suppress the CoreAudio/CoreAudio.h include on iOS
#define COREAUDIO_COREAUDIO_H

#endif // IOS
