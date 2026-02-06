/**
 * snapclient_bridge.h
 *
 * C interface to the Snapcast C++ client core.
 * This bridge allows Swift code to control the snapclient engine
 * without directly interfacing with C++.
 *
 * Thread safety: all functions are thread-safe unless noted otherwise.
 * The bridge manages its own background thread for the audio engine.
 */

#ifndef SNAPCLIENT_BRIDGE_H
#define SNAPCLIENT_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

/* ── Opaque handle ──────────────────────────────────────────────── */

/// Opaque pointer to the snapclient instance.
typedef struct SnapClient* SnapClientRef;

/* ── Lifecycle ──────────────────────────────────────────────────── */

/// Create a new snapclient instance.
/// Returns NULL on failure.
SnapClientRef snapclient_create(void);

/// Destroy a snapclient instance and free all resources.
/// Safe to call with NULL.
void snapclient_destroy(SnapClientRef client);

/* ── Connection ─────────────────────────────────────────────────── */

/// Connect to a Snapserver and start audio playback.
/// @param host  Server hostname or IP address (UTF-8).
/// @param port  Server audio port (typically 1704).
/// @return true on success, false on failure.
bool snapclient_start(SnapClientRef client, const char* host, int port);

/// Disconnect from the server and stop playback.
void snapclient_stop(SnapClientRef client);

/// Returns true if the client is currently connected and playing.
bool snapclient_is_connected(SnapClientRef client);

/* ── Playback control ──────────────────────────────────────────────── */

/// Pause audio playback while keeping the connection alive.
/// The client continues to receive audio data and sync with the server,
/// but audio output is silenced.
void snapclient_pause(SnapClientRef client);

/// Resume audio playback after a pause.
void snapclient_resume(SnapClientRef client);

/// Returns true if audio playback is currently paused.
bool snapclient_is_paused(SnapClientRef client);

/* ── Volume ─────────────────────────────────────────────────────── */

/// Set playback volume (0–100).
void snapclient_set_volume(SnapClientRef client, int percent);

/// Get current playback volume (0–100).
int snapclient_get_volume(SnapClientRef client);

/// Set mute state.
void snapclient_set_muted(SnapClientRef client, bool muted);

/// Get mute state.
bool snapclient_get_muted(SnapClientRef client);

/* ── Latency ────────────────────────────────────────────────────── */

/// Set additional client latency in milliseconds.
void snapclient_set_latency(SnapClientRef client, int latency_ms);

/// Get current client latency in milliseconds.
int snapclient_get_latency(SnapClientRef client);

/* ── Client identity ────────────────────────────────────────────── */

/// Set the client's display name (UTF-8).
void snapclient_set_name(SnapClientRef client, const char* name);

/// Set a unique client instance ID (default: 1).
/// Multiple instances on the same device use different IDs.
void snapclient_set_instance(SnapClientRef client, int instance);

/* ── Status & callbacks ─────────────────────────────────────────── */

/// Client connection state.
typedef enum {
    SNAPCLIENT_STATE_DISCONNECTED = 0,
    SNAPCLIENT_STATE_CONNECTING   = 1,
    SNAPCLIENT_STATE_CONNECTED    = 2,
    SNAPCLIENT_STATE_PLAYING      = 3,
} SnapClientState;

/// Get current connection state.
SnapClientState snapclient_get_state(SnapClientRef client);

/// Callback invoked when client state changes.
/// @param ctx    User-provided context pointer.
/// @param state  New client state.
typedef void (*SnapClientStateCallback)(void* ctx, SnapClientState state);

/// Register a state change callback.
/// Pass NULL to unregister.
void snapclient_set_state_callback(SnapClientRef client,
                                   SnapClientStateCallback callback,
                                   void* ctx);

/// Callback invoked when server settings change (volume, mute, latency).
typedef void (*SnapClientSettingsCallback)(void* ctx,
                                           int volume,
                                           bool muted,
                                           int latency_ms);

/// Register a settings change callback.
void snapclient_set_settings_callback(SnapClientRef client,
                                      SnapClientSettingsCallback callback,
                                      void* ctx);

/* ── Logging ────────────────────────────────────────────────────── */

/// Log severity levels.
typedef enum {
    SNAPCLIENT_LOG_DEBUG   = 0,
    SNAPCLIENT_LOG_INFO    = 1,
    SNAPCLIENT_LOG_WARNING = 2,
    SNAPCLIENT_LOG_ERROR   = 3,
} SnapClientLogLevel;

/// Callback invoked for each log message from the C++ core.
/// @param ctx    User-provided context pointer.
/// @param level  Log severity.
/// @param msg    Null-terminated log message (UTF-8).
typedef void (*SnapClientLogCallback)(void* ctx, SnapClientLogLevel level, const char* msg);

/// Register a log callback to receive all bridge log messages.
/// Pass NULL to unregister. Logs are also sent to os_log.
void snapclient_set_log_callback(SnapClientLogCallback callback, void* ctx);

/* ── Audio session (iOS-specific) ───────────────────────────────── */

/// Configure the iOS audio session for background playback.
/// Call this before snapclient_start().
/// Returns true on success.
bool snapclient_configure_audio_session(void);

/* ── Diagnostics ────────────────────────────────────────────────── */

/// Test raw TCP connection to host:port (bypasses Snapcast protocol).
/// Returns 0 on success, or errno on failure. Logs details via log callback.
int snapclient_test_tcp(const char* host, int port);

/* ── Version info ───────────────────────────────────────────────── */

/// Returns the snapclient core version string (e.g. "0.34.0").
const char* snapclient_version(void);

/// Returns the Snapcast protocol version supported.
int snapclient_protocol_version(void);

#ifdef __cplusplus
}
#endif

#endif /* SNAPCLIENT_BRIDGE_H */
