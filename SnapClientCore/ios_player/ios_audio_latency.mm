/***
    This file is part of snapcast-ios (SnapForge project)
    Copyright (C) 2025  SnapForge contributors

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
***/

#import "ios_audio_latency.h"
#import <AVFoundation/AVFoundation.h>

double ios_get_audio_output_latency_ms(void) {
    @autoreleasepool {
        AVAudioSession *session = [AVAudioSession sharedInstance];

        // outputLatency is the latency for audio output in seconds
        // This includes the hardware DAC latency
        NSTimeInterval latency = session.outputLatency;

        // Convert to milliseconds
        return latency * 1000.0;
    }
}
