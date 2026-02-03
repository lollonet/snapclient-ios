import Foundation
import Network

// MARK: - Data Models

/// Snapcast client volume.
struct ClientVolume: Codable, Sendable {
    var percent: Int
    var muted: Bool
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

private struct RPCNotification: Decodable {
    let method: String
    let params: AnyCodable?
}

// MARK: - JSON-RPC Client

/// Client for the Snapcast JSON-RPC control API (port 1780).
///
/// Supports both TCP and WebSocket transports.
/// Receives server notifications for real-time state updates.
@MainActor
final class SnapcastRPCClient: ObservableObject {

    // MARK: - Published state

    @Published private(set) var serverStatus: ServerStatus?
    @Published private(set) var isConnected = false

    // MARK: - Private

    private var connection: NWConnection?
    private var requestId = 0
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    private var receiveBuffer = Data()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Connection

    /// Connect to the Snapserver JSON-RPC API.
    func connect(host: String, port: Int = 1780) {
        disconnect()

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))

        connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.startReceiving()
                    await self?.refreshStatus()
                case .failed, .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }

        connection?.start(queue: .global(qos: .userInitiated))
    }

    /// Disconnect from the server.
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        serverStatus = nil
        pendingRequests.values.forEach {
            $0.resume(throwing: CancellationError())
        }
        pendingRequests.removeAll()
    }

    // MARK: - Server.GetStatus

    /// Refresh the full server status.
    func refreshStatus() async {
        do {
            let result: ServerStatusResult = try await call(
                method: "Server.GetStatus",
                params: nil
            )
            serverStatus = result.server
        } catch {
            // Connection error — will be reflected in isConnected
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
        requestId += 1
        let id = requestId

        let request = RPCRequest(id: id, method: method, params: params)
        var data = try encoder.encode(request)
        data.append(0x0A) // newline delimiter

        let responseData: Data = try await withCheckedThrowingContinuation { cont in
            pendingRequests[id] = cont
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error {
                    Task { @MainActor in
                        self.pendingRequests.removeValue(forKey: id)?
                            .resume(throwing: error)
                    }
                }
            })
        }

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
        connection?.receive(minimumIncompleteLength: 1,
                           maximumLength: 65536) { [weak self] data, _, _, error in
            if let data {
                Task { @MainActor in
                    self?.handleReceivedData(data)
                }
            }
            if error == nil {
                Task { @MainActor in
                    self?.startReceiving()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        // Split on newlines (JSON-RPC over TCP uses newline-delimited JSON)
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let messageData = receiveBuffer[receiveBuffer.startIndex..<newlineIndex]
            receiveBuffer = Data(receiveBuffer[receiveBuffer.index(after: newlineIndex)...])

            guard !messageData.isEmpty else { continue }

            // Try to match to a pending request
            if let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
               let id = json["id"] as? Int,
               let cont = pendingRequests.removeValue(forKey: id) {
                cont.resume(returning: Data(messageData))
            } else {
                // It's a notification — refresh status
                Task {
                    await refreshStatus()
                }
            }
        }
    }
}

// MARK: - AnyCodable helper

/// Minimal type-erased Codable for JSON-RPC params.
enum AnyCodable: Codable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case dict([String: AnyCodable])
    case array([AnyCodable])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .dict(let v):   try container.encode(v)
        case .array(let v):  try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self)            { self = .string(v) }
        else if let v = try? container.decode(Int.self)          { self = .int(v) }
        else if let v = try? container.decode(Bool.self)         { self = .bool(v) }
        else if let v = try? container.decode([String: AnyCodable].self) { self = .dict(v) }
        else if let v = try? container.decode([AnyCodable].self) { self = .array(v) }
        else { self = .null }
    }
}
