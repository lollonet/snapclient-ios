/***
    This file is part of snapcast-ios (SnapForge project)
    Based on coreaudio_player.cpp from Snapcast
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

#include "ios_player.hpp"

// local headers
#include "common/aixlog.hpp"

// Thread priority for real-time audio
#include <pthread.h>
#include <mach/mach.h>
#include <mach/thread_policy.h>

namespace player
{

// Global pause state for bridge control
std::atomic<bool> g_ios_player_paused{false};

/// Set real-time thread priority for audio work
static void setRealtimeThreadPriority()
{
    // Get current thread
    mach_port_t thread = mach_thread_self();

    // Set thread to time-constraint (real-time) policy
    thread_time_constraint_policy_data_t policy;
    policy.period = 0;        // Default period
    policy.computation = 10000000;  // 10ms computation time
    policy.constraint = 20000000;   // 20ms constraint
    policy.preemptible = TRUE;

    kern_return_t result = thread_policy_set(
        thread,
        THREAD_TIME_CONSTRAINT_POLICY,
        (thread_policy_t)&policy,
        THREAD_TIME_CONSTRAINT_POLICY_COUNT
    );

    if (result != KERN_SUCCESS)
    {
        // Fall back to high priority via pthread
        struct sched_param param;
        param.sched_priority = sched_get_priority_max(SCHED_FIFO);
        pthread_setschedparam(pthread_self(), SCHED_FIFO, &param);
    }

    mach_port_deallocate(mach_task_self(), thread);
}

#define NUM_BUFFERS 4

static constexpr auto LOG_TAG = "IOSPlayer";

// AudioQueue callback
void ios_callback(void* custom_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    IOSPlayer* player = static_cast<IOSPlayer*>(custom_data);
    player->playerCallback(queue, buffer);
}


IOSPlayer::IOSPlayer(boost::asio::io_context& io_context, const ClientSettings::Player& settings, std::shared_ptr<Stream> stream)
    : Player(io_context, settings, stream), ms_(100), pubStream_(stream)  // 100ms buffer (400ms total with 4 buffers)
{
}


IOSPlayer::~IOSPlayer()
{
}


std::vector<PcmDevice> IOSPlayer::pcm_list()
{
    // iOS doesn't support device enumeration - there's only the system output
    std::vector<PcmDevice> devices;
    devices.push_back(PcmDevice(0, "Default Output"));
    return devices;
}


void IOSPlayer::pause()
{
    LOG(INFO, LOG_TAG) << "Pausing audio playback\n";
    g_ios_player_paused.store(true);
    if (queue_)
    {
        AudioQueuePause(queue_);
    }
}


void IOSPlayer::resume()
{
    LOG(INFO, LOG_TAG) << "Resuming audio playback\n";
    g_ios_player_paused.store(false);
    if (queue_)
    {
        AudioQueueStart(queue_, NULL);
    }
}


void IOSPlayer::playerCallback(AudioQueueRef queue, AudioQueueBufferRef bufferRef)
{
    char* buffer = (char*)bufferRef->mAudioData;

    // If paused, output silence instead of actual audio
    if (g_ios_player_paused.load())
    {
        memset(buffer, 0, bufferRef->mAudioDataByteSize);
        AudioQueueEnqueueBuffer(queue, bufferRef, 0, NULL);
        return;
    }

    // Estimate the playout delay by checking the number of frames left in the buffer
    // and add ms_ (= complete buffer size). Based on trying.
    AudioTimeStamp timestamp;
    AudioQueueGetCurrentTime(queue, timeLine_, &timestamp, NULL);
    size_t bufferedFrames = (frames_ - ((uint64_t)timestamp.mSampleTime % frames_)) % frames_;
    size_t bufferedMs = bufferedFrames * 1000 / pubStream_->getFormat().rate() + (ms_ * (NUM_BUFFERS - 1));
    // 15ms DAC delay. Based on trying.
    bufferedMs += 15;

    chronos::usec delay(bufferedMs * 1000);
    if (!pubStream_->getPlayerChunkOrSilence(buffer, delay, frames_))
    {
        if (chronos::getTickCount() - lastChunkTick > 5000)
        {
            LOG(NOTICE, LOG_TAG) << "No chunk received for 5000ms. Closing Audio Queue.\n";
            uninitAudioQueue(queue);
            return;
        }
    }
    else
    {
        lastChunkTick = chronos::getTickCount();
        adjustVolume(buffer, frames_);
    }

    AudioQueueEnqueueBuffer(queue, bufferRef, 0, NULL);

    if (!active_)
    {
        uninitAudioQueue(queue);
    }
}


bool IOSPlayer::needsThread() const
{
    return true;
}


void IOSPlayer::worker()
{
    // Boost thread priority for real-time audio
    setRealtimeThreadPriority();
    LOG(INFO, LOG_TAG) << "Audio worker thread started with real-time priority\n";

    while (active_)
    {
        if (pubStream_->waitForChunk(std::chrono::milliseconds(100)))
        {
            try
            {
                if (!initAudioQueue())
                {
                    LOG(WARNING, LOG_TAG) << "Audio queue init failed, retrying...\n";
                }
            }
            catch (const std::exception& e)
            {
                LOG(ERROR, LOG_TAG) << "Exception in worker: " << e.what() << "\n";
            }
            chronos::sleep(100);
        }
        chronos::sleep(100);
    }
}


bool IOSPlayer::initAudioQueue()
{
    const SampleFormat& sampleFormat = pubStream_->getFormat();

    AudioStreamBasicDescription format;
    format.mSampleRate = sampleFormat.rate();
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;
    format.mBitsPerChannel = sampleFormat.bits();
    format.mChannelsPerFrame = sampleFormat.channels();
    format.mBytesPerFrame = sampleFormat.frameSize();
    format.mFramesPerPacket = 1;
    format.mBytesPerPacket = format.mBytesPerFrame * format.mFramesPerPacket;
    format.mReserved = 0;

    AudioQueueRef queue;
    OSStatus status = AudioQueueNewOutput(&format, ios_callback, this, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &queue);
    if (status != noErr)
    {
        LOG(ERROR, LOG_TAG) << "AudioQueueNewOutput failed: " << status << "\n";
        return false;
    }

    // Store queue reference for pause/resume
    queue_ = queue;

    status = AudioQueueCreateTimeline(queue, &timeLine_);
    if (status != noErr)
    {
        LOG(WARNING, LOG_TAG) << "AudioQueueCreateTimeline failed: " << status << " (non-fatal)\n";
        // Non-fatal, continue without timeline
    }

    // Calculate buffer size for ~100ms
    frames_ = (sampleFormat.rate() * ms_) / 1000;
    ms_ = frames_ * 1000 / sampleFormat.rate();
    buff_size_ = frames_ * sampleFormat.frameSize();
    LOG(INFO, LOG_TAG) << "frames: " << frames_ << ", ms: " << ms_ << ", buffer size: " << buff_size_ << "\n";

    AudioQueueBufferRef buffers[NUM_BUFFERS];
    for (int i = 0; i < NUM_BUFFERS; i++)
    {
        AudioQueueAllocateBuffer(queue, buff_size_, &buffers[i]);
        buffers[i]->mAudioDataByteSize = buff_size_;
        ios_callback(this, queue, buffers[i]);
    }

    LOG(DEBUG, LOG_TAG) << "IOSPlayer::initAudioQueue starting\n";
    // Start in paused state if already paused (use global as source of truth)
    if (!g_ios_player_paused.load())
    {
        status = AudioQueueStart(queue, NULL);
        if (status != noErr)
        {
            LOG(ERROR, LOG_TAG) << "AudioQueueStart failed: " << status << "\n";
            queue_ = nullptr;
            AudioQueueDispose(queue, true);
            return false;
        }
    }
    else
    {
        LOG(INFO, LOG_TAG) << "Audio queue created but paused\n";
    }

    CFRunLoopRun();
    return true;
}


void IOSPlayer::uninitAudioQueue(AudioQueueRef queue)
{
    queue_ = nullptr;
    AudioQueueStop(queue, false);
    AudioQueueDispose(queue, false);
    pubStream_->clearChunks();
    CFRunLoopStop(CFRunLoopGetCurrent());
}

} // namespace player
