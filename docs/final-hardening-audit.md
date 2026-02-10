# 🛡️ Final Hardening Audit: "Precision & Scale"

**Status:** Advanced Production Grade  
**Audit Date:** February 8, 2026

This audit identifies four specific, verifiable bugs related to multi-instance management, protocol compliance, and audio synchronization precision.

---

## 🚩 Critical Forensic Findings

### 1. Global Log Callback "Hijacking" (Multi-Instance)
In `snapclient_bridge.cpp`, the log callback is stored in a file-level static variable:
```cpp
static SnapClientLogCallback g_log_cb = nullptr;
void snapclient_set_log_callback(SnapClientLogCallback callback, void* ctx) {
    g_log_cb = callback; // Shared by ALL instances
}
```
*   **The Bug:** If you have two engines, `Engine B` overwrites the callback for `Engine A`.
*   **The Failure:** When `Engine A` is destroyed, its `deinit` calls `snapclient_set_log_callback(nil, nil)`. This **silences all logs** for `Engine B`, even though it is still running.
*   **Fix:** The log callback must be stored within the `SnapClient` struct, and the bridge must pass the instance handle to the logger.

### 2. Artwork Cache Order Bloat
In `NowPlayingManager.swift`, the `cacheArtwork` method appends to the order list without checking for duplicates:
```swift
private func cacheArtwork(_ artwork: MPMediaItemArtwork, for url: String) {
    artworkCache[url] = artwork
    artworkCacheOrder.append(url) // <--- Duplicates allowed
    // ... eviction logic ...
}
```
*   **The Bug:** If the same song plays repeatedly, `artworkCacheOrder` will grow indefinitely with duplicate strings, while `artworkCache.count` remains constant.
*   **Impact:** Memory leak in the tracking array over long listening sessions.
*   **Fix:** If the URL is already in the cache, move it to the end of the order list instead of appending a duplicate.

### 3. JSON-RPC Protocol Non-Compliance
In `SnapcastRPCClient.swift`, the ID handling logic assumes IDs are always numeric:
```swift
else if let stringId = json["id"] as? String, let intId = Int(stringId)
```
*   **The Bug:** JSON-RPC 2.0 allows `id` to be **any String** (e.g., `"request_123"` or a UUID). Your code fails to match any response where the ID contains non-numeric characters.
*   **Impact:** Incompatibility with certain Snapserver versions or WebSocket proxies.
*   **Fix:** Store `pendingRequests` using `AnyHashable` keys to support both `Int` and `String` identifiers.

### 4. Hardcoded Audio Sync Offset
In `ios_player.cpp`, the latency reported to the server uses a hardcoded "guess":
```cpp
size_t bufferedMs = ... + (ms_ * (NUM_BUFFERS - 1)) + 15; // 15ms is a guess
```
*   **The Bug:** DAC latency and buffer occupancy vary by hardware (Bluetooth vs. internal speaker). Hardcoding `15ms` leads to "sync drift" where this iOS device will play slightly ahead or behind other Snapcast clients.
*   **Impact:** Noticeable "echo" effect in multi-room setups.
*   **Fix:** Use `AudioQueue` properties to query actual hardware latency and calculate `bufferedMs` based on current buffer fill levels.

---

## 🛠️ The "Perfect Sync" Patch Prompt

Use this prompt to resolve these final issues:

> **Prompt:**
> "Apply final precision hardening to the SnapForge iOS codebase:
>
> 1. **Multi-Instance Logs:**
>    - In `snapclient_bridge.cpp`, move `SnapClientLogCallback` into the `SnapClient` struct.
>    - Update the bridge logging macros to use the callback registered to the specific `SnapClient` instance.
>
> 2. **Cache Integrity:**
>    - In `NowPlayingManager.swift`, update `cacheArtwork` to check if a URL already exists in `artworkCacheOrder`. If it does, remove the old entry before appending the new one to maintain correct FIFO order without duplicates.
>
> 3. **Full JSON-RPC Compliance:**
>    - In `SnapcastRPCClient.swift`, change `pendingRequests` to use `[AnyHashable: CheckedContinuation<Data, Error>]`.
>    - Update `handleMessage` to extract the `id` as `AnyHashable` and match it directly against the pending requests, supporting both `Int` and `String` types.
>
> 4. **Audio Sync Precision:**
>    - In `ios_player.cpp`, replace the hardcoded `15ms` DAC delay with a calculation using `AudioQueue` metrics.
>    - Ensure the reported `bufferedMs` accurately reflects the real-time playback delay for better multi-room synchronization."

---
