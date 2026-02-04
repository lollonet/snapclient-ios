/**
 * ios_platform.hpp
 *
 * Platform compatibility shim for iOS.
 * Snapcast was originally written for Linux/macOS - this header provides
 * iOS-compatible replacements for missing headers and functions.
 */

#pragma once

#ifdef IOS

// iOS doesn't have sys/sysinfo.h - provide stub
// Used for getting system uptime, not critical for client
#define sysinfo(x) (-1)
struct sysinfo {
    long uptime;
};

// iOS uses AudioToolbox instead of CoreAudio for AudioQueue
// CoreAudio.h on iOS is missing - use AudioToolbox
#include <AudioToolbox/AudioToolbox.h>

// Suppress the CoreAudio/CoreAudio.h include on iOS
#define COREAUDIO_COREAUDIO_H

// iOS-specific: No device enumeration via AudioHardware
// (AudioHardware APIs are macOS-only)
#define kAudioHardwarePropertyDevices 0
#define kAudioObjectSystemObject 0
#define kAudioObjectPropertyScopeGlobal 0
#define kAudioObjectPropertyElementMaster 0
#define kAudioDevicePropertyStreamConfiguration 0
#define kAudioDevicePropertyScopeOutput 0
#define kAudioDeviceUnknown 0

// Stub functions for macOS-only AudioObject APIs
inline OSStatus AudioObjectGetPropertyDataSize(UInt32, const void*, UInt32, const void*, UInt32*) { return -1; }
inline OSStatus AudioObjectGetPropertyData(UInt32, const void*, UInt32, const void*, UInt32*, void*) { return -1; }

// IOKit is not available on iOS
#ifdef MACOS
#undef MACOS
#endif

#endif // IOS
