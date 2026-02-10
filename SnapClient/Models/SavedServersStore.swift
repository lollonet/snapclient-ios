import Foundation

/// Manages persistence of manually saved servers.
@MainActor
final class SavedServersStore: ObservableObject {
    @Published private(set) var servers: [SavedServer] = []

    private static let key = "savedServers"

    init() {
        load()
    }

    /// Add a new saved server.
    func add(_ server: SavedServer) {
        servers.append(server)
        save()
    }

    /// Remove servers at specified offsets.
    func remove(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        save()
    }

    /// Remove a specific server by ID.
    func remove(_ server: SavedServer) {
        servers.removeAll { $0.id == server.id }
        save()
    }

    /// Update an existing server.
    func update(_ server: SavedServer) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SavedServer].self, from: data) else {
            return
        }
        servers = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            #if DEBUG
            print("[SavedServers] Failed to save: \(error)")
            #endif
        }
    }
}
