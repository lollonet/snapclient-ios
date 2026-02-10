# 🩺 Stability & Resource Hardening Plan

**Date:** February 8, 2026  
**Status:** Investigation & Implementation  
**Symptoms:** App becomes unresponsive after long sessions or multiple server switches.  
**Root Cause:** Thread leaks and resource contention at the Swift-C++ boundary.

---

## 🔍 Phase 1: Forensic Investigation & Diagnostics
We need to move from "it's slow" to "here is the leaking resource."

1.  **Implement `EngineDiagnostics`:** Add a method to `SnapClientEngine` to track:
    *   **Thread Count:** Monitor growth of background worker threads.
    *   **Memory (RSS):** Track the resident set size to identify C++ heap leaks.
    *   **Bridge Latency:** Measure the time taken for a simple C-bridge call (detecting mutex contention).
2.  **Telemetry UI:** Add a hidden "Developer HUD" in the Servers tab to visualize these metrics in real-time.

---

## 🛠️ Phase 2: Implementation of Fixes
The primary goal is to ensure that a server switch **never** leaks a resource, even if the network is hanging.

### 1. C++ Lifecycle Hardening (`ios_player.cpp`)
*   **The Problem:** The `worker()` thread gets stuck in `CFRunLoopRun()`.
*   **The Fix:** 
    *   Implement an explicit `uninit()` called from the `IOSPlayer` destructor.
    *   Ensure `CFRunLoopStop` is called on the correct thread reference.
    *   Change `AudioQueueStop` to synchronous (`true`) to force-release hardware resources immediately.

### 2. Swift Instance Management (`SnapClientEngine.swift`)
*   **The Problem:** The `await pendingStop.value` timeout "proceeds anyway," leading to multiple active connections on the same C++ pointer.
*   **The Fix:** **Instance Invalidation.** 
    *   If a `stopTask` times out, **discard** the `clientRef`. 
    *   Instead of calling `snapclient_start` on a stuck instance, call `snapclient_create()` to get a fresh, clean C++ state.
    *   Let the old "zombie" instance clean itself up in the background (or leak harmlessly without blocking the new one).

---

## 🧪 Phase 3: Automated Stress & Regression Tests
We will add a new test target `SnapClientStabilityTests` to simulate high-load scenarios.

1.  **The "Server-Hop" Test:**
    *   Simulate switching between 3 servers every 500ms for 100 iterations.
    *   **Success Criteria:** Memory usage must remain stable (within 5MB of baseline) and thread count must not exceed `baseline + 2`.
2.  **The "Buffer Exhaustion" Test:**
    *   Simulate a high-latency, jittery network.
    *   **Success Criteria:** AudioQueue must recover/restart without manual app intervention.
3.  **The "Long-Haul" Test:**
    *   Maintain a connection for 60 minutes with background/foreground transitions.
    *   **Success Criteria:** No `RPC reconnect ghosts` and responsive UI throughout.

---

## 📋 Execution Order
1.  **[IMMEDIATE]** Patch `ios_player.cpp` and `SnapClientEngine.swift` with the **Instance Invalidation** logic.
2.  **[MONITORING]** Implement the Diagnostics HUD to verify the fix works.
3.  **[REGRESSION]** Add the `Server-Hop` stability test.
