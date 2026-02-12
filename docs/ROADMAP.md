# 🚀 Future Improvement Roadmap (The 1%)

**Date:** February 8, 2026  
**Status:** Post-Hardening / Optimization Ready

While the current codebase is functionally flawless and production-stable, the following improvements would elevate it from "Professional" to "Industry-Leading."

---

## 🏗️ 1. Architectural Refinements

### A. Formal Finite State Machine (FSM)
*   **Current State:** State is managed by multiple flags (`state`, `isConnecting`, `isPaused`) across Swift and C++.
*   **Improvement:** Implement a unified `StateEngine` using a formal state machine pattern.
*   **Benefit:** Eliminates the "illegal transition" edge cases entirely (e.g., trying to `pause` while in `connecting` state).

### B. Move Global Atomic to Instance
*   **Current State:** `g_ios_player_paused` is a global C++ atomic.
*   **Improvement:** Move the pause state into the `SnapClient` struct and pass it via the `Player` constructor.
*   **Benefit:** Enables **Multi-Stream** capability (listening to two different Snapcast streams simultaneously in one app).

---

## ⚡ 2. Performance Optimizations

### A. RPC Notification Dispatcher
*   **Current State:** `SnapcastRPCClient` uses a large `switch` statement (~200 lines) for incremental updates.
*   **Improvement:** Refactor into a `Map<String, RPCNotificationHandler>`.
*   **Benefit:** Reduces cyclomatic complexity and makes the protocol handling easier to unit test in isolation.

### B. Adaptive Buffer Tuning
*   **Current State:** Buffer size is fixed at `100ms` (400ms total).
*   **Improvement:** Implement an adaptive logic that reduces buffer size to `50ms` when on high-speed Wi-Fi and increases it to `200ms` when on cellular/VPN.
*   **Benefit:** Zero-latency feel without risking dropouts on poor connections.

---

## ♿ 3. Polish & Compliance

### A. Accessibility (A11y) Certification
*   **Target:** 100% VoiceOver coverage.
*   **Action:** Add `accessibilityLabel` to the `AlbumPlaceholder` and meaningful `accessibilityHint` to the `Disconnect` and `Mute` buttons.
*   **Benefit:** Allows visually impaired users to manage their multi-room audio with confidence.

### B. Haptic Engine Integration
*   **Target:** Physical response for UI actions.
*   **Action:** Integrate `UIImpactFeedbackGenerator`.
*   **Benefit:** Subtle "clicks" when the volume slider snaps or when a connection is established improve the "premium" feel of the app.

---

## 🧪 4. The "Endurance" Test
*   **Action:** Perform a **7-Day Soak Test**.
*   **Goal:** Connect the app to a MainActor-isolated logger and let it play silence for 168 hours. 
*   **Benefit:** Identify the absolute smallest memory leaks (e.g., 1KB/hour) that only a marathon session can reveal.

---

## 🏁 Final Thought
This roadmap represents the transition from **Software Engineering** to **Software Craftsmanship**. The current code solves the "What" and the "How"; these suggestions solve the "Experience."
