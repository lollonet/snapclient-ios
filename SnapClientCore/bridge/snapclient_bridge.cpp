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
#include "time_provider.hpp"
#include "common/aixlog.hpp"
#include "ios_player.hpp"

// Standard headers
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <cstdarg>
#include <cstdio>

// Boost.Asio
#include <boost/asio/io_context.hpp>
#include <boost/asio/executor_work_guard.hpp>

// iOS: use os_log directly (AixLog SinkNative falls back to syslog on iOS)
#ifdef IOS
#include <os/log.h>
static os_log_t bridge_log() {
    static os_log_t log = os_log_create("com.snapforge.snapclient", "Bridge");
    return log;
}
#endif

/* ── Log callback ──────────────────────────────────────────────── */

// Global fallback log callback (used when no instance-specific callback is set)
// This is kept for backward compatibility and for logs before any client is created.
static SnapClientLogCallback g_log_cb = nullptr;
static void* g_log_ctx = nullptr;
static std::mutex g_log_mutex;

// Forward declaration for per-instance logging
struct SnapClient;
static void instance_log_msg(SnapClient* client, SnapClientLogLevel level, const char* fmt, ...)
    __attribute__((format(printf, 3, 4)));

void snapclient_set_log_callback(SnapClientLogCallback callback, void* ctx) {
    std::lock_guard<std::mutex> lock(g_log_mutex);
    g_log_cb = callback;
    g_log_ctx = ctx;
}

/// Log to os_log + callback. Use this instead of LOG() in bridge code.
static void bridge_log_msg(SnapClientLogLevel level, const char* fmt, ...)
    __attribute__((format(printf, 2, 3)));

static void bridge_log_msg(SnapClientLogLevel level, const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

#ifdef IOS
    os_log_type_t type = OS_LOG_TYPE_DEFAULT;
    switch (level) {
        case SNAPCLIENT_LOG_DEBUG:   type = OS_LOG_TYPE_DEBUG; break;
        case SNAPCLIENT_LOG_INFO:    type = OS_LOG_TYPE_INFO; break;
        case SNAPCLIENT_LOG_WARNING: type = OS_LOG_TYPE_DEFAULT; break;
        case SNAPCLIENT_LOG_ERROR:   type = OS_LOG_TYPE_ERROR; break;
    }
    os_log_with_type(bridge_log(), type, "%{public}s", buf);
#endif

    // Copy callback and context inside lock, call outside to avoid deadlock
    SnapClientLogCallback cb = nullptr;
    void* ctx = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_log_mutex);
        cb = g_log_cb;
        ctx = g_log_ctx;
    }
    if (cb) {
        cb(ctx, level, buf);
    }
}

#define BLOG_DEBUG(...)   bridge_log_msg(SNAPCLIENT_LOG_DEBUG, __VA_ARGS__)
#define BLOG_INFO(...)    bridge_log_msg(SNAPCLIENT_LOG_INFO, __VA_ARGS__)
#define BLOG_WARN(...)    bridge_log_msg(SNAPCLIENT_LOG_WARNING, __VA_ARGS__)
#define BLOG_ERROR(...)   bridge_log_msg(SNAPCLIENT_LOG_ERROR, __VA_ARGS__)

// Instance-specific logging macros (use when client pointer is available)
#define ILOG_DEBUG(c, ...)   instance_log_msg(c, SNAPCLIENT_LOG_DEBUG, __VA_ARGS__)
#define ILOG_INFO(c, ...)    instance_log_msg(c, SNAPCLIENT_LOG_INFO, __VA_ARGS__)
#define ILOG_WARN(c, ...)    instance_log_msg(c, SNAPCLIENT_LOG_WARNING, __VA_ARGS__)
#define ILOG_ERROR(c, ...)   instance_log_msg(c, SNAPCLIENT_LOG_ERROR, __VA_ARGS__)

/* ── Internal state ─────────────────────────────────────────────── */

// Type alias for work guard
using work_guard_t = boost::asio::executor_work_guard<boost::asio::io_context::executor_type>;

struct SnapClient {
    std::recursive_mutex mutex;

    // Lifecycle guard for callbacks
    std::atomic<int> callbacksInFlight{0};      // Count of callbacks currently executing
    std::atomic<bool> destroying{false};        // Set when destroy begins
    std::condition_variable_any callbacksDone;  // Signaled when callbacksInFlight hits 0

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

    // Per-instance log callback (takes precedence over global)
    SnapClientLogCallback log_cb = nullptr;
    void* log_ctx = nullptr;
};

/// RAII guard for callback scope - prevents callbacks during destroy
struct CallbackGuard {
    SnapClient* client;
    bool valid;

