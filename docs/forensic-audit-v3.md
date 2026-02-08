# 🕵️ Deep Forensic Audit v3: "Edge-Case Poltergeists"

**Status:** ✅ Complete
**Audit Date:** February 8, 2026
**Completion Date:** February 8, 2026

The refactored code is resilient and performs well. However, this deep-dive identifies "Level 4" bugs—subtle issues involving race conditions, memory lifecycles, and OS-level citizenship that typically only surface in production under stress.

---

## 🚩 Deep-Level Vulnerabilities

### 1. `SnapClientRef` Use-After-Free (UAF)
In `SnapClientEngine.stop()`, the blocking C++ cleanup is moved to a background task:
```swift
Task.detached {
    snapclient_stop(ref) // 'ref' is a captured raw pointer
}
```
*   **The Bug:** If `SnapClientEngine` is deallocated immediately after `stop()` (e.g., user exits the app), the `deinit` will run and call `snapclient_destroy(ref)`. The background task may then attempt to call `snapclient_stop` on a pointer that has already been `delete`d.
*   **Impact:** Intermittent crashes on app exit or server switching.

### 2. JSON-RPC Protocol Fragility
The response handler expects `id` to be strictly an `Int`:
```swift
if let json = try? ... as? [String: Any], let id = json["id"] as? Int
```
*   **The Bug:** JSON-RPC 2.0 allows `id` to be a **String**. If a Snapserver version or proxy (like a Nginx wrapper) returns string IDs, the client will ignore all responses.
*   **Impact:** Sudden "connection loss" or timeouts with certain server configurations.

### 3. Audio Session "Vampirism"
The `AVAudioSession` is activated in `start()` but never explicitly deactivated.
*   **The Bug:** When `stop()` is called, the app remains the "primary" audio owner in the eyes of iOS. This can prevent other apps (Spotify, Podcasts) from resuming correctly or keep the "SnapForge" card visible in Control Center indefinitely.
*   **Impact:** Poor "OS citizenship" and user frustration with background audio behavior.

### 4. Concurrent Socket Exhaustion
The `connectionTask.cancel()` only stops the Swift Task, not the underlying blocking C++ `connect()` call.
*   **The Bug:** If a user taps "Connect" on 5 different servers rapidly, 5 background threads will be stuck in a blocking TCP connect simultaneously.
*   **Impact:** Resource exhaustion and "ghost" connections appearing briefly on the server.

---

## 🛠️ The "Bulletproof" Patch Prompt

Use this prompt to reach 100% SOTA quality:

> **Prompt:**
> "Apply final forensic hardening to the SnapForge iOS codebase:
>
> 1. **Secure Memory Lifecycle:**
>    - In `SnapClientEngine.stop()`, ensure the `Task.detached` captures `self` strongly so the engine (and its `clientRef`) is guaranteed to survive until `snapclient_stop` returns.
>
> 2. **Protocol Robustness:**
>    - Update `SnapcastRPCClient.handleMessage` to handle the JSON-RPC `id` as either an `Int` or a `String`. 
>
> 3. **Audio Citizenship:**
>    - In `SnapClientEngine.stop()`, call `try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)` on the MainActor after the engine stops.
>
> 4. **Socket Protection:**
>    - In `SnapClientEngine.start()`, add a check to ensure we don't start a new `Task.detached` if one is already in a 'connecting' state, or implement a small delay to debounce rapid taps.
>
> 5. **Logging:**
>    - Ensure all background tasks in the engine use `Logger` instead of `print` to maintain consistent diagnostic logs in Console.app."

---
