# 📉 Refactoring Audit v2: "The Last Mile"

**Status:** ✅ Complete
**Audit Date:** February 8, 2026
**Completion Date:** February 8, 2026

You successfully split the files and implemented the requested logic, but the app is currently in a "hybrid" state where new components exist but are not yet integrated, and some logic bugs remain.

---

## 🚩 Remaining Weaknesses

### 1. Unused Components (The "Ghost" Refactor)
You created `SnapVolumeSlider.swift` and `SnapVolumeControl.swift`, but they are currently **not used**.
*   **Location:** `PlayerView.swift` (line 166) and `GroupsView.swift` (line 218).
*   **Issue:** Both files still contain the original, manual `Slider` logic and local `@State` variables for volume.
*   **Impact:** You haven't actually reduced the technical debt yet; you've just added more files.

### 2. RPC Debounce Race Condition
The `debouncedRefresh` in `SnapcastRPCClient.swift` can still trigger multiple concurrent network requests.
```swift
if timeSinceLastRefresh >= refreshDebounceInterval {
    Task { await refreshStatus() } // Fires every time if interval has passed
}
```
*   **Issue:** If 5 notifications arrive within the same millisecond after the 500ms window has passed, you will fire 5 simultaneous `Server.GetStatus` requests.
*   **Impact:** Unnecessary server load and potential UI flickering.

### 3. Duplicated Error State
The `rpcError` and `showRPCError` states are still duplicated across 4 different view structs.
*   **Impact:** Harder to maintain. If you want to change the error UI (e.g., to a Toast), you have to change it in 4 places.

---

## 🛠️ The Fix-it Prompt (Copy & Paste)

Use this prompt to finish the refactor:

> **Prompt:**
> "Complete the refactor of the SnapForge iOS app:
>
> 1. **Integrate Components:**
>    - In `PlayerView.swift` and `GroupsView.swift`, replace the manual `Slider` and `VStack` volume blocks with the `SnapVolumeControl` component.
>    - Remove the redundant `@State private var volumeSlider` and `@State private var isEditingVolume` from those views.
>
> 2. **Fix RPC Race Condition:**
>    - In `SnapcastRPCClient.swift`, add a `private var isRefreshing = false` flag.
>    - Update `refreshStatus()` to check this flag and return early if a refresh is already in progress.
>
> 3. **Centralize Error Alerts:**
>    - Move `rpcError` and `showRPCError` from the views into `SnapcastRPCClient`.
>    - Add an `handleError(_:)` method to the RPC client.
>    - Remove all `.alert("Error", ...)` blocks from sub-views and place a **single** alert on the root `ContentView` that monitors the `rpcClient`.
>
> 4. **Cleanup:**
>    - Remove any unused `@State` variables left over from the old volume logic."

---