    CallbackGuard(SnapClient* c) : client(c), valid(false) {
        if (!c || c->destroying.load(std::memory_order_acquire)) return;
        c->callbacksInFlight.fetch_add(1, std::memory_order_acq_rel);
        // Double-check after increment (prevents race with destroy)
        if (c->destroying.load(std::memory_order_acquire)) {
            c->callbacksInFlight.fetch_sub(1, std::memory_order_acq_rel);
            c->callbacksDone.notify_all();
            return;
        }
        valid = true;
    }

    ~CallbackGuard() {
        if (valid) {
            if (client->callbacksInFlight.fetch_sub(1, std::memory_order_acq_rel) == 1) {
                client->callbacksDone.notify_all();
            }
        }
    }

    explicit operator bool() const { return valid; }
};

/* ── Instance-specific logging ──────────────────────────────────── */

/// Log with instance-specific callback (falls back to global if not set)
static void instance_log_msg(SnapClient* client, SnapClientLogLevel level, const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

#ifdef IOS
    os_log_type_t type = OS_LOG_TYPE_DEFAULT;
    switch (level) {
        case SNAPCLIENT_LOG_DEBUG:   type = OS_LOG_TYPE_DEBUG; break;
        case SNAPCLIENT_LOG_INFO:    type = OS_LOG_TYPE_INFO; break;
        case SNAPCLIENT_LOG_WARNING: type = OS_LOG_TYPE_DEFAULT; break;
        case SNAPCLIENT_LOG_ERROR:   type = OS_LOG_TYPE_ERROR; break;
    }
    os_log_with_type(bridge_log(), type, "%{public}s", buf);
#endif

    // Try instance-specific callback first
    SnapClientLogCallback cb = nullptr;
    void* ctx = nullptr;

    if (client) {
        std::lock_guard<std::recursive_mutex> lock(client->mutex);
        cb = client->log_cb;
        ctx = client->log_ctx;
    }

    // Fall back to global callback if no instance callback
    if (!cb) {
        std::lock_guard<std::mutex> lock(g_log_mutex);
        cb = g_log_cb;
        ctx = g_log_ctx;
    }

    if (cb) {
        cb(ctx, level, buf);
    }
}

/* ── Helpers ────────────────────────────────────────────────────── */

static void notify_state(SnapClient* c, SnapClientState new_state) {
    c->state.store(new_state);

    CallbackGuard guard(c);
    if (!guard) return;  // Client being destroyed

    // Copy callback and context inside lock to avoid race with callback modification
    SnapClientStateCallback cb = nullptr;
    void* ctx = nullptr;
    {
        std::lock_guard<std::recursive_mutex> lock(c->mutex);
        cb = c->state_cb;
        ctx = c->state_ctx;
    }

    // Call callback outside lock to avoid potential deadlock
    if (cb) {
        cb(ctx, new_state);
    }
}

/* ── Lifecycle ──────────────────────────────────────────────────── */

SnapClientRef snapclient_create(void) {
    // Initialize AixLog for Snapcast internals (uses syslog on iOS)
    static bool logging_initialized = false;
    if (!logging_initialized) {
        AixLog::Log::init<AixLog::SinkNative>("snapclient", AixLog::Filter(AixLog::Severity::debug));
        logging_initialized = true;
    }

    BLOG_INFO("snapclient_create: allocating client");
    return new (std::nothrow) SnapClient();
}

void snapclient_begin_destroy(SnapClientRef client) {
    if (!client) return;

    // Synchronously set destroying flag to block new callbacks.
    // This is safe to call from any thread including MainActor.
    // The flag is checked by CallbackGuard before allowing callback execution.
    client->destroying.store(true, std::memory_order_release);
    BLOG_DEBUG("snapclient_begin_destroy: destroying flag set");
}

void snapclient_destroy(SnapClientRef client) {
    if (!client) return;

    // Phase 1: Signal that destroy is starting (idempotent if already called)
    client->destroying.store(true, std::memory_order_release);

    // Phase 2: Wait for in-flight callbacks to complete (with timeout)
    {
        std::unique_lock<std::recursive_mutex> lock(client->mutex);
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
        while (client->callbacksInFlight.load(std::memory_order_acquire) > 0) {
            if (client->callbacksDone.wait_until(lock, deadline) == std::cv_status::timeout) {
                BLOG_WARN("snapclient_destroy: timeout waiting for callbacks, proceeding anyway");
                break;
            }
        }
    }

    // Phase 3: Stop and cleanup
    snapclient_stop(client);
    delete client;
}

/* ── Connection ─────────────────────────────────────────────────── */

