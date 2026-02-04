/***
    This file is part of snapcast-ios (SnapForge project)
    Based on coreaudio_player.hpp from Snapcast
    Copyright (C) 2014-2023  Johannes Pohl
    Copyright (C) 2025  SnapForge contributors

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
***/

#pragma once

// local headers
#include "client_settings.hpp"
#include "player/player.hpp"
#include "stream.hpp"

// iOS AudioToolbox
#include <AudioToolbox/AudioToolbox.h>

namespace player
{

/// Player name constant for iOS
static constexpr auto IOS = "ios";

/// iOS audio player using AudioQueue Services
class IOSPlayer : public Player
{
public:
    IOSPlayer(boost::asio::io_context& io_context, const ClientSettings::Player& settings, std::shared_ptr<Stream> stream);
    virtual ~IOSPlayer();

    /// iOS doesn't support device enumeration like macOS
    static std::vector<PcmDevice> pcm_list();

    void playerCallback(AudioQueueRef queue, AudioQueueBufferRef buffer);

protected:
    void worker() override;
    bool needsThread() const override;

private:
    void initAudioQueue();
    void uninitAudioQueue(AudioQueueRef queue);

    size_t ms_;
    size_t frames_;
    size_t buff_size_;
    AudioQueueTimelineRef timeLine_;
    std::shared_ptr<Stream> pubStream_;
    uint64_t lastChunkTick{0};
};

} // namespace player
