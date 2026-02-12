# 🏛️ SnapForge iOS: Architecture & Stability Guide

This document outlines the high-precision engineering used to bridge Swift and C++ in the SnapForge audio engine.

## 1. The Multi-Layered Bridge
The core of the application is a **Hybrid Bridge** that connects modern high-level Swift with low-level real-time C++.

### A. SnapClientEngine (Swift)
Acts as the **Owner** and **State Machine**.
- **Structured Concurrency:** Uses `Task.detached` to prevent blocking the Main Actor with C++ TCP operations.
- **Zombie Lifecycle:** If a C++ instance hangs during shutdown, the engine "invalidates" it, appends it to `zombieRefs`, and spawns a fresh `SnapClientRef`. This ensures the UI is always responsive.

### B. snapclient_bridge (C/C++)
Acts as the **Safety Layer**.
- **CallbackGuard:** An RAII guard that tracks `callbacksInFlight`. It prevents the C++ core from calling into a Swift context that is currently being deallocated (Use-After-Free protection).
- **Hard Reset:** Forcibly clears the `TimeProvider` singleton on every new connection to prevent multi-room sync drift.

### C. IOSPlayer (C++)
The **Real-Time Hot Path**.
- **Lock-Free Design:** Uses **Atomic Generations** instead of mutexes in the `playerCallback`. This guarantees that the system audio thread never stutters due to lock contention from background worker threads.
- **RunLoop Sync:** Manages a dedicated `CFRunLoop` for `AudioQueue` events, with a robust `CFRunLoopStop` signal for clean thread termination.

## 2. Stability Invariants
Maintainers MUST adhere to these rules:
1. **Never call C functions on MainActor:** All `snapclient_*` calls that involve network or thread-joins must be wrapped in `Task.detached`.
2. **Atomic Hot Paths:** The `playerCallback` in `ios_player.cpp` must remain lock-free. Never introduce a `std::mutex` or `os_log` in this function.
3. **Weak Self Captures:** Any `Task` launched by `SnapClientEngine` must capture `self` weakly to prevent retain cycles.

## 3. Telemetry & Diagnostics
The engine exposes a `diagnostics` struct for real-time monitoring:
- `activeZombiesCount`: Number of stale C++ threads pending cleanup.
- `isStopTaskHanging`: Detects if the C++ bridge is blocked by a TCP timeout.
