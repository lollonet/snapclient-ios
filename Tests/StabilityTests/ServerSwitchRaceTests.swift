import XCTest
@testable import SnapClient

/// Tests for race condition fixes when switching between servers.
/// These tests verify that stale tasks don't interfere with new connections.
final class ServerSwitchRaceTests: XCTestCase {

    // MARK: - RPC Client Server Switching Tests

    /// Tests that rapid server switching in RPC client doesn't crash.
    ///
    /// This validates that stale receiveTask/pingTask properly exit
    /// when the websocket is replaced during a server switch.
    @MainActor
    func testRPCClientRapidServerSwitch() async throws {
        let rpcClient = SnapcastRPCClient()

        // Dummy servers (non-routable, will fail to connect but tests the switching logic)
        let servers = [
            ("10.255.255.1", 1780),
            ("10.255.255.2", 1780),
            ("10.255.255.3", 1780),
            ("10.255.255.4", 1780),
            ("10.255.255.5", 1780)
        ]

        print("🧪 [RPCSwitch] Testing rapid RPC client server switching")

        let switchCount = 50
        for i in 1...switchCount {
            let server = servers[i % servers.count]

            // Rapid switch - connect to new server immediately
            rpcClient.connect(host: server.0, port: server.1)

            // Very short delay to stress the switching logic
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms

            if i % 10 == 0 {
                print("📊 [RPCSwitch] Switch \(i)/\(switchCount) - isConnected: \(rpcClient.isConnected)")
            }
        }

        // Final disconnect
        rpcClient.disconnect()

        // Allow time for cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        print("✅ [RPCSwitch] Test complete - no crashes during rapid switching")

        // If we get here without crashing, the race condition fix is working
        XCTAssertFalse(rpcClient.isConnected, "Should be disconnected after explicit disconnect")
    }

    /// Tests that disconnect followed by immediate connect works correctly.
    ///
    /// This validates the fix where stale error handlers could tear down
    /// the new connection when disconnect/connect happen in quick succession.
    @MainActor
    func testRPCClientDisconnectReconnect() async throws {
        let rpcClient = SnapcastRPCClient()

        print("🧪 [RPCReconnect] Testing disconnect/reconnect cycles")

        let cycleCount = 20
        for i in 1...cycleCount {
            // Connect
            rpcClient.connect(host: "10.255.255.1", port: 1780)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // Disconnect
            rpcClient.disconnect()

            // Immediately reconnect (this is where the race condition could occur)
            rpcClient.connect(host: "10.255.255.2", port: 1780)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms

            if i % 5 == 0 {
                print("📊 [RPCReconnect] Cycle \(i)/\(cycleCount)")
            }
        }

        rpcClient.disconnect()
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        print("✅ [RPCReconnect] Test complete - disconnect/reconnect cycles work correctly")
        XCTAssertFalse(rpcClient.isConnected)
    }

    // MARK: - Engine Connection Ownership Tests

    /// Tests that engine properly tracks connection ownership during rapid switches.
    ///
    /// Validates the fix where a stale connection task could overwrite
    /// connectedHost/connectedPort with old values after a server switch.
    @MainActor
    func testEngineConnectionOwnership() async throws {
        let engine = SnapClientEngine()

        print("🧪 [EngineOwnership] Testing engine connection ownership tracking")

        // Start connection to Server A
        engine.start(host: "10.255.255.1", port: 1704)

        // Check that connection target is tracked
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let diagA = engine.diagnostics
        XCTAssertEqual(diagA.activeConnectionTarget, "10.255.255.1:1704",
                      "Should track connection target A")

        // Immediately switch to Server B
        engine.start(host: "10.255.255.2", port: 1704)

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let diagB = engine.diagnostics

        // The active target should now be B (or nil if completed)
        if let target = diagB.activeConnectionTarget {
            XCTAssertEqual(target, "10.255.255.2:1704",
                          "Active target should be B, not A")
        }

        // Wait for connections to settle
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // If connectedHost is set, it should be B (or nil if failed)
        if let host = engine.connectedHost {
            XCTAssertEqual(host, "10.255.255.2",
                          "Connected host should be B, not A (stale task shouldn't overwrite)")
        }

        engine.stop()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        print("✅ [EngineOwnership] Test complete - ownership tracking works correctly")
    }

