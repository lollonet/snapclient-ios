# 🧪 Final Proof of Stability: Automated Stress Tests

**Objective:** Prove the "Zero-Deadlock" and "Zero-Leak" architecture holds up under extreme, non-human usage patterns.

---

## 📋 The "Hammer Test" Prompt (Copy & Paste)

> **Prompt:**
> "Create a robust suite of stability and stress tests to verify the hardened SnapForge engine:
>
> 1. **The 'Server-Hop' Swift Test (`SnapClientStabilityTests.swift`):**
>    - Create an XCTest that calls `engine.start(host:port:)` with five different dummy IPs in rapid succession (every 100ms).
>    - Repeat this for 100 iterations.
>    - **Goal:** Verify that `zombieRefs` are correctly created and reaped, and that the Main Actor **never** blocks.
>
> 2. **The 'Audio-Cycle' Bridge Test (`BridgeStabilityTests.cpp`):**
>    - Create a C++ test that repeatedly calls `snapclient_pause` and `snapclient_resume` from 10 different threads simultaneously.
>    - **Goal:** Verify that the lock-free state in `ios_player.cpp` and the recursive mutex in the bridge handle high-frequency contention without crashing or deadlocking.
>
> 3. **The 'Dirty Disconnect' Test:**
>    - Simulate a background task calling `snapclient_stop` while a `notify_state` callback is actively executing.
>    - **Goal:** Verify that the `CallbackGuard` successfully prevents a use-after-free crash.
>
> 4. **Resource Monitoring:**
>    - The tests should log the final `diagnostics.activeZombiesCount` to ensure it returns to zero after the stress period ends."

---

## 🏗️ Why these tests are the final step

| Test | What it Proves |
| :--- | :--- |
| **Server-Hop** | The `invalidateAndRecreate` logic actually works and doesn't leak threads. |
| **Audio-Cycle** | The `std::atomic` pause state is truly thread-safe under extreme load. |
| **Dirty Disconnect** | The `callbacksInFlight` guard is working as intended. |

---

## 🏁 Final Handover
Once these tests pass, you have a **verified industrial-strength** codebase. You won't just *think* it works flawlessly—you will have the logs to *prove* it.

**Proceed with creating the test files?**
