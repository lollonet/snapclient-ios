/**
 * CoreAudio/CoreAudio.h shim for iOS
 *
 * On iOS, CoreAudio.h doesn't exist. AudioQueue APIs come from AudioToolbox.
 * This shim provides the necessary types and stubs to compile coreaudio_player.cpp.
 */

#pragma once

#ifdef IOS

// AudioQueue and related types come from AudioToolbox
#include <AudioToolbox/AudioToolbox.h>

// macOS-only AudioObject types - stub them out
typedef UInt32 AudioDeviceID;
typedef struct AudioObjectPropertyAddress {
    UInt32 mSelector;
    UInt32 mScope;
    UInt32 mElement;
} AudioObjectPropertyAddress;

// macOS AudioHardware constants - not used on iOS
#define kAudioHardwarePropertyDevices 0
#define kAudioObjectSystemObject 0
#define kAudioObjectPropertyScopeGlobal 0
#define kAudioObjectPropertyElementMaster 0
#define kAudioDevicePropertyStreamConfiguration 0
#define kAudioDevicePropertyScopeOutput 0
#define kAudioDeviceUnknown 0
#define kAudioDevicePropertyDeviceName 0

// Stub functions - these always fail on iOS (no device enumeration)
inline OSStatus AudioObjectGetPropertyDataSize(UInt32, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32* size) {
    *size = 0;
    return -1;
}

inline OSStatus AudioObjectGetPropertyData(UInt32, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32*, void*) {
    return -1;
}

#endif // IOS
