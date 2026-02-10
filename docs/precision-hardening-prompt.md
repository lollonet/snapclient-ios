# 🛡️ Precision Hardening Prompt: "Zero-Flicker & Clean Lifecycle"

**Date:** February 8, 2026  
**Target:** Race conditions and UX bugs identified via Forensic Log Analysis.

---

## 📋 The Fix-it Prompt (Copy & Paste)

> **Prompt:**
> "Harden the SnapForge iOS codebase to resolve race conditions, metadata flickers, and lifecycle timeouts identified in recent debug logs:
>
> 1. **Fix Metadata Flicker (NowPlayingManager.swift):**
>    - Implement a **metadata persistence** mechanism. The `nowPlayingInfo` must keep the last valid song title, artist, and artwork URL during server switches or RPC reconnections.
>    - Modify the logic so that lock screen info is **not** cleared immediately when `rpcClient.serverStatus` becomes `nil`. Instead, only clear it if the `engine.state` has been `disconnected` for more than **5 seconds**.
>
> 2. **Fix RPC Reconnect Race (SnapcastRPCClient.swift):**
>    - In `connect(host:port:)`, ensure the `connectedHost` property is updated **synchronously** before any asynchronous tasks are launched.
>    - Update `scheduleReconnect()` to guard against 'Ghost Reconnections': it must check if the `host` it was scheduled for is still the `connectedHost` before attempting to connect.
>
> 3. **Harden C++ Engine Lifecycle (SnapClientEngine.swift):**
>    - Improve the connection sequence in `start()`. Replace the short fixed wait with a **wait-loop** (up to 2 seconds, checking every 100ms) that polls `snapclient_get_state`.
>    - **Critical:** Do not call `snapclient_start` until the C++ core has reached the `DISCONNECTED` state. This prevents the 'already connecting' collisions and ensures a clean clock sync for the new connection.
>
> 4. **Fix Thread-Isolation Warnings:**
>    - Audit the artwork downloader in `NowPlayingManager` and the `AsyncImage` logic in `PlayerView`.
>    - Ensure all `UIImage` instantiations and `MPNowPlayingInfoCenter` updates are strictly isolated to the `@MainActor` to eliminate 'Requesting visual style' system warnings."

---

## 🔍 Context: Why these fixes matter

| Bug | Impact | Fix Benefit |
| :--- | :--- | :--- |
| **Metadata Flicker** | Lock screen "blinks" to default info every song change or reconnect. | Smooth, professional-grade media experience. |
| **RPC Ghosts** | App tries to connect to old IPs in the background after switching servers. | Lower battery usage and cleaner network logs. |
| **Lifecycle Timeout** | New connection starts before the old one is fully dead, causing sync drift. | Perfect multi-room synchronization. |
| **Visual Style Spam** | iOS Console.app filled with UI warnings. | Proper thread safety and stable UI rendering. |
