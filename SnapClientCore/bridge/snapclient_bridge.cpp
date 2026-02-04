/**
 * snapclient_bridge.cpp
 *
 * Implementation of the C bridge to the Snapcast C++ client core.
 * This file wraps the C++ Controller/ClientConnection classes into
 * a plain-C API that Swift can call via the bridging header.
 */

#include "snapclient_bridge.h"

// Snapcast headers
#include "client_settings.hpp"
#include "controller.hpp"
#include "common/aixlog.hpp"

// Standard headers
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

// Boost.Asio
#include <boost/asio/io_context.hpp>
#include <boost/asio/executor_work_guard.hpp>

/* ── Internal state ─────────────────────────────────────────────── */

// Type alias for work guard
using work_guard_t = boost::asio::executor_work_guard<boost::asio::io_context::executor_type>;

struct SnapClient {
    std::mutex mutex;

    // Boost.Asio io_context - runs the networking and timers
    std::unique_ptr<boost::asio::io_context> io_context;
    std::unique_ptr<work_guard_t> work_guard;

    // The Snapcast Controller
    std::unique_ptr<Controller> controller;

    // Worker thread for io_context
    std::thread io_thread;

    // Connection state
    std::string host;
    int port = 1704;
    std::atomic<SnapClientState> state{SNAPCLIENT_STATE_DISCONNECTED};

    // Settings (cached for when server updates them)
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
    // Initialize logging (once)
    static bool logging_initialized = false;
    if (!logging_initialized) {
        AixLog::Log::init<AixLog::SinkNative>("snapclient", AixLog::Filter(AixLog::Severity::info));
        logging_initialized = true;
    }

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

    try {
        // Create io_context
        client->io_context = std::make_unique<boost::asio::io_context>();
        client->work_guard = std::make_unique<work_guard_t>(client->io_context->get_executor());

        // Configure ClientSettings
        ClientSettings settings;
        settings.server.uri = StreamUri("tcp://" + client->host + ":" + std::to_string(client->port));
        settings.player.player_name = "ios";  // Use our iOS player
        settings.player.latency = client->latency_ms.load();
        settings.instance = client->instance;
        settings.host_id = client->name;

        // Create Controller
        client->controller = std::make_unique<Controller>(*client->io_context, settings);

        // Start Controller (it will connect and set up everything)
        client->controller->start();

        // Run io_context in background thread
        client->io_thread = std::thread([client]() {
            try {
                client->io_context->run();
            } catch (const std::exception& e) {
                LOG(ERROR, "Bridge") << "io_context exception: " << e.what() << "\n";
            }
            notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
        });

        notify_state(client, SNAPCLIENT_STATE_CONNECTED);
        return true;

    } catch (const std::exception& e) {
        LOG(ERROR, "Bridge") << "Failed to start: " << e.what() << "\n";
        notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
        return false;
    }
}

void snapclient_stop(SnapClientRef client) {
    if (!client) return;

    std::lock_guard<std::mutex> lock(client->mutex);

    if (client->state.load() == SNAPCLIENT_STATE_DISCONNECTED) {
        return;
    }

    // Stop io_context
    if (client->work_guard) {
        client->work_guard.reset();
    }
    if (client->io_context) {
        client->io_context->stop();
    }

    // Wait for worker thread
    if (client->io_thread.joinable()) {
        client->io_thread.join();
    }

    // Cleanup
    client->controller.reset();
    client->io_context.reset();

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
    // Note: Volume is controlled by the server via ServerSettings messages.
    // To change volume, use the JSON-RPC API to the server.
}

int snapclient_get_volume(SnapClientRef client) {
    return client ? client->volume.load() : 0;
}

void snapclient_set_muted(SnapClientRef client, bool muted) {
    if (!client) return;
    client->muted.store(muted);
    // Note: Mute is controlled by the server via ServerSettings messages.
}

bool snapclient_get_muted(SnapClientRef client) {
    return client ? client->muted.load() : false;
}

/* ── Latency ────────────────────────────────────────────────────── */

void snapclient_set_latency(SnapClientRef client, int latency_ms) {
    if (!client) return;
    client->latency_ms.store(latency_ms);
    // Note: Latency must be set before start()
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

#ifdef __OBJC__
#import <AVFAudio/AVFAudio.h>
#endif

bool snapclient_configure_audio_session(void) {
#ifdef __OBJC__
    @autoreleasepool {
        NSError* error = nil;
        AVAudioSession* session = [AVAudioSession sharedInstance];

        // Set category for playback
        [session setCategory:AVAudioSessionCategoryPlayback
                        mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionMixWithOthers
                       error:&error];
        if (error) {
            LOG(ERROR, "Bridge") << "Failed to set audio category: "
                                 << [[error localizedDescription] UTF8String] << "\n";
            return false;
        }

        // Activate session
        [session setActive:YES error:&error];
        if (error) {
            LOG(ERROR, "Bridge") << "Failed to activate audio session: "
                                 << [[error localizedDescription] UTF8String] << "\n";
            return false;
        }

        LOG(INFO, "Bridge") << "Audio session configured for playback\n";
        return true;
    }
#else
    // Non-Objective-C build - audio session must be configured from Swift
    return true;
#endif
}

/* ── Version ────────────────────────────────────────────────────── */

const char* snapclient_version(void) {
    return VERSION;
}

int snapclient_protocol_version(void) {
    return 2;
}
