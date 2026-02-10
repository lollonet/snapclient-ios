import Foundation

// MARK: - Data Models

/// Snapcast client volume.
struct ClientVolume: Codable, Sendable {
    /// Volume percentage (always clamped to 0-100).
    var percent: Int {
        didSet { percent = max(0, min(100, percent)) }
    }
    var muted: Bool

    /// Create a volume with validated percent (clamped to 0-100).
    init(percent: Int, muted: Bool) {
        self.percent = max(0, min(100, percent))
        self.muted = muted
    }
}

/// Snapcast client info as returned by the server.
struct SnapcastClient: Codable, Identifiable, Sendable {
    let id: String
    var config: ClientConfig
    var connected: Bool
    var host: HostInfo?

    struct ClientConfig: Codable, Sendable {
        var name: String
        var volume: ClientVolume
        var latency: Int
        var instance: Int
    }

    struct HostInfo: Codable, Sendable {
        var arch: String?
        var ip: String?
        var mac: String?
        var name: String?
        var os: String?
    }
}

/// Snapcast group.
struct SnapcastGroup: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var stream_id: String
    var muted: Bool
    var clients: [SnapcastClient]
}

/// Snapcast stream.
struct SnapcastStream: Codable, Identifiable, Sendable {
    let id: String
    var status: String
    var uri: StreamURI?
    var properties: StreamProperties?

    struct StreamURI: Codable, Sendable {
        var raw: String?
        var scheme: String?
        var host: String?
        var path: String?
    }

    struct StreamProperties: Codable, Sendable {
        var metadata: StreamMetadata?
    }

    struct StreamMetadata: Codable, Sendable {
        var artist: String?
        var title: String?
        var album: String?
        var artUrl: String?

        enum CodingKeys: String, CodingKey {
            case artist, title, album
            case artUrl = "artUrl"
        }

        /// Memberwise initializer for incremental updates
        init(artist: String? = nil, title: String? = nil, album: String? = nil, artUrl: String? = nil) {
            self.artist = artist
            self.title = title
            self.album = album
            self.artUrl = artUrl
        }

        // Custom decoder to handle fields that can be String or [String]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            artist = Self.decodeStringOrArray(container, key: .artist)
            title = Self.decodeStringOrArray(container, key: .title)
            album = Self.decodeStringOrArray(container, key: .album)
            artUrl = try container.decodeIfPresent(String.self, forKey: .artUrl)
        }

        private static func decodeStringOrArray(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
            // Try String first
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
            // Try [String] and join
            if let values = try? container.decode([String].self, forKey: key) {
                return values.joined(separator: ", ")
            }
            return nil
        }
    }
}

/// Full server status.
struct ServerStatus: Codable, Sendable {
    var groups: [SnapcastGroup]
    var streams: [SnapcastStream]

    var allClients: [SnapcastClient] {
        groups.flatMap(\.clients)
    }
}

// MARK: - JSON-RPC types

private struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]?
}

private struct RPCResponse<T: Decodable>: Decodable {
    let id: Int?
    let result: T?
    let error: RPCError?
}

private struct RPCError: Decodable {
    let code: Int
    let message: String
}

// MARK: - JSON-RPC Client (WebSocket)

/// Client for the Snapcast JSON-RPC control API.
///
/// Uses WebSocket transport (ws://host:port/jsonrpc) as required
/// by Snapcast's control server.
@MainActor
final class SnapcastRPCClient: ObservableObject {

    // MARK: - Published state

    @Published private(set) var serverStatus: ServerStatus?
    @Published private(set) var isConnected = false

    /// Centralized error state for RPC operations.
    /// Views should observe this and show a single alert on ContentView.
    @Published var lastError: String?
    @Published var showError = false

    // MARK: - Private

    /// Prevents multiple concurrent refresh requests
    private var isRefreshing = false

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var requestId = 0
    /// Pending requests keyed by ID. Uses AnyHashable to support both Int and String IDs per JSON-RPC 2.0.
    private var pendingRequests: [AnyHashable: CheckedContinuation<Data, Error>] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    // Connection info for reconnection
    private var connectedHost: String?
    private var connectedPort: Int?

