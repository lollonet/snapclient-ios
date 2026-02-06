# Code Quality Fixes for snapclient-ios

## Context

This document describes fixes for issues identified during code review of commits `7bdc872..c0f7da7` in the snapclient-ios project.

---

## Fix 1: Race Condition in Bridge State Notification

**File:** `SnapClientCore/bridge/snapclient_bridge.cpp`

**Problem:** In `snapclient_start()`, the io_thread might call `notify_state(DISCONNECTED)` immediately if connection fails, racing with the main thread's `notify_state(CONNECTED)` call.

**Fix:** Only notify CONNECTED after confirming the controller started successfully, and use a connection confirmation mechanism:

```cpp
bool snapclient_start(SnapClientRef client, const char* host, int port) {
    if (!client || !host) return false;

    std::lock_guard<std::mutex> lock(client->mutex);
    if (client->state.load() != SNAPCLIENT_STATE_DISCONNECTED) {
        return false;
    }

    client->host = host;
    client->port = port;
    notify_state(client, SNAPCLIENT_STATE_CONNECTING);

    try {
        client->io_context = std::make_unique<boost::asio::io_context>();
        client->work_guard = std::make_unique<work_guard_t>(client->io_context->get_executor());

        ClientSettings settings;
        settings.server.uri = StreamUri("tcp://" + client->host + ":" + std::to_string(client->port));
        settings.player.player_name = "ios";
        settings.player.latency = client->latency_ms.load();
        settings.instance = client->instance;
        settings.host_id = client->name;

        client->controller = std::make_unique<Controller>(*client->io_context, settings);
        client->controller->start();

        // Start io_thread - state changes happen via Controller callbacks
        client->io_thread = std::thread([client]() {
            try {
                client->io_context->run();
            } catch (const std::exception& e) {
                LOG(ERROR, "Bridge") << "io_context exception: " << e.what() << "\n";
            }
            // Only notify disconnected if we were previously connected
            if (client->state.load() != SNAPCLIENT_STATE_DISCONNECTED) {
                notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
            }
        });

        // Mark as connected (Controller will update to PLAYING when stream starts)
        notify_state(client, SNAPCLIENT_STATE_CONNECTED);
        return true;

    } catch (const std::exception& e) {
        LOG(ERROR, "Bridge") << "Failed to start: " << e.what() << "\n";
        // Cleanup on failure
        client->controller.reset();
        client->work_guard.reset();
        client->io_context.reset();
        notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
        return false;
    }
}
```

---

## Fix 2: Duplicate AudioQueueCreateTimeline Call

**File:** `SnapClientCore/ios_player/ios_player.cpp`

**Problem:** `AudioQueueCreateTimeline()` is called twice in `initAudioQueue()` (lines 148 and 165).

**Fix:** Remove the duplicate call at line 165:

```cpp
void IOSPlayer::initAudioQueue()
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
        return;
    }

    // Create timeline for timing info (only once)
    AudioQueueCreateTimeline(queue, &timeLine_);

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
    // REMOVED: duplicate AudioQueueCreateTimeline call was here
    AudioQueueStart(queue, NULL);
    CFRunLoopRun();
}
```

---

## Fix 3: Return Status from initAudioQueue

**File:** `SnapClientCore/ios_player/ios_player.cpp`

**Problem:** `initAudioQueue()` silently fails without indicating success/failure to callers.

**Fix:** Change return type to bool and propagate errors:

**In `ios_player.hpp`:**
```cpp
// Change declaration
bool initAudioQueue();
```

**In `ios_player.cpp`:**
```cpp
bool IOSPlayer::initAudioQueue()
{
    const SampleFormat& sampleFormat = pubStream_->getFormat();

    AudioStreamBasicDescription format;
    // ... format setup ...

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
        LOG(WARNING, LOG_TAG) << "AudioQueueCreateTimeline failed: " << status << "\n";
        // Non-fatal, continue without timeline
    }

    // ... rest of setup ...

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
```

**Update worker():**
```cpp
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
```

---

## Fix 4: Prevent Duplicate Audio Session Observers

**File:** `SnapClient/Engine/SnapClientEngine.swift`

**Problem:** If `setupAudioSessionObservers()` were called multiple times, old observers wouldn't be removed.

**Fix:** Remove existing observer before adding new one:

```swift
private func setupAudioSessionObservers() {
    // Remove existing observer if any
    if let observer = interruptionObserver {
        NotificationCenter.default.removeObserver(observer)
        interruptionObserver = nil
    }

    interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
    ) { [weak self] notification in
        Task { @MainActor in
            self?.handleAudioInterruption(notification)
        }
    }
}
```

---

## Fix 5: Exponential Backoff for Reconnection

**File:** `SnapClient/Engine/SnapClientEngine.swift`

**Problem:** Fixed 2-second reconnect delay may hammer the server or drain battery.

**Fix:** Implement exponential backoff:

```swift
// Add properties
private var reconnectAttempts: Int = 0
private let maxReconnectDelay: TimeInterval = 60.0
private let baseReconnectDelay: TimeInterval = 2.0

private func scheduleReconnect() {
    reconnectTask?.cancel()

    // Exponential backoff: 2, 4, 8, 16, 32, 60 (capped)
    let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
    reconnectAttempts += 1

    reconnectTask = Task { [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.reconnect()
        }
    }
}

// Reset attempts on successful connection
private func handleStateChange(_ newState: SnapClientState) {
    let oldState = state
    state = newState

    if newState == .connected || newState == .playing {
        reconnectAttempts = 0  // Reset on successful connection
    }

    if oldState.isActive && newState == .disconnected &&
       autoReconnect && connectedHost != nil {
        scheduleReconnect()
    }
}
```

---

## Testing Checklist

After applying fixes:

1. [ ] Build for iOS device (`./scripts/build-deps.sh`)
2. [ ] Build for iOS Simulator (`./scripts/build-deps-sim.sh`)
3. [ ] Run on device - verify connection/disconnection cycle
4. [ ] Test reconnection by toggling airplane mode
5. [ ] Test audio interruption (trigger phone call or Siri)
6. [ ] Verify no memory leaks with Instruments

---

## Priority

| Fix | Severity | Effort |
|-----|----------|--------|
| Fix 2 (duplicate timeline) | Low | 1 min |
| Fix 4 (observer leak) | Low | 2 min |
| Fix 3 (return status) | Medium | 10 min |
| Fix 5 (backoff) | Medium | 10 min |
| Fix 1 (race condition) | Medium | 15 min |
