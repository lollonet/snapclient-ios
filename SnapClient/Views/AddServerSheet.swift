import SwiftUI

/// Sheet for adding or editing a manual server.
struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var savedServers: SavedServersStore

    /// If set, we're editing an existing server.
    var editingServer: SavedServer?

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "1704"

    private var isEditing: Bool { editingServer != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                        .textContentType(.name)

                    TextField("Host (IP or hostname)", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    TextField("Port", text: $portString)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Default port is 1704. Control port (RPC) is automatically calculated as port + 76.")
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveServer()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let server = editingServer {
                    name = server.name == server.host ? "" : server.name
                    host = server.host
                    portString = "\(server.port)"
                }
            }
        }
    }

    private func saveServer() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        // Validate port range (1-65535), default to 1704 if invalid
        let port = Int(portString).map { max(1, min(65535, $0)) } ?? 1704

        if let existing = editingServer {
            // Update existing
            var updated = existing
            updated.name = name.isEmpty ? trimmedHost : name
            updated.host = trimmedHost
            updated.port = port
            savedServers.update(updated)
        } else {
            // Add new
            let server = SavedServer(
                name: name.isEmpty ? trimmedHost : name,
                host: trimmedHost,
                port: port
            )
            savedServers.add(server)
        }
        dismiss()
    }
}