    // Ping interval to keep connection alive (30 seconds)
    private let pingInterval: TimeInterval = 30

    // Debounce refresh to avoid storm on rapid notifications
    private var lastRefreshTime: Date = .distantPast
    private var pendingRefreshTask: Task<Void, Never>?
    private let refreshDebounceInterval: TimeInterval = 0.5  // 500ms

    // MARK: - Connection

    /// Connect to the Snapserver JSON-RPC API via WebSocket.
    func connect(host: String, port: Int = 1780) {
        disconnect()

        connectedHost = host
        connectedPort = port

        let urlString = "ws://\(host):\(port)/jsonrpc"
        #if DEBUG
        print("[RPC] connecting to \(urlString)")
        #endif
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("[RPC] invalid URL")
            #endif
            return
        }

        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        isConnected = true
        startReceiving()
        startPinging()

        Task {
            await refreshStatus()
        }
    }

    /// Disconnect from the server.
    func disconnect() {
        // Cancel all background tasks
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        // Close WebSocket
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        // Clear state but keep host/port for potential reconnect
        isConnected = false
        serverStatus = nil
        pendingRequests.values.forEach {
            $0.resume(throwing: CancellationError())
        }
        pendingRequests.removeAll()
    }

    // MARK: - Error handling

    /// Handle and display an RPC error centrally.
    func handleError(_ error: Error) {
        lastError = error.localizedDescription
        showError = true
    }

    // MARK: - Server.GetStatus

    /// Refresh the full server status.
    /// Protected against concurrent calls with isRefreshing flag.
    func refreshStatus() async {
        // Prevent concurrent refresh requests
        guard !isRefreshing else {
            #if DEBUG
            print("[RPC] refreshStatus: already refreshing, skipping")
            #endif
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result: ServerStatusResult = try await call(
                method: "Server.GetStatus",
                params: nil
            )
            serverStatus = result.server
            lastRefreshTime = Date()
            #if DEBUG
            print("[RPC] refreshStatus: \(result.server.groups.count) groups, \(result.server.allClients.count) clients")
            #endif
        } catch {
            #if DEBUG
            print("[RPC] refreshStatus error: \(error)")
            #endif
        }
    }

    /// Debounced refresh - coalesces rapid notifications into a single refresh.
    /// Won't refresh more than once per refreshDebounceInterval.
    private func debouncedRefresh() {
        // Cancel any pending refresh
        pendingRefreshTask?.cancel()

        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)

        if timeSinceLastRefresh >= refreshDebounceInterval {
            // Enough time has passed, refresh immediately
            Task {
                await refreshStatus()
            }
        } else {
            // Schedule a refresh after the remaining debounce time
            let delay = refreshDebounceInterval - timeSinceLastRefresh
            pendingRefreshTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await refreshStatus()
            }
        }
    }

    private struct ServerStatusResult: Decodable {
        let server: ServerStatus
    }

    // MARK: - Client commands

    /// Set volume for a specific client.
    func setClientVolume(clientId: String, volume: ClientVolume) async throws {
        let _: EmptyResult = try await call(
            method: "Client.SetVolume",
            params: ["id": .string(clientId),
                     "volume": .dict(["percent": .int(volume.percent),
                                      "muted": .bool(volume.muted)])]
        )
    }

    /// Set display name for a client.
    func setClientName(clientId: String, name: String) async throws {
        let _: EmptyResult = try await call(
            method: "Client.SetName",
            params: ["id": .string(clientId), "name": .string(name)]
        )
    }

    /// Set latency for a client.
    func setClientLatency(clientId: String, latency: Int) async throws {
        let _: EmptyResult = try await call(
            method: "Client.SetLatency",
            params: ["id": .string(clientId), "latency": .int(latency)]
        )
    }

    // MARK: - Group commands

    /// Set the audio stream for a group.
    func setGroupStream(groupId: String, streamId: String) async throws {
        let _: EmptyResult = try await call(
            method: "Group.SetStream",
            params: ["id": .string(groupId), "stream_id": .string(streamId)]
        )
    }

    /// Mute/unmute a group.
    func setGroupMute(groupId: String, muted: Bool) async throws {
        let _: EmptyResult = try await call(
            method: "Group.SetMute",
            params: ["id": .string(groupId), "mute": .bool(muted)]
        )
    }

    /// Set group name.
    func setGroupName(groupId: String, name: String) async throws {
        let _: EmptyResult = try await call(
            method: "Group.SetName",
            params: ["id": .string(groupId), "name": .string(name)]
        )
    }

    /// Set which clients belong to a group.
    func setGroupClients(groupId: String, clientIds: [String]) async throws {
        let _: EmptyResult = try await call(
            method: "Group.SetClients",
            params: ["id": .string(groupId),
                     "clients": .array(clientIds.map { .string($0) })]
        )
    }

    // MARK: - Server commands

    /// Delete a client from the server.
    func deleteClient(clientId: String) async throws {
        let _: EmptyResult = try await call(
            method: "Server.DeleteClient",
            params: ["id": .string(clientId)]
        )
    }

    // MARK: - Internal JSON-RPC

    private struct EmptyResult: Decodable {}

    private func call<T: Decodable>(
        method: String,
        params: [String: AnyCodable]?
    ) async throws -> T {
        guard let webSocket else {
            throw NSError(domain: "SnapcastRPC", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        requestId += 1
        let id = requestId

        let request = RPCRequest(id: id, method: method, params: params)
        let data = try encoder.encode(request)

        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SnapcastRPC", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        }

        let responseData: Data = try await withCheckedThrowingContinuation { cont in
            pendingRequests[id] = cont
            webSocket.send(.string(text)) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.pendingRequests.removeValue(forKey: id)?
                            .resume(throwing: error)
                    }
                }
            }
        }

        #if DEBUG
        // Debug: print raw response
        if let rawString = String(data: responseData, encoding: .utf8) {
            print("[RPC] raw response (\(responseData.count) bytes): \(rawString.prefix(500))...")
        }
        #endif

        let response = try decoder.decode(RPCResponse<T>.self, from: responseData)
        if let error = response.error {
            throw NSError(domain: "SnapcastRPC", code: error.code,
                          userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        guard let result = response.result else {
            throw NSError(domain: "SnapcastRPC", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Empty result"])
        }
        return result
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            print("[RPC] startReceiving loop started")
            #endif
            while !Task.isCancelled {
                do {
                    guard let webSocket = await MainActor.run(body: { self.webSocket }) else {
                        #if DEBUG
                        print("[RPC] webSocket is nil, exiting receive loop")
                        #endif
                        break
                    }
                    let message = try await webSocket.receive()
                    await MainActor.run {
                        self.handleMessage(message)
                    }
                } catch {
                    #if DEBUG
                    print("[RPC] receive error: \(error)")
                    #endif
                    await MainActor.run {
                        self.handleDisconnect()
                    }
                    break
                }
            }
            #if DEBUG
            print("[RPC] receive loop ended")
            #endif
        }
    }

    private func startPinging() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pingInterval ?? 30))
                guard !Task.isCancelled else { break }

                guard let self,
                      let webSocket = await MainActor.run(body: { self.webSocket }) else {
                    break
                }

                do {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        webSocket.sendPing { error in
                            if let error {
                                cont.resume(throwing: error)
                            } else {
                                cont.resume()
                            }
                        }
                    }
                    #if DEBUG
                    print("[RPC] ping/pong ok")
                    #endif
                } catch {
                    #if DEBUG
                    print("[RPC] ping failed: \(error)")
                    #endif
                    await MainActor.run {
                        self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleDisconnect() {
        // Stop pinging
        pingTask?.cancel()
        pingTask = nil

        // Mark as disconnected
        isConnected = false

        // Clean up WebSocket
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        // Fail pending requests
        pendingRequests.values.forEach {
            $0.resume(throwing: NSError(domain: "SnapcastRPC", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Connection lost"]))
        }
        pendingRequests.removeAll()

        // Schedule reconnect
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard let host = connectedHost, let port = connectedPort else {
            #if DEBUG
            print("[RPC] no host/port for reconnect")
            #endif
            return
        }

        // Capture the target host to check against later
        let targetHost = host
        let targetPort = port

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            #if DEBUG
            print("[RPC] scheduling reconnect in 2s...")
            #endif
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }

                // Guard against ghost reconnections: only reconnect if target is still current
                guard self.connectedHost == targetHost && self.connectedPort == targetPort else {
                    #if DEBUG
                    print("[RPC] skipping ghost reconnect to \(targetHost):\(targetPort) (current: \(self.connectedHost ?? "nil"):\(self.connectedPort ?? 0))")
                    #endif
                    return
                }

                #if DEBUG
                print("[RPC] attempting reconnect to \(targetHost):\(targetPort)")
                #endif
                self.connect(host: targetHost, port: targetPort)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        // Try to match to a pending request
        // JSON-RPC 2.0 allows id to be Int or String, so handle both
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var requestId: AnyHashable?

            // Try Int first (most common)
            if let intId = json["id"] as? Int {
                requestId = intId
            }
            // Also handle String id (per JSON-RPC 2.0 spec) - supports any string, not just numeric
            else if let stringId = json["id"] as? String {
                // First try to match as the string itself
                requestId = stringId
                // If no match, try converting to Int (for servers that stringify numeric IDs)
                if pendingRequests[stringId] == nil, let intId = Int(stringId) {
                    requestId = intId
                }
            }

            if let id = requestId, let cont = pendingRequests.removeValue(forKey: id) {
                cont.resume(returning: data)
                return
            }

            // Server notification — try incremental update first
            if let method = json["method"] as? String,
               let params = json["params"] as? [String: Any] {
                if handleIncrementalUpdate(method: method, params: params) {
                    #if DEBUG
                    print("[RPC] Handled incrementally: \(method)")
                    #endif
                    return
                }
            }
        }

        // Fall back to full refresh for unhandled notifications
        debouncedRefresh()
    }

    // MARK: - Incremental Model Updates

    /// Handle notifications incrementally without full refresh.
    /// Returns true if handled, false if full refresh is needed.
    private func handleIncrementalUpdate(method: String, params: [String: Any]) -> Bool {
        guard var status = serverStatus else { return false }

        switch method {
        case "Client.OnVolumeChanged":
            guard let clientId = params["id"] as? String,
                  let volumeDict = params["volume"] as? [String: Any],
                  let percent = volumeDict["percent"] as? Int,
                  let muted = volumeDict["muted"] as? Bool else {
                return false
            }
            // Update client volume in all groups
            for groupIndex in status.groups.indices {
                if let clientIndex = status.groups[groupIndex].clients.firstIndex(where: { $0.id == clientId }) {
                    status.groups[groupIndex].clients[clientIndex].config.volume = ClientVolume(percent: percent, muted: muted)
                    serverStatus = status
                    #if DEBUG
                    print("[RPC] Incremental: Client \(clientId) volume -> \(percent)% muted=\(muted)")
                    #endif
                    return true
                }
            }
            return false

        case "Client.OnNameChanged":
            guard let clientId = params["id"] as? String,
                  let configDict = params["config"] as? [String: Any],
                  let name = configDict["name"] as? String else {
                return false
            }
            for groupIndex in status.groups.indices {
                if let clientIndex = status.groups[groupIndex].clients.firstIndex(where: { $0.id == clientId }) {
                    status.groups[groupIndex].clients[clientIndex].config.name = name
                    serverStatus = status
                    return true
                }
            }
            return false

        case "Client.OnLatencyChanged":
            guard let clientId = params["id"] as? String,
                  let configDict = params["config"] as? [String: Any],
                  let latency = configDict["latency"] as? Int else {
                return false
            }
            for groupIndex in status.groups.indices {
                if let clientIndex = status.groups[groupIndex].clients.firstIndex(where: { $0.id == clientId }) {
                    status.groups[groupIndex].clients[clientIndex].config.latency = latency
                    serverStatus = status
                    return true
                }
            }
            return false

        case "Client.OnConnect", "Client.OnDisconnect":
            // These require full refresh since client list changes
            return false

        case "Group.OnMute":
            guard let groupId = params["id"] as? String,
                  let mute = params["mute"] as? Bool else {
                return false
            }
            if let groupIndex = status.groups.firstIndex(where: { $0.id == groupId }) {
                status.groups[groupIndex].muted = mute
                serverStatus = status
                return true
            }
            return false

        case "Group.OnNameChanged":
            guard let groupId = params["id"] as? String,
                  let name = params["name"] as? String else {
                return false
            }
            if let groupIndex = status.groups.firstIndex(where: { $0.id == groupId }) {
                status.groups[groupIndex].name = name
                serverStatus = status
                return true
            }
            return false

        case "Group.OnStreamChanged":
            guard let groupId = params["id"] as? String,
                  let streamId = params["stream_id"] as? String else {
                return false
            }
            if let groupIndex = status.groups.firstIndex(where: { $0.id == groupId }) {
                status.groups[groupIndex].stream_id = streamId
                serverStatus = status
                return true
            }
            return false

        case "Stream.OnProperties":
            guard let streamId = params["id"] as? String,
                  let propsDict = params["properties"] as? [String: Any] else {
                return false
            }
            if let streamIndex = status.streams.firstIndex(where: { $0.id == streamId }) {
                // Decode properties incrementally
                if let metaDict = propsDict["metadata"] as? [String: Any] {
                    let artist = Self.extractStringOrArray(metaDict["artist"])
                    let title = Self.extractStringOrArray(metaDict["title"])
                    let album = Self.extractStringOrArray(metaDict["album"])
                    let artUrl = metaDict["artUrl"] as? String

                    // Create updated metadata - use existing if field is nil
                    let existingMeta = status.streams[streamIndex].properties?.metadata
                    let newMeta = SnapcastStream.StreamMetadata(
                        artist: artist ?? existingMeta?.artist,
                        title: title ?? existingMeta?.title,
                        album: album ?? existingMeta?.album,
                        artUrl: artUrl ?? existingMeta?.artUrl
                    )

                    // Update stream properties
                    if status.streams[streamIndex].properties == nil {
                        status.streams[streamIndex].properties = SnapcastStream.StreamProperties(metadata: newMeta)
                    } else {
                        status.streams[streamIndex].properties?.metadata = newMeta
                    }
                    serverStatus = status
                    #if DEBUG
                    print("[RPC] Incremental: Stream \(streamId) metadata -> \(title ?? "nil") by \(artist ?? "nil")")
                    #endif
                    return true
                }
            }
            return false

        case "Stream.OnUpdate":
            guard let streamId = params["id"] as? String,
                  let streamDict = params["stream"] as? [String: Any],
                  let streamStatus = streamDict["status"] as? String else {
                return false
            }
            if let streamIndex = status.streams.firstIndex(where: { $0.id == streamId }) {
                status.streams[streamIndex].status = streamStatus
                serverStatus = status
                return true
            }
            return false

        default:
            // Unknown notification - needs full refresh
            return false
        }
    }

    /// Extract a string or array of strings from JSON value
    private static func extractStringOrArray(_ value: Any?) -> String? {
        if let str = value as? String {
            return str
        }
        if let arr = value as? [String] {
            return arr.joined(separator: ", ")
        }
        return nil
    }
}

// MARK: - AnyCodable helper

/// Minimal type-erased Codable for JSON-RPC params.
enum AnyCodable: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dict([String: AnyCodable])
    case array([AnyCodable])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .dict(let v):   try container.encode(v)
        case .array(let v):  try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self)            { self = .string(v) }
        else if let v = try? container.decode(Bool.self)         { self = .bool(v) }
        else if let v = try? container.decode(Int.self)          { self = .int(v) }
        else if let v = try? container.decode(Double.self)       { self = .double(v) }
        else if let v = try? container.decode([String: AnyCodable].self) { self = .dict(v) }
        else if let v = try? container.decode([AnyCodable].self) { self = .array(v) }
        else { self = .null }
    }
}
