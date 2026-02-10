import Foundation

/// A manually saved Snapcast server.
struct SavedServer: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String        // User-defined name
    var host: String        // IP or hostname
    var port: Int           // Audio port (default 1704)

    init(id: UUID = UUID(), name: String = "", host: String, port: Int = 1704) {
        self.id = id
        self.name = name.isEmpty ? host : name
        self.host = host
        self.port = port
    }

    /// Control API port (JSON-RPC). Defaults to audio port + 76 (1704 -> 1780).
    var controlPort: Int { port + 76 }

    /// Display name for UI (name if set, otherwise host).
    var displayName: String { name.isEmpty ? host : name }
}
