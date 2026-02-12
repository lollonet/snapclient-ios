import Foundation

/// Manages persistence of manually saved servers.
@MainActor
final class SavedServersStore: ObservableObject {
    @Published private(set) var servers: [SavedServer] = []

    private static let key = "savedServers"
    private static let versionKey = "savedServersVersion"
    private static let currentVersion = 1

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
        let version = UserDefaults.standard.integer(forKey: Self.versionKey)

        // Handle migration if needed
        if version < Self.currentVersion && version > 0 {
            migrate(from: version)
        }

        guard let data = UserDefaults.standard.data(forKey: Self.key) else {
            return
        }

        do {
            servers = try JSONDecoder().decode([SavedServer].self, from: data)
        } catch {
            #if DEBUG
            print("[SavedServers] Failed to decode: \(error). Data may be corrupted.")
            #endif
            // Don't crash - start with empty list if decode fails
            servers = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: Self.key)
            UserDefaults.standard.set(Self.currentVersion, forKey: Self.versionKey)
        } catch {
            #if DEBUG
            print("[SavedServers] Failed to save: \(error)")
            #endif
        }
    }

    /// Migrate data from older versions.
    private func migrate(from oldVersion: Int) {
        // Future migrations go here
        // Example:
        // if oldVersion < 2 {
        //     // Migrate v1 -> v2 schema changes
        // }
        #if DEBUG
        print("[SavedServers] Migrating from v\(oldVersion) to v\(Self.currentVersion)")
        #endif
    }
}
