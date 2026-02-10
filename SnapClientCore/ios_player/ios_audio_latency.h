/***
    This file is part of snapcast-ios (SnapForge project)
    Copyright (C) 2025  SnapForge contributors

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
***/

#ifndef IOS_AUDIO_LATENCY_H
#define IOS_AUDIO_LATENCY_H

#ifdef __cplusplus
extern "C" {
#endif

/// Query the current iOS audio output latency in milliseconds.
/// This uses AVAudioSession.outputLatency which includes hardware DAC latency.
/// Returns 0 on error or if not available.
double ios_get_audio_output_latency_ms(void);

#ifdef __cplusplus
}
#endif

#endif /* IOS_AUDIO_LATENCY_H */
