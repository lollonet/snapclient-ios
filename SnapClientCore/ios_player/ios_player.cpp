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
#include <thread>

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
    LOG(INFO, LOG_TAG) << "Destroying IOSPlayer, requesting shutdown\n";

    // Signal shutdown to the worker thread
    shutdownRequested_.store(true, std::memory_order_release);

    // Wake up worker thread if it's blocked in CFRunLoopRun
    CFRunLoopRef runLoop = workerRunLoop_.load(std::memory_order_acquire);
    if (runLoop)
    {
        CFRunLoopStop(runLoop);
    }

    // CRITICAL: Call stop() to join the worker thread BEFORE this destructor
    // returns. The base class destructor will also call stop(), but we must
    // do it here because:
    // 1. The base class checks `if (active_)` before joining
    // 2. If we set active_=false here, the base class skips the join
    // 3. The worker thread then accesses destroyed IOSPlayer members = crash
    //
    // By calling stop() here (while active_ is still true), we ensure the
    // thread is properly joined before IOSPlayer members are destroyed.
    stop();
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
    g_ios_player_paused.store(true, std::memory_order_release);

    // AudioQueue APIs are thread-safe, no mutex needed here.
    // queueMutex_ is only for protecting queue_ lifecycle (create/destroy).
    std::lock_guard<std::mutex> lock(queueMutex_);
    if (queue_)
    {
        AudioQueuePause(queue_);
    }
}


void IOSPlayer::resume()
{
    LOG(INFO, LOG_TAG) << "Resuming audio playback\n";
    g_ios_player_paused.store(false, std::memory_order_release);

    // AudioQueue APIs are thread-safe, no mutex needed here.
    std::lock_guard<std::mutex> lock(queueMutex_);
    if (queue_)
    {
        AudioQueueStart(queue_, NULL);
    }
}


void IOSPlayer::playerCallback(AudioQueueRef queue, AudioQueueBufferRef bufferRef)
{
    // RAII guard to mark callback active and signal completion on exit.
    // This ensures cleanupAudioQueue can wait for callback to fully exit.
    struct CallbackActiveGuard {
        IOSPlayer* player;
        CallbackActiveGuard(IOSPlayer* p) : player(p) {
            player->callbackActive_.store(true, std::memory_order_release);
        }
        ~CallbackActiveGuard() {
            player->callbackActive_.store(false, std::memory_order_release);
            // Signal condition variable that callback has exited
            player->callbackDone_.notify_all();
        }
    } activeGuard(this);

    // Capture generation to detect queue invalidation
    const uint32_t myGeneration = callbackGeneration_.load(std::memory_order_acquire);

    char* buffer = (char*)bufferRef->mAudioData;

    // Fast path: paused - fill silence, no blocking
    if (g_ios_player_paused.load(std::memory_order_relaxed))
    {
        memset(buffer, 0, bufferRef->mAudioDataByteSize);
        AudioQueueEnqueueBuffer(queue, bufferRef, 0, NULL);
        return;  // activeGuard destructor signals callbackDone_
    }

    // Check shutdown - use atomic load, never check non-atomic active_
    if (shutdownRequested_.load(std::memory_order_relaxed))
    {
        needsReinit_.store(true, std::memory_order_relaxed);
        // Load runloop ref atomically
        CFRunLoopRef rl = workerRunLoop_.load(std::memory_order_acquire);
        if (rl) CFRunLoopStop(rl);
        return;  // Don't enqueue buffer - let queue drain
    }

    // Verify our queue generation is still valid
    if (myGeneration != callbackGeneration_.load(std::memory_order_acquire))
    {
        // Queue was invalidated while we were running
        return;
    }

    // Estimate the playout delay by checking the number of frames left in the buffer
    // and add ms_ (= complete buffer size). Based on trying.
    size_t bufferedMs = ms_ * (NUM_BUFFERS - 1);  // Default if no timeline

    // Timeline access - load atomically (timeline is only valid while queue_ is set)
    AudioQueueTimelineRef tl = timeLine_.load(std::memory_order_acquire);
    if (tl)
    {
        AudioTimeStamp timestamp;
        AudioQueueGetCurrentTime(queue, tl, &timestamp, NULL);
        size_t bufferedFrames = (frames_ - ((uint64_t)timestamp.mSampleTime % frames_)) % frames_;
        bufferedMs = bufferedFrames * 1000 / pubStream_->getFormat().rate() + (ms_ * (NUM_BUFFERS - 1));
    }
    // 15ms DAC delay. Based on trying.
    bufferedMs += 15;

    chronos::usec delay(bufferedMs * 1000);
    if (!pubStream_->getPlayerChunkOrSilence(buffer, delay, frames_))
    {
        if (chronos::getTickCount() - lastChunkTick > 5000)
        {
            // CRITICAL FIX: Signal worker thread, don't call uninitAudioQueue from callback!
            // Calling AudioQueue functions from callback context causes deadlock.
            LOG(NOTICE, LOG_TAG) << "No chunk received for 5000ms. Signaling reinit.\n";
            needsReinit_.store(true, std::memory_order_relaxed);
            CFRunLoopRef rl = workerRunLoop_.load(std::memory_order_acquire);
            if (rl) CFRunLoopStop(rl);
            return;  // Don't enqueue buffer
        }
    }
    else
    {
        lastChunkTick = chronos::getTickCount();
        adjustVolume(buffer, frames_);
    }

    AudioQueueEnqueueBuffer(queue, bufferRef, 0, NULL);
    // activeGuard destructor signals callbackDone_
}


