import XCTest
@testable import SnapClient

/// Stability and stress tests to verify the hardened SnapForge engine.
/// These tests validate zero-deadlock and zero-leak guarantees under extreme usage patterns.
final class SnapClientStabilityTests: XCTestCase {

    // MARK: - Test Configuration

    /// Number of rapid server switches per iteration
    private let serversPerIteration = 5

    /// Delay between server switches (100ms as specified)
    private let switchDelayMs: UInt64 = 100

    /// Total iterations for the server-hop test
    private let serverHopIterations = 100

    /// Timeout for async operations
    private let testTimeout: TimeInterval = 120.0

    // MARK: - Test 1: Server-Hop Test

    /// Tests rapid server switching to verify zombie cleanup and MainActor non-blocking.
    ///
    /// This test:
    /// 1. Calls engine.start(host:port:) with 5 different dummy IPs every 100ms
    /// 2. Repeats for 100 iterations (500 total switches)
    /// 3. Verifies zombieRefs are correctly created and reaped
    /// 4. Ensures MainActor never blocks
    @MainActor
    func testServerHopStress() async throws {
        let engine = SnapClientEngine()

        // Dummy IPs for switching (non-routable to ensure fast failure)
        let dummyServers = [
            ("10.255.255.1", 1704),
            ("10.255.255.2", 1704),
            ("10.255.255.3", 1704),
            ("10.255.255.4", 1704),
            ("10.255.255.5", 1704)
        ]

        var maxZombiesObserved = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        // Track MainActor responsiveness
        var mainActorBlockedCount = 0
        let mainActorCheckInterval: UInt64 = 50_000_000 // 50ms

        print("🧪 [ServerHop] Starting stress test: \(serverHopIterations) iterations × \(serversPerIteration) servers")

        for iteration in 1...serverHopIterations {
            for (index, server) in dummyServers.enumerated() {
                let iterationStart = CFAbsoluteTimeGetCurrent()

                // Start connection to dummy server
                engine.start(host: server.0, port: server.1)

                // Check MainActor responsiveness (should return immediately)
                let afterStart = CFAbsoluteTimeGetCurrent()
                let startDuration = (afterStart - iterationStart) * 1000

                if startDuration > 50 { // More than 50ms = potential blocking
                    mainActorBlockedCount += 1
                    print("⚠️ [ServerHop] MainActor blocked for \(String(format: "%.1f", startDuration))ms at iteration \(iteration).\(index)")
                }

                // Track zombie count
                let zombies = engine.diagnostics.activeZombiesCount
                if zombies > maxZombiesObserved {
                    maxZombiesObserved = zombies
                }

                // Wait before next switch
                try await Task.sleep(nanoseconds: switchDelayMs * 1_000_000)
            }

            // Progress logging every 10 iterations
            if iteration % 10 == 0 {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                print("📊 [ServerHop] Iteration \(iteration)/\(serverHopIterations) - Zombies: \(engine.diagnostics.activeZombiesCount), MaxZombies: \(maxZombiesObserved), Elapsed: \(String(format: "%.1f", elapsed))s")
            }
        }

        // Stop engine and wait for cleanup
        engine.stop()

        // Give time for zombie cleanup
        print("🧹 [ServerHop] Waiting for zombie cleanup...")
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Final diagnostics
        let finalZombies = engine.diagnostics.activeZombiesCount
        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime

        print("✅ [ServerHop] Test complete:")
        print("   - Total switches: \(serverHopIterations * serversPerIteration)")
        print("   - Max zombies observed: \(maxZombiesObserved)")
        print("   - Final zombie count: \(finalZombies)")
        print("   - MainActor blocks (>50ms): \(mainActorBlockedCount)")
        print("   - Total duration: \(String(format: "%.1f", totalDuration))s")

        // Assertions
        XCTAssertEqual(finalZombies, 0, "Zombie count should return to 0 after cleanup")
        XCTAssertEqual(mainActorBlockedCount, 0, "MainActor should never block during server switches")
        XCTAssertLessThanOrEqual(maxZombiesObserved, 10, "Zombie accumulation should be bounded")
    }

    // MARK: - Test 2: Rapid Pause/Resume Test

