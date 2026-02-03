/**
 * snapclient_bridge.cpp
 *
 * Implementation of the C bridge to the Snapcast C++ client core.
 * This file wraps the C++ Controller/ClientConnection classes into
 * a plain-C API that Swift can call via the bridging header.
 *
 * TODO(phase-1): Wire up to actual Snapcast Controller class once
 *                the C++ core compiles for iOS.
 */

#include "snapclient_bridge.h"

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

/* ── Internal state ─────────────────────────────────────────────── */

struct SnapClient {
    std::mutex mutex;

    // Connection
    std::string host;
    int port = 1704;
    std::atomic<SnapClientState> state{SNAPCLIENT_STATE_DISCONNECTED};
    std::thread worker;

    // Settings
    std::atomic<int> volume{100};
    std::atomic<bool> muted{false};
    std::atomic<int> latency_ms{0};

    // Identity
    std::string name = "SnapForge iOS";
    int instance = 1;

    // Callbacks
    SnapClientStateCallback state_cb = nullptr;
    void* state_ctx = nullptr;
    SnapClientSettingsCallback settings_cb = nullptr;
    void* settings_ctx = nullptr;

    // TODO: Add Snapcast Controller*, ClientConnection*, Stream* here
    // once C++ core is linked in.
};

/* ── Helpers ────────────────────────────────────────────────────── */

static void notify_state(SnapClient* c, SnapClientState new_state) {
    c->state.store(new_state);
    if (c->state_cb) {
        c->state_cb(c->state_ctx, new_state);
    }
}

/* ── Lifecycle ──────────────────────────────────────────────────── */

SnapClientRef snapclient_create(void) {
    return new (std::nothrow) SnapClient();
}

void snapclient_destroy(SnapClientRef client) {
    if (!client) return;
    snapclient_stop(client);
    delete client;
}

/* ── Connection ─────────────────────────────────────────────────── */

bool snapclient_start(SnapClientRef client, const char* host, int port) {
    if (!client || !host) return false;

    std::lock_guard<std::mutex> lock(client->mutex);

    if (client->state.load() != SNAPCLIENT_STATE_DISCONNECTED) {
        return false; // already running
    }

    client->host = host;
    client->port = port;
    notify_state(client, SNAPCLIENT_STATE_CONNECTING);

    // TODO(phase-1): Replace this placeholder with actual Snapcast
    // Controller startup:
    //
    //   auto settings = ClientSettings{};
    //   settings.host = client->host;
    //   settings.port = client->port;
    //   settings.player.name = "coreaudio";
    //   settings.instance = client->instance;
    //
    //   client->controller = std::make_unique<Controller>(io_context, settings);
    //   client->controller->start();
    //
    // The Controller internally creates:
    //   ClientConnection → Stream → Decoder → CoreAudioPlayer
    // and handles time synchronization automatically.

    notify_state(client, SNAPCLIENT_STATE_CONNECTED);
    return true;
}

void snapclient_stop(SnapClientRef client) {
    if (!client) return;

    std::lock_guard<std::mutex> lock(client->mutex);

    if (client->state.load() == SNAPCLIENT_STATE_DISCONNECTED) {
        return;
    }

    // TODO(phase-1): controller->stop() and join worker thread.

    if (client->worker.joinable()) {
        client->worker.join();
    }

    notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
}

bool snapclient_is_connected(SnapClientRef client) {
    if (!client) return false;
    auto s = client->state.load();
    return s == SNAPCLIENT_STATE_CONNECTED || s == SNAPCLIENT_STATE_PLAYING;
}

/* ── Volume ─────────────────────────────────────────────────────── */

void snapclient_set_volume(SnapClientRef client, int percent) {
    if (!client) return;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    client->volume.store(percent);
    // TODO: forward to Controller/Stream
}

int snapclient_get_volume(SnapClientRef client) {
    return client ? client->volume.load() : 0;
}

void snapclient_set_muted(SnapClientRef client, bool muted) {
    if (!client) return;
    client->muted.store(muted);
    // TODO: forward to Controller/Stream
}

bool snapclient_get_muted(SnapClientRef client) {
    return client ? client->muted.load() : false;
}

/* ── Latency ────────────────────────────────────────────────────── */

void snapclient_set_latency(SnapClientRef client, int latency_ms) {
    if (!client) return;
    client->latency_ms.store(latency_ms);
    // TODO: forward to Controller
}

int snapclient_get_latency(SnapClientRef client) {
    return client ? client->latency_ms.load() : 0;
}

/* ── Identity ───────────────────────────────────────────────────── */

void snapclient_set_name(SnapClientRef client, const char* name) {
    if (!client || !name) return;
    std::lock_guard<std::mutex> lock(client->mutex);
    client->name = name;
}

void snapclient_set_instance(SnapClientRef client, int instance) {
    if (!client) return;
    std::lock_guard<std::mutex> lock(client->mutex);
    client->instance = instance;
}

/* ── Status ─────────────────────────────────────────────────────── */

SnapClientState snapclient_get_state(SnapClientRef client) {
    return client ? client->state.load() : SNAPCLIENT_STATE_DISCONNECTED;
}

void snapclient_set_state_callback(SnapClientRef client,
                                   SnapClientStateCallback callback,
                                   void* ctx) {
    if (!client) return;
    std::lock_guard<std::mutex> lock(client->mutex);
    client->state_cb = callback;
    client->state_ctx = ctx;
}

void snapclient_set_settings_callback(SnapClientRef client,
                                      SnapClientSettingsCallback callback,
                                      void* ctx) {
    if (!client) return;
    std::lock_guard<std::mutex> lock(client->mutex);
    client->settings_cb = callback;
    client->settings_ctx = ctx;
}

/* ── Audio session ──────────────────────────────────────────────── */

bool snapclient_configure_audio_session(void) {
    // TODO(phase-2): Configure AVAudioSession via Obj-C:
    //   [[AVAudioSession sharedInstance]
    //       setCategory:AVAudioSessionCategoryPlayback error:nil];
    //   [[AVAudioSession sharedInstance]
    //       setActive:YES error:nil];
    return true;
}

/* ── Version ────────────────────────────────────────────────────── */

const char* snapclient_version(void) {
    // TODO: return actual SNAPCAST_VERSION_STRING from snapcast headers
    return "0.34.0-snapforge";
}

int snapclient_protocol_version(void) {
    // TODO: return actual protocol version from snapcast headers
    return 2;
}