bool snapclient_start(SnapClientRef client, const char* host, int port) {
    if (!client || !host) return false;

    std::lock_guard<std::recursive_mutex> lock(client->mutex);

    if (client->state.load() != SNAPCLIENT_STATE_DISCONNECTED) {
        return false; // already running
    }

    // HARD RESET: Clear TimeProvider's stale clock data from previous server
    // This prevents clock drift issues (-1.68e+08ms) when switching servers
    TimeProvider::getInstance().reset();
    BLOG_INFO("TimeProvider reset for new connection");

    client->host = host;
    client->port = port;
    BLOG_INFO("start: host=%s, port=%d", host, port);
    notify_state(client, SNAPCLIENT_STATE_CONNECTING);

    try {
        // Create io_context
        client->io_context = std::make_unique<boost::asio::io_context>();
        client->work_guard = std::make_unique<work_guard_t>(client->io_context->get_executor());
        BLOG_INFO("io_context created");

        // Configure ClientSettings
        ClientSettings settings;
        std::string uri_str = "tcp://" + client->host + ":" + std::to_string(client->port);
        settings.server.uri = StreamUri(uri_str);
        settings.player.player_name = player::IOS_PLAYER;
        settings.player.latency = client->latency_ms.load();
        settings.instance = client->instance;
        settings.host_id = client->name;
        BLOG_INFO("settings: uri=%s, player=%s, host_id=%s, instance=%d",
                  uri_str.c_str(), settings.player.player_name.c_str(),
                  settings.host_id.c_str(), static_cast<int>(settings.instance));

        // Create Controller
        client->controller = std::make_unique<Controller>(*client->io_context, settings);
        BLOG_INFO("Controller created");

        // Start Controller — synchronous TCP connect + queues async hello/read
        BLOG_INFO("calling controller->start()...");
        client->controller->start();
        BLOG_INFO("controller->start() returned (TCP connected, async ops queued)");

        // Run io_context in background thread
        client->io_thread = std::thread([client]() {
            BLOG_INFO("io_context thread started");
            try {
                auto n = client->io_context->run();
                BLOG_INFO("io_context.run() returned, handlers executed: %lu",
                          static_cast<unsigned long>(n));
            } catch (const std::exception& e) {
                BLOG_ERROR("io_context exception: %s", e.what());
            }
            BLOG_INFO("io_context thread exiting (state=%d)",
                      static_cast<int>(client->state.load()));
            // Only notify disconnected if we were previously connected
            // (avoids race with main thread's notify_state calls)
            if (client->state.load() != SNAPCLIENT_STATE_DISCONNECTED) {
                notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
            }
        });

        // Mark as connected (Controller will update to PLAYING when stream starts)
        notify_state(client, SNAPCLIENT_STATE_CONNECTED);
        BLOG_INFO("connected, io_context running in background");
        return true;

    } catch (const std::exception& e) {
        BLOG_ERROR("failed to start: %s", e.what());
        // Cleanup on failure
        client->controller.reset();
        client->work_guard.reset();
        client->io_context.reset();
        notify_state(client, SNAPCLIENT_STATE_DISCONNECTED);
        return false;
    }
}