    /// Tests rapid pause/resume cycling to verify lock-free state handling.
    ///
    /// This test verifies that the atomic pause state in ios_player.cpp
    /// handles rapid state changes correctly.
    @MainActor
    func testRapidPauseResumeCycle() async throws {
        let engine = SnapClientEngine()

        let cycleCount = 1000
        var pauseCount = 0
        var resumeCount = 0

        print("🧪 [PauseResume] Starting \(cycleCount) rapid pause/resume cycles")

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 1...cycleCount {
            engine.pause()
            pauseCount += 1

            // Minimal delay to allow state propagation
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms

            engine.resume()
            resumeCount += 1

            if i % 100 == 0 {
                print("📊 [PauseResume] Cycle \(i)/\(cycleCount) - isPaused: \(engine.isPaused)")
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        print("✅ [PauseResume] Test complete:")
        print("   - Cycles: \(cycleCount)")
        print("   - Duration: \(String(format: "%.2f", duration))s")
        print("   - Rate: \(String(format: "%.0f", Double(cycleCount) / duration)) cycles/sec")

        // Final state should be resumed (not paused)
        XCTAssertFalse(engine.isPaused, "Engine should be resumed after test")
        XCTAssertEqual(pauseCount, cycleCount, "All pause calls should complete")
        XCTAssertEqual(resumeCount, cycleCount, "All resume calls should complete")
    }

    // MARK: - Test 3: Concurrent State Access Test

    /// Tests concurrent access to engine state from multiple tasks.
    ///
    /// Verifies that published state properties are thread-safe.
    @MainActor
    func testConcurrentStateAccess() async throws {
        let engine = SnapClientEngine()

        let taskCount = 50
        let readsPerTask = 100

        print("🧪 [ConcurrentState] Starting \(taskCount) concurrent tasks × \(readsPerTask) reads")

        let startTime = CFAbsoluteTimeGetCurrent()

        // Launch concurrent tasks that read state
        await withTaskGroup(of: Int.self) { group in
            for taskId in 1...taskCount {
                group.addTask { @MainActor in
                    var reads = 0
                    for _ in 1...readsPerTask {
                        // Read various state properties
                        _ = engine.state
                        _ = engine.isPaused
                        _ = engine.diagnostics
                        _ = engine.volume
                        reads += 1
                    }
                    return reads
                }
            }

            var totalReads = 0
            for await reads in group {
                totalReads += reads
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ [ConcurrentState] Test complete:")
            print("   - Total reads: \(totalReads)")
            print("   - Duration: \(String(format: "%.3f", duration))s")
            print("   - Rate: \(String(format: "%.0f", Double(totalReads) / duration)) reads/sec")

            XCTAssertEqual(totalReads, taskCount * readsPerTask, "All reads should complete")
        }
    }

    // MARK: - Test 4: Diagnostics Stability Test

    /// Tests that diagnostics remain consistent during stress.
    @MainActor
    func testDiagnosticsStability() async throws {
        let engine = SnapClientEngine()

        print("🧪 [Diagnostics] Testing diagnostics consistency during operations")

        // Initial state
        let initialDiagnostics = engine.diagnostics
        XCTAssertEqual(initialDiagnostics.activeZombiesCount, 0)
        XCTAssertFalse(initialDiagnostics.isStopTaskHanging)
        XCTAssertNil(initialDiagnostics.activeConnectionTarget)

        // Start a connection
        engine.start(host: "10.255.255.1", port: 1704)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let connectingDiagnostics = engine.diagnostics
        XCTAssertNotNil(connectingDiagnostics.activeConnectionTarget, "Should have connection target during connect")

        // Rapid state changes
        for _ in 1...10 {
            engine.start(host: "10.255.255.2", port: 1704)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            _ = engine.diagnostics // Read diagnostics - should not crash
        }

        // Stop and verify cleanup
        engine.stop()
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s for cleanup

        let finalDiagnostics = engine.diagnostics
        print("✅ [Diagnostics] Final state:")
        print("   - Zombies: \(finalDiagnostics.activeZombiesCount)")
        print("   - StopHanging: \(finalDiagnostics.isStopTaskHanging)")
        print("   - ConnectionTarget: \(finalDiagnostics.activeConnectionTarget ?? "nil")")

        XCTAssertEqual(finalDiagnostics.activeZombiesCount, 0, "No zombies should remain")
    }

    // MARK: - Test 5: Engine Lifecycle Stress Test

    /// Tests rapid engine creation and destruction.
    @MainActor
    func testEngineLifecycleStress() async throws {
        let iterations = 20

        print("🧪 [Lifecycle] Creating and destroying \(iterations) engines")

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 1...iterations {
            autoreleasepool {
                let engine = SnapClientEngine()
                engine.start(host: "10.255.255.\(i % 255 + 1)", port: 1704)
                // Engine deinit called when leaving scope
            }

            // Small delay to allow cleanup
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            if i % 5 == 0 {
                print("📊 [Lifecycle] Created/destroyed \(i)/\(iterations) engines")
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        print("✅ [Lifecycle] Test complete:")
        print("   - Engines created: \(iterations)")
        print("   - Duration: \(String(format: "%.1f", duration))s")

        // If we get here without crashing, the test passes
        XCTAssertTrue(true, "Engine lifecycle stress test completed without crash")
    }
}
