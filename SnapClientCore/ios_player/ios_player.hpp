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

// Standard headers
#include <atomic>
#include <mutex>

namespace player
{

/// Player name constant for iOS
static constexpr auto IOS_PLAYER = "ios";

/// Global pause state (shared across all IOSPlayer instances)
/// Used by the bridge to control playback without accessing Controller internals
extern std::atomic<bool> g_ios_player_paused;

/// iOS audio player using AudioQueue Services
class IOSPlayer : public Player
{
public:
    IOSPlayer(boost::asio::io_context& io_context, const ClientSettings::Player& settings, std::shared_ptr<Stream> stream);
    virtual ~IOSPlayer();

    /// iOS doesn't support device enumeration like macOS
    static std::vector<PcmDevice> pcm_list();

    void playerCallback(AudioQueueRef queue, AudioQueueBufferRef buffer);

    /// Pause audio playback (keeps connection alive)
    void pause();

    /// Resume audio playback
    void resume();

    /// @return true if audio is paused
    bool isPaused() const { return g_ios_player_paused.load(); }

protected:
    void worker() override;
    bool needsThread() const override;

private:
    bool initAudioQueue();
    void cleanupAudioQueue();  // Safe cleanup from worker thread

    size_t ms_;
    size_t frames_;
    size_t buff_size_;
    AudioQueueRef queue_{nullptr};
    std::shared_ptr<Stream> pubStream_;
    uint64_t lastChunkTick{0};

    // Thread-safe signaling for callback -> worker communication
    std::atomic<bool> needsReinit_{false};      // Signal worker to reinit audio queue
    std::atomic<bool> shutdownRequested_{false}; // Signal clean shutdown
    std::mutex queueMutex_;                     // Protect queue_ lifecycle (create/destroy)

    // Real-time safety: atomic pointers and state for lock-free callback
    std::atomic<CFRunLoopRef> workerRunLoop_{nullptr};       // Worker's runloop (atomic for callback access)
    std::atomic<AudioQueueTimelineRef> timeLine_{nullptr};   // Timeline (atomic for callback access)
    std::atomic<bool> callbackActive_{false};                // True while callback is executing
    std::atomic<uint32_t> callbackGeneration_{0};            // Incremented on each queue init/cleanup
};

} // namespace player