void snapclient_stop(SnapClientRef client) {
    if (!client) return;

    // Check if already disconnected (atomic read, no lock needed)
    if (client->state.load() == SNAPCLIENT_STATE_DISCONNECTED) {
        return;
    }

    // Phase 1: Signal shutdown (under lock)
    {
        std::lock_guard<std::recursive_mutex> lock(client->mutex);

        // Double-check under lock
        if (client->state.load() == SNAPCLIENT_STATE_DISCONNECTED) {
            return;
        }

        // Stop io_context - this signals the worker thread to exit
        // Note: Socket cleanup happens via the destructor chain:
        // controller.reset() -> ~Controller -> ~ClientConnection -> disconnect()
        if (client->work_guard) {
            client->work_guard.reset();
        }
        if (client->io_context) {
            client->io_context->stop();
        }
    }
    // Lock is released here - this allows io_thread's notify_state to complete

    // Phase 2: Wait for worker thread (NO lock - avoids deadlock with notify_state)
    if (client->io_thread.joinable()) {
        client->io_thread.join();
    }

    // Phase 3: Cleanup (under lock)
    {
        std::lock_guard<std::recursive_mutex> lock(client->mutex);
        client->controller.reset();
        client->io_context.reset();
    }

    // Reset time provider to clear stale sync data from previous server
    TimeProvider::getInstance().reset();

    // Notify disconnected state (notify_state handles its own locking)
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

/* ── Playback control ───────────────────────────────────────────── */

void snapclient_pause(SnapClientRef client) {
    if (!client) return;
    BLOG_INFO("pause: pausing audio playback");
    player::g_ios_player_paused.store(true);
}

void snapclient_resume(SnapClientRef client) {
    if (!client) return;
    BLOG_INFO("resume: resuming audio playback");
    player::g_ios_player_paused.store(false);
}

bool snapclient_is_paused(SnapClientRef client) {
    // Use global player state as single source of truth
    std::ignore = client;
    return player::g_ios_player_paused.load();
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
    std::lock_guard<std::recursive_mutex> lock(client->mutex);
    client->name = name;
}

void snapclient_set_instance(SnapClientRef client, int instance) {
    if (!client) return;
    std::lock_guard<std::recursive_mutex> lock(client->mutex);
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
    if (client->destroying.load(std::memory_order_acquire)) return;  // Reject during destroy

    std::lock_guard<std::recursive_mutex> lock(client->mutex);
    client->state_cb = callback;
    client->state_ctx = ctx;
}

void snapclient_set_settings_callback(SnapClientRef client,
                                      SnapClientSettingsCallback callback,
                                      void* ctx) {
    if (!client) return;
    if (client->destroying.load(std::memory_order_acquire)) return;  // Reject during destroy

    std::lock_guard<std::recursive_mutex> lock(client->mutex);
    client->settings_cb = callback;
    client->settings_ctx = ctx;
}

void snapclient_set_instance_log_callback(SnapClientRef client,
                                          SnapClientLogCallback callback,
                                          void* ctx) {
    if (!client) return;
    if (client->destroying.load(std::memory_order_acquire)) return;  // Reject during destroy

    std::lock_guard<std::recursive_mutex> lock(client->mutex);
    client->log_cb = callback;
    client->log_ctx = ctx;
}

/* ── Audio session ──────────────────────────────────────────────── */

bool snapclient_configure_audio_session(void) {
    // Audio session must be configured from Swift on iOS
    // (this file is compiled as C++, not Objective-C++)
    BLOG_INFO("configure_audio_session: delegating to Swift");
    return true;
}

/* ── Clock synchronization ──────────────────────────────────────── */

void snapclient_reset_clock(void) {
    BLOG_INFO("reset_clock: resetting TimeProvider for foreground resume");
    TimeProvider::getInstance().reset();
}

/* ── Diagnostics ────────────────────────────────────────────────── */

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int snapclient_test_tcp(const char* host, int port) {
    BLOG_INFO("test_tcp: connecting to %s:%d", host, port);

    // Resolve hostname
    struct addrinfo hints = {};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo* res = nullptr;
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    int err = getaddrinfo(host, port_str, &hints, &res);
    if (err != 0) {
        BLOG_ERROR("test_tcp: getaddrinfo failed: %s", gai_strerror(err));
        return err;
    }
    BLOG_INFO("test_tcp: resolved %s", host);

    // Create socket
    int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sock < 0) {
        int e = errno;
        BLOG_ERROR("test_tcp: socket() failed: %s", strerror(e));
        freeaddrinfo(res);
        return e;
    }
    BLOG_INFO("test_tcp: socket created fd=%d", sock);

    // Connect
    if (connect(sock, res->ai_addr, res->ai_addrlen) < 0) {
        int e = errno;
        BLOG_ERROR("test_tcp: connect() failed: %s", strerror(e));
        close(sock);
        freeaddrinfo(res);
        return e;
    }
    BLOG_INFO("test_tcp: connected!");
    freeaddrinfo(res);

    // Send a simple test message (Snapcast base message header is 26 bytes)
    // We'll send garbage - server will reject it but we'll see if bytes flow
    const char test_msg[] = "SNAPTEST";
    ssize_t sent = send(sock, test_msg, sizeof(test_msg), 0);
    if (sent < 0) {
        int e = errno;
        BLOG_ERROR("test_tcp: send() failed: %s", strerror(e));
        close(sock);
        return e;
    }
    BLOG_INFO("test_tcp: sent %zd bytes", sent);

    // Try to read response (with timeout)
    struct timeval tv = {2, 0};  // 2 second timeout
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    char buf[256];
    ssize_t rcvd = recv(sock, buf, sizeof(buf) - 1, 0);
    if (rcvd < 0) {
        int e = errno;
        if (e == EAGAIN || e == EWOULDBLOCK) {
            BLOG_INFO("test_tcp: recv timeout (server didn't respond in 2s)");
        } else {
            BLOG_ERROR("test_tcp: recv() failed: %s", strerror(e));
        }
    } else if (rcvd == 0) {
        BLOG_INFO("test_tcp: server closed connection (expected - we sent garbage)");
    } else {
        BLOG_INFO("test_tcp: received %zd bytes", rcvd);
    }

    close(sock);
    BLOG_INFO("test_tcp: done, connection works!");
    return 0;
}

/* ── Version ────────────────────────────────────────────────────── */

const char* snapclient_version(void) {
    return VERSION;
}

int snapclient_protocol_version(void) {
    return 2;
}
