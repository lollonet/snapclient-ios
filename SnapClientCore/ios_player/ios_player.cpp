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

namespace player
{

#define NUM_BUFFERS 4

static constexpr auto LOG_TAG = "IOSPlayer";

// AudioQueue callback
void ios_callback(void* custom_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    IOSPlayer* player = static_cast<IOSPlayer*>(custom_data);
    player->playerCallback(queue, buffer);
}


IOSPlayer::IOSPlayer(boost::asio::io_context& io_context, const ClientSettings::Player& settings, std::shared_ptr<Stream> stream)
    : Player(io_context, settings, stream), ms_(150), pubStream_(stream)
{
}


IOSPlayer::~IOSPlayer()
{
}


std::vector<PcmDevice> IOSPlayer::pcm_list()
{
    // iOS doesn't support device enumeration - there's only the system output
    std::vector<PcmDevice> result;
    result.push_back(PcmDevice(0, "Default Output"));
    return result;
}


void IOSPlayer::playerCallback(AudioQueueRef queue, AudioQueueBufferRef bufferRef)
{
    // Estimate the playout delay by checking the number of frames left in the buffer
    // and add ms_ (= complete buffer size). Based on trying.
    AudioTimeStamp timestamp;
    AudioQueueGetCurrentTime(queue, timeLine_, &timestamp, NULL);
    size_t bufferedFrames = (frames_ - ((uint64_t)timestamp.mSampleTime % frames_)) % frames_;
    size_t bufferedMs = bufferedFrames * 1000 / pubStream_->getFormat().rate() + (ms_ * (NUM_BUFFERS - 1));
    // 15ms DAC delay. Based on trying.
    bufferedMs += 15;

    chronos::usec delay(bufferedMs * 1000);
    char* buffer = (char*)bufferRef->mAudioData;
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
    // Note: AudioQueueCreateTimeline already called above - don't duplicate
    status = AudioQueueStart(queue, NULL);
    if (status != noErr)
    {
        LOG(ERROR, LOG_TAG) << "AudioQueueStart failed: " << status << "\n";
        AudioQueueDispose(queue, true);
        return false;
    }

    CFRunLoopRun();
    return true;
}


void IOSPlayer::uninitAudioQueue(AudioQueueRef queue)
{
    AudioQueueStop(queue, false);
    AudioQueueDispose(queue, false);
    pubStream_->clearChunks();
    CFRunLoopStop(CFRunLoopGetCurrent());
}

} // namespace player
