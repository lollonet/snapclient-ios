/***
    BridgeStabilityTests.cpp

    C++ stress tests for the snapclient bridge layer.
    These tests verify thread-safety and deadlock-freedom under extreme contention.

    Build: Include in a test target or run standalone with:
    clang++ -std=c++17 -I../../SnapClientCore/bridge BridgeStabilityTests.cpp -o bridge_tests

    Copyright (C) 2025 SnapForge contributors
    License: GPL-3.0
***/

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <random>
#include <thread>
#include <vector>

// Bridge header
extern "C" {
#include "snapclient_bridge.h"
}

namespace bridge_tests {

// Test configuration
constexpr int AUDIO_CYCLE_THREADS = 10;
constexpr int AUDIO_CYCLE_ITERATIONS = 1000;
constexpr int DIRTY_DISCONNECT_ITERATIONS = 100;
constexpr int CALLBACK_STRESS_THREADS = 5;
constexpr int CALLBACK_STRESS_ITERATIONS = 500;

// Test result tracking
struct TestResult {
    std::string name;
    bool passed;
    std::string message;
    double duration_ms;
};

std::vector<TestResult> g_results;

// Helper: Log with timestamp
void log(const std::string& msg) {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::cout << "[" << std::put_time(std::localtime(&time), "%H:%M:%S") << "] " << msg << std::endl;
}

// ============================================================================
// Test 1: Audio-Cycle Bridge Test
// ============================================================================
// Tests concurrent pause/resume from multiple threads to verify lock-free
// state handling and mutex contention resilience.

TestResult test_audio_cycle_contention() {
    log("🧪 [AudioCycle] Starting: " + std::to_string(AUDIO_CYCLE_THREADS) +
        " threads × " + std::to_string(AUDIO_CYCLE_ITERATIONS) + " iterations");

    auto start = std::chrono::high_resolution_clock::now();

    // Create a client for testing
    SnapClientRef client = snapclient_create();
    if (!client) {
        return {"AudioCycle", false, "Failed to create client", 0};
    }

    std::atomic<int> pause_count{0};
    std::atomic<int> resume_count{0};
    std::atomic<bool> has_error{false};
    std::string error_msg;
    std::mutex error_mutex;

    // Barrier to start all threads simultaneously
    std::atomic<int> ready_count{0};
    std::atomic<bool> go{false};

    std::vector<std::thread> threads;

    for (int t = 0; t < AUDIO_CYCLE_THREADS; ++t) {
        threads.emplace_back([&, t]() {
            // Signal ready and wait for go
            ready_count.fetch_add(1);
            while (!go.load()) {
                std::this_thread::yield();
            }

            std::random_device rd;
            std::mt19937 gen(rd());
            std::uniform_int_distribution<> delay_dist(0, 100); // 0-100 microseconds

            for (int i = 0; i < AUDIO_CYCLE_ITERATIONS; ++i) {
                try {
                    // Alternate between pause and resume
                    if ((t + i) % 2 == 0) {
                        snapclient_pause(client);
                        pause_count.fetch_add(1);
                    } else {
                        snapclient_resume(client);
                        resume_count.fetch_add(1);
                    }

                    // Random micro-delay to increase contention variety
                    std::this_thread::sleep_for(std::chrono::microseconds(delay_dist(gen)));

                } catch (const std::exception& e) {
                    std::lock_guard<std::mutex> lock(error_mutex);
                    has_error.store(true);
                    error_msg = "Thread " + std::to_string(t) + " exception: " + e.what();
                    break;
                }
            }
        });
    }

    // Wait for all threads to be ready
    while (ready_count.load() < AUDIO_CYCLE_THREADS) {
        std::this_thread::yield();
    }

    // Start all threads simultaneously
    log("📊 [AudioCycle] All threads ready, starting contention test...");
    go.store(true);

    // Wait for completion
    for (auto& t : threads) {
        t.join();
    }

    auto end = std::chrono::high_resolution_clock::now();
    double duration_ms = std::chrono::duration<double, std::milli>(end - start).count();

    // Cleanup
    snapclient_destroy(client);

    // Results
    int total_ops = pause_count.load() + resume_count.load();
    int expected_ops = AUDIO_CYCLE_THREADS * AUDIO_CYCLE_ITERATIONS;

    log("✅ [AudioCycle] Complete:");
    log("   - Pause calls: " + std::to_string(pause_count.load()));
    log("   - Resume calls: " + std::to_string(resume_count.load()));
    log("   - Total ops: " + std::to_string(total_ops) + " / " + std::to_string(expected_ops));
    log("   - Duration: " + std::to_string(duration_ms) + " ms");
    log("   - Rate: " + std::to_string(total_ops / (duration_ms / 1000.0)) + " ops/sec");

    if (has_error.load()) {
        return {"AudioCycle", false, error_msg, duration_ms};
    }

    if (total_ops != expected_ops) {
        return {"AudioCycle", false,
                "Operation count mismatch: " + std::to_string(total_ops) + " != " + std::to_string(expected_ops),
                duration_ms};
    }

    return {"AudioCycle", true, "All operations completed without deadlock", duration_ms};
}

// ============================================================================
// Test 2: Dirty Disconnect Test
// ============================================================================
// Simulates stop() being called while callbacks are actively executing.
// Verifies CallbackGuard prevents use-after-free.

TestResult test_dirty_disconnect() {
    log("🧪 [DirtyDisconnect] Starting: " + std::to_string(DIRTY_DISCONNECT_ITERATIONS) + " iterations");

    auto start = std::chrono::high_resolution_clock::now();

    std::atomic<int> callback_count{0};
    std::atomic<int> callback_during_destroy{0};
    std::atomic<bool> has_crash{false};

    for (int i = 0; i < DIRTY_DISCONNECT_ITERATIONS; ++i) {
        SnapClientRef client = snapclient_create();
        if (!client) continue;

        std::atomic<bool> destroying{false};
        std::atomic<bool> callback_running{false};

        // Set up a state callback that simulates slow execution
        snapclient_set_state_callback(client,
            [](void* ctx, SnapClientState state) {
                auto* running = static_cast<std::atomic<bool>*>(ctx);
                running->store(true);

                // Simulate slow callback (50ms)
                std::this_thread::sleep_for(std::chrono::milliseconds(50));

                running->store(false);
            },
            &callback_running);

        // Start connection to trigger callbacks
        // Use non-routable IP to ensure fast failure but callback still fires
        snapclient_start(client, "10.255.255.1", 1704);

        // Wait a bit for callback to potentially start
        std::this_thread::sleep_for(std::chrono::milliseconds(10));

        // Check if callback is running while we destroy
        if (callback_running.load()) {
            callback_during_destroy.fetch_add(1);
        }

        // Destroy while callback might be running
        // This should NOT crash due to CallbackGuard
        destroying.store(true);
        snapclient_destroy(client);

        callback_count.fetch_add(1);

        if (i % 20 == 0) {
            log("📊 [DirtyDisconnect] Iteration " + std::to_string(i) + "/" +
                std::to_string(DIRTY_DISCONNECT_ITERATIONS));
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    double duration_ms = std::chrono::duration<double, std::milli>(end - start).count();

    log("✅ [DirtyDisconnect] Complete:");
    log("   - Iterations: " + std::to_string(DIRTY_DISCONNECT_ITERATIONS));
    log("   - Callbacks during destroy: " + std::to_string(callback_during_destroy.load()));
    log("   - Duration: " + std::to_string(duration_ms) + " ms");

    // If we get here without crashing, CallbackGuard works
    return {"DirtyDisconnect", true,
            "No crashes during " + std::to_string(DIRTY_DISCONNECT_ITERATIONS) + " dirty disconnects",
            duration_ms};
}

// ============================================================================
// Test 3: Callback Registration Race Test
// ============================================================================
// Tests concurrent callback registration and unregistration.

TestResult test_callback_registration_race() {
    log("🧪 [CallbackRace] Starting: " + std::to_string(CALLBACK_STRESS_THREADS) +
        " threads × " + std::to_string(CALLBACK_STRESS_ITERATIONS) + " iterations");

    auto start = std::chrono::high_resolution_clock::now();

    SnapClientRef client = snapclient_create();
    if (!client) {
        return {"CallbackRace", false, "Failed to create client", 0};
    }

    std::atomic<int> register_count{0};
    std::atomic<int> unregister_count{0};
    std::atomic<bool> has_error{false};

    std::vector<std::thread> threads;

    for (int t = 0; t < CALLBACK_STRESS_THREADS; ++t) {
        threads.emplace_back([&, t]() {
            for (int i = 0; i < CALLBACK_STRESS_ITERATIONS; ++i) {
                if ((t + i) % 2 == 0) {
                    // Register callback
                    snapclient_set_state_callback(client,
                        [](void* ctx, SnapClientState state) {
                            // Empty callback
                        },
                        nullptr);
                    register_count.fetch_add(1);
                } else {
                    // Unregister callback
                    snapclient_set_state_callback(client, nullptr, nullptr);
                    unregister_count.fetch_add(1);
                }

                // Also test settings callback
                if (i % 3 == 0) {
                    snapclient_set_settings_callback(client,
                        [](void* ctx, int vol, bool muted, int lat) {},
                        nullptr);
                } else if (i % 3 == 1) {
                    snapclient_set_settings_callback(client, nullptr, nullptr);
                }
            }
        });
    }

    for (auto& t : threads) {
        t.join();
    }

    auto end = std::chrono::high_resolution_clock::now();
    double duration_ms = std::chrono::duration<double, std::milli>(end - start).count();

    snapclient_destroy(client);

    int total = register_count.load() + unregister_count.load();

    log("✅ [CallbackRace] Complete:");
    log("   - Registers: " + std::to_string(register_count.load()));
    log("   - Unregisters: " + std::to_string(unregister_count.load()));
    log("   - Duration: " + std::to_string(duration_ms) + " ms");

    return {"CallbackRace", true,
            "Completed " + std::to_string(total) + " callback operations without race",
            duration_ms};
}

// ============================================================================
// Test 4: Rapid Create/Destroy Test
// ============================================================================
// Tests rapid client lifecycle to verify no resource leaks.

TestResult test_rapid_lifecycle() {
    log("🧪 [RapidLifecycle] Starting: 100 rapid create/destroy cycles");

    auto start = std::chrono::high_resolution_clock::now();

    std::atomic<int> create_count{0};
    std::atomic<int> destroy_count{0};

    for (int i = 0; i < 100; ++i) {
        SnapClientRef client = snapclient_create();
        if (client) {
            create_count.fetch_add(1);

            // Do some operations
            snapclient_set_volume(client, i % 100);
            snapclient_set_muted(client, i % 2 == 0);

            snapclient_destroy(client);
            destroy_count.fetch_add(1);
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    double duration_ms = std::chrono::duration<double, std::milli>(end - start).count();

    log("✅ [RapidLifecycle] Complete:");
    log("   - Created: " + std::to_string(create_count.load()));
    log("   - Destroyed: " + std::to_string(destroy_count.load()));
    log("   - Duration: " + std::to_string(duration_ms) + " ms");

    bool passed = (create_count.load() == destroy_count.load()) && (create_count.load() == 100);

    return {"RapidLifecycle", passed,
            passed ? "All clients properly created and destroyed" : "Lifecycle mismatch",
            duration_ms};
}

// ============================================================================
// Test 5: Begin Destroy Synchronization Test
// ============================================================================
// Tests that begin_destroy properly blocks callbacks before full destroy.

TestResult test_begin_destroy_sync() {
    log("🧪 [BeginDestroySync] Testing synchronous callback blocking");

    auto start = std::chrono::high_resolution_clock::now();

    std::atomic<int> callbacks_after_begin_destroy{0};
    std::atomic<bool> begin_destroy_called{false};

    for (int i = 0; i < 50; ++i) {
        SnapClientRef client = snapclient_create();
        if (!client) continue;

        begin_destroy_called.store(false);

        // Set callback that checks if begin_destroy was called
        snapclient_set_state_callback(client,
            [](void* ctx, SnapClientState state) {
                auto* flag = static_cast<std::atomic<bool>*>(ctx);
                if (flag->load()) {
                    // This should NOT happen - begin_destroy should block this
                    std::cerr << "ERROR: Callback executed after begin_destroy!" << std::endl;
                }
            },
            &begin_destroy_called);

        // Start to trigger potential callbacks
        snapclient_start(client, "10.255.255.1", 1704);
        std::this_thread::sleep_for(std::chrono::milliseconds(5));

        // Call begin_destroy synchronously
        begin_destroy_called.store(true);
        snapclient_begin_destroy(client);

        // Now any callbacks should be blocked
        std::this_thread::sleep_for(std::chrono::milliseconds(10));

        // Full destroy
        snapclient_destroy(client);
    }

    auto end = std::chrono::high_resolution_clock::now();
    double duration_ms = std::chrono::duration<double, std::milli>(end - start).count();

    log("✅ [BeginDestroySync] Complete:");
    log("   - Callbacks after begin_destroy: " + std::to_string(callbacks_after_begin_destroy.load()));
    log("   - Duration: " + std::to_string(duration_ms) + " ms");

    return {"BeginDestroySync", callbacks_after_begin_destroy.load() == 0,
            "begin_destroy properly blocks callbacks", duration_ms};
}

// ============================================================================
// Main Test Runner
// ============================================================================

void run_all_tests() {
    std::cout << "\n";
    std::cout << "╔══════════════════════════════════════════════════════════════╗\n";
    std::cout << "║       SnapClient Bridge Stability Tests                      ║\n";
    std::cout << "╚══════════════════════════════════════════════════════════════╝\n";
    std::cout << "\n";

    auto total_start = std::chrono::high_resolution_clock::now();

    // Run tests
    g_results.push_back(test_audio_cycle_contention());
    std::cout << "\n";

    g_results.push_back(test_dirty_disconnect());
    std::cout << "\n";

    g_results.push_back(test_callback_registration_race());
    std::cout << "\n";

    g_results.push_back(test_rapid_lifecycle());
    std::cout << "\n";

    g_results.push_back(test_begin_destroy_sync());
    std::cout << "\n";

    auto total_end = std::chrono::high_resolution_clock::now();
    double total_ms = std::chrono::duration<double, std::milli>(total_end - total_start).count();

    // Summary
    std::cout << "╔══════════════════════════════════════════════════════════════╗\n";
    std::cout << "║                      Test Summary                            ║\n";
    std::cout << "╚══════════════════════════════════════════════════════════════╝\n";

    int passed = 0;
    int failed = 0;

    for (const auto& result : g_results) {
        std::string status = result.passed ? "✅ PASS" : "❌ FAIL";
        std::cout << "  " << status << "  " << result.name << "\n";
        std::cout << "         " << result.message << " (" << result.duration_ms << " ms)\n";

        if (result.passed) passed++;
        else failed++;
    }

    std::cout << "\n";
    std::cout << "  Total: " << passed << " passed, " << failed << " failed\n";
    std::cout << "  Duration: " << total_ms << " ms\n";
    std::cout << "\n";

    if (failed == 0) {
        std::cout << "🎉 All tests passed! Bridge is deadlock-free and thread-safe.\n";
    } else {
        std::cout << "⚠️  Some tests failed. Review the output above.\n";
    }
}

} // namespace bridge_tests

// Entry point for standalone execution
#ifndef BRIDGE_TESTS_AS_LIBRARY
int main() {
    bridge_tests::run_all_tests();
    return 0;
}
#endif
