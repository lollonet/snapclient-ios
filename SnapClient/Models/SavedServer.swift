import Foundation

// MARK: - URL Utilities

extension URL {
    /// Create a URL from a string, converting HTTP to HTTPS for App Transport Security compliance.
    ///
    /// Most artwork servers (coverartarchive.org, etc.) support HTTPS, so this allows
    /// seamless loading without ATS exceptions.
    static func secureURL(from string: String) -> URL? {
        let secure = string.hasPrefix("http://")
            ? string.replacingOccurrences(of: "http://", with: "https://")
            : string
        return URL(string: secure)
    }
}

// MARK: - SavedServer

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
