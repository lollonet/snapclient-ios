# 🛠️ SnapForge iOS Optimization Report

**Date:** February 6, 2026  
**Focus:** Code Duplication, Performance, and Scalability

---

## 📊 1. Current State (LOC)
The project has grown to ~4,500 lines of code. `ContentView.swift` has become a "Massive View" (1,000+ LOC), violating the Single Responsibility Principle and making maintenance difficult.

| File | LOC | Issue |
| :--- | :--- | :--- |
| `ContentView.swift` | 1,034 | Contains 3 distinct views + duplicated logic. |
| `SnapcastRPCClient.swift` | 534 | Heavy network overhead on notifications. |
| `IOSPlayer.cpp` | 281 | High latency (800ms buffer). |

---

## 🔍 2. Key Findings

### A. Code Duplication (UI)
*   **Volume Logic:** `PlayerView`, `GroupSection`, and `ClientRow` all implement identical logic for:
    *   Tracking `isEditing` state.
    *   Handling `Slider` interactions.
    *   Debouncing or triggering `rpcClient.setClientVolume`.
    *   Syncing server-side volume changes back to the UI.
*   **Error Alerts:** The same `.alert("Error", ...)` block is repeated 4+ times in the UI layer.

### B. Performance Bottlenecks
*   **RPC Refresh Storm:** `SnapcastRPCClient` triggers a full `Server.GetStatus` refresh for *every* incoming WebSocket notification. This causes excessive JSON parsing and network traffic on busy servers.
*   **Audio Latency:** The `IOSPlayer` uses a 200ms x 4 buffer (800ms total). While stable, this creates a sluggish user experience where volume/pause actions feel delayed.
*   **Bridge Locking:** Extensive use of `std::recursive_mutex` in the C bridge adds minor overhead to every state check.

---

## 🎯 3. Optimization Goals
1.  **Extract Components:** Move `VolumeSlider` and `ErrorAlert` into reusable SwiftUI components.
2.  **Smart RPC Updates:** Implement a debounced refresh or partial update mechanism for WebSocket notifications.
3.  **Latency Reduction:** Tune `IOSPlayer` buffers for a more responsive feel (target 100ms or 50ms).
4.  **View Decoupling:** Split `ContentView.swift` into `PlayerView.swift`, `GroupsView.swift`, and `ServersView.swift`.

---

## 📝 4. Prompt for AI Refactoring

Copy and paste the following prompt to execute these optimizations:

> **Prompt:** 
> "Refactor the SnapForge iOS codebase for performance and maintainability:
> 
> 1. **UI Clean-up:** 
>    - Create a reusable `SnapVolumeSlider` component that handles its own `isEditing` state and provides a callback for volume changes.
>    - Extract `PlayerView`, `GroupsView`, and `ServersView` into separate files.
>    - Implement a centralized error handling mechanism (e.g., an `ErrorManager` or `ObservableObject`) to remove duplicate `.alert` blocks.
> 
> 2. **RPC Optimization:**
>    - In `SnapcastRPCClient.swift`, add a debounce to `refreshStatus` so it doesn't fire more than once every 500ms, even if multiple notifications arrive.
>    - (Optional) Attempt to parse the incoming JSON notification to update the local `serverStatus` model directly instead of a full refresh.
> 
> 3. **Audio Performance:**
>    - In `IOSPlayer.cpp`, reduce the buffer size `ms_` from 200 to 100 to decrease total latency.
> 
> 4. **Bridge Refinement:**
>    - Ensure the audio hot-path in the C bridge uses atomic variables instead of mutexes where possible to avoid jitter."

---