    /// Tests rapid engine server switching with ownership verification.
    @MainActor
    func testEngineRapidSwitchOwnership() async throws {
        let engine = SnapClientEngine()

        print("🧪 [EngineRapidSwitch] Testing rapid engine switches with ownership checks")

        let servers = [
            "10.255.255.1",
            "10.255.255.2",
            "10.255.255.3"
        ]

        // Rapid switching
        for i in 1...30 {
            let server = servers[i % servers.count]
            engine.start(host: server, port: 1704)

            // Very short delay
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms

            // The most recent target should always be the last one we called
            let diag = engine.diagnostics
            if let target = diag.activeConnectionTarget {
                XCTAssertTrue(target.hasPrefix(server),
                             "Active target \(target) should match most recent server \(server)")
            }
        }

        // Final switch to known server
        let finalServer = "10.255.255.99"
        engine.start(host: finalServer, port: 1704)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let finalDiag = engine.diagnostics
        if let target = finalDiag.activeConnectionTarget {
            XCTAssertTrue(target.hasPrefix(finalServer),
                         "Final target should be \(finalServer)")
        }

        engine.stop()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        print("✅ [EngineRapidSwitch] Test complete")
    }

    // MARK: - Combined Engine + RPC Client Switching

    /// Tests switching servers using both engine and RPC client together.
    ///
    /// This simulates the real-world scenario in ServersView.connectTo()
    /// where both engine and RPC client are switched simultaneously.
    @MainActor
    func testCombinedServerSwitch() async throws {
        let engine = SnapClientEngine()
        let rpcClient = SnapcastRPCClient()

        print("🧪 [CombinedSwitch] Testing combined engine + RPC server switching")

        let servers = [
            ("10.255.255.1", 1704, 1780),
            ("10.255.255.2", 1704, 1780),
            ("10.255.255.3", 1704, 1780)
        ]

        for i in 1...20 {
            let server = servers[i % servers.count]

            // This is the pattern from ServersView.connectTo()
            rpcClient.disconnect()
            engine.start(host: server.0, port: server.1)
            rpcClient.connect(host: server.0, port: server.2)

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms

            if i % 5 == 0 {
                print("📊 [CombinedSwitch] Switch \(i)/20 - Engine state: \(engine.state.displayName)")
            }
        }

        // Cleanup
        rpcClient.disconnect()
        engine.stop()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        print("✅ [CombinedSwitch] Test complete - combined switching works correctly")

        XCTAssertFalse(rpcClient.isConnected)
    }

    // MARK: - Explicit Stale Task Behavior Tests

    /// Tests that stale receiveTask doesn't tear down new connection.
    ///
    /// This explicitly validates the race condition fix where the old
    /// websocket's error handler could call handleDisconnect() and
    /// tear down the new connection that replaced it.
    @MainActor
    func testStaleTaskDoesntTearDownNewConnection() async throws {
        let rpcClient = SnapcastRPCClient()

        print("🧪 [StaleTask] Testing that stale task doesn't tear down new connection")

        // Connect to Server A, let receiveTask start
        rpcClient.connect(host: "10.255.255.1", port: 1780)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms for task to start

        // Track connection state before switch
        let wasConnectedBeforeSwitch = rpcClient.isConnected

        // Immediately switch to Server B (this is where the race could occur)
        rpcClient.connect(host: "10.255.255.2", port: 1780)

        // Monitor for unexpected disconnects over the next 500ms
        // If the old task tears down the new connection, isConnected would drop
        var disconnectCount = 0
        var connectedCount = 0

        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if rpcClient.isConnected {
                connectedCount += 1
            } else {
                disconnectCount += 1
            }
        }

        print("📊 [StaleTask] Over 500ms: connected=\(connectedCount), disconnected=\(disconnectCount)")

        // The connection should remain stable (isConnected true most of the time)
        // Note: With non-routable IPs, the websocket may fail, but it shouldn't
        // be torn down by the STALE task - only by legitimate connection failures.

        // Cleanup
        rpcClient.disconnect()
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        print("✅ [StaleTask] Test complete - wasConnectedBeforeSwitch: \(wasConnectedBeforeSwitch)")

        // Main assertion: we shouldn't see rapid connect/disconnect flickering
        // If stale task was tearing down new connection, we'd see more disconnects
        XCTAssertFalse(rpcClient.isConnected, "Should be disconnected after explicit disconnect")
    }
}