bool IOSPlayer::needsThread() const
{
    return true;
}


void IOSPlayer::worker()
{
    // Boost thread priority for real-time audio
    setRealtimeThreadPriority();
    workerRunLoop_.store(CFRunLoopGetCurrent(), std::memory_order_release);
    LOG(INFO, LOG_TAG) << "Audio worker thread started with real-time priority\n";

    while (active_ && !shutdownRequested_.load(std::memory_order_acquire))
    {
        needsReinit_.store(false, std::memory_order_relaxed);

        if (pubStream_->waitForChunk(std::chrono::milliseconds(100)))
        {
            try
            {
                if (initAudioQueue())
                {
                    // CFRunLoopRun blocks until CFRunLoopStop is called
                    CFRunLoopRun();

                    // After runloop exits, cleanup in THIS thread context (safe)
                    // This is the critical fix - cleanup happens here, not in callback
                    cleanupAudioQueue();
                }
                else
                {
                    LOG(WARNING, LOG_TAG) << "Audio queue init failed, retrying...\n";
                }
            }
            catch (const std::exception& e)
            {
                LOG(ERROR, LOG_TAG) << "Exception in worker: " << e.what() << "\n";
            }
        }

        // Only sleep if not being asked to reinit immediately
        if (!needsReinit_.load(std::memory_order_relaxed))
            chronos::sleep(100);
    }

    workerRunLoop_.store(nullptr, std::memory_order_release);
    LOG(INFO, LOG_TAG) << "Audio worker thread exiting\n";
}


bool IOSPlayer::initAudioQueue()
{
    // Guard against double initialization (would leak AudioQueue)
    if (queue_)
    {
        LOG(WARNING, LOG_TAG) << "AudioQueue already initialized, skipping\n";
        return false;
    }

    // Increment generation for this new queue session
    callbackGeneration_.fetch_add(1, std::memory_order_acq_rel);

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

    // Store queue reference for pause/resume (with mutex protection)
    {
        std::lock_guard<std::mutex> lock(queueMutex_);
        queue_ = queue;
    }

    // Create timeline and store atomically
    AudioQueueTimelineRef timeline = nullptr;
    status = AudioQueueCreateTimeline(queue, &timeline);
    if (status == noErr)
    {
        timeLine_.store(timeline, std::memory_order_release);
    }
    else
    {
        LOG(WARNING, LOG_TAG) << "AudioQueueCreateTimeline failed: " << status << " (non-fatal)\n";
        timeLine_.store(nullptr, std::memory_order_release);
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
    if (!g_ios_player_paused.load(std::memory_order_relaxed))
    {
        status = AudioQueueStart(queue, NULL);
        if (status != noErr)
        {
            LOG(ERROR, LOG_TAG) << "AudioQueueStart failed: " << status << "\n";
            timeLine_.store(nullptr, std::memory_order_release);
            {
                std::lock_guard<std::mutex> lock(queueMutex_);
                queue_ = nullptr;
            }
            AudioQueueDispose(queue, true);
            return false;
        }
    }
    else
    {
        LOG(INFO, LOG_TAG) << "Audio queue created but paused\n";
    }

    // Worker thread calls CFRunLoopRun after this returns
    return true;
}


void IOSPlayer::cleanupAudioQueue()
{
    // Step 1: Increment generation to invalidate any in-flight callbacks
    callbackGeneration_.fetch_add(1, std::memory_order_acq_rel);

    // Step 2: Stop queue synchronously - this drains pending callbacks
    std::lock_guard<std::mutex> lock(queueMutex_);

    if (!queue_)
        return;

    AudioQueueRef q = queue_;
    queue_ = nullptr;

    // Synchronous stop with inImmediate=true:
    // Apple docs: "Stops the audio queue synchronously. The function returns
    // when the audio queue has stopped running."
    // After this returns, no new callbacks will be scheduled.
    AudioQueueStop(q, true);

    // Step 3: Wait for callback to fully exit using condition variable.
    // AudioQueueStop(q, true) should guarantee no callbacks are running,
    // but we use a bounded wait as a safety net with logging.
    {
        std::unique_lock<std::mutex> cvLock(callbackMutex_);
        auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
        if (!callbackDone_.wait_until(cvLock, deadline, [this] {
            return !callbackActive_.load(std::memory_order_acquire);
        }))
        {
            // This should never happen if AudioQueueStop works correctly.
            // Log but proceed - the callback will see stale generation and exit.
            LOG(ERROR, LOG_TAG) << "Callback still active after 500ms wait - proceeding anyway. "
                                << "This indicates AudioQueueStop did not drain callbacks.\n";
        }
    }

    // Step 4: Now safe to dispose timeline - callback has exited
    AudioQueueTimelineRef tl = timeLine_.exchange(nullptr, std::memory_order_acq_rel);
    if (tl)
    {
        AudioQueueDisposeTimeline(q, tl);
    }

    AudioQueueDispose(q, true);
    pubStream_->clearChunks();

    LOG(DEBUG, LOG_TAG) << "Audio queue cleaned up safely\n";
}

} // namespace player
