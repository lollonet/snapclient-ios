import SwiftUI

/// Sheet for editing client settings.
struct ClientEditSheet: View {
    let client: SnapcastClient
    let currentGroupId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var name: String = ""
    @State private var latency: String = ""
    @State private var selectedGroupId: String = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Client Info") {
                    LabeledContent("ID", value: client.id)
                    if let host = client.host {
                        if let hostName = host.name {
                            LabeledContent("Host", value: hostName)
                        }
                        if let ip = host.ip {
                            LabeledContent("IP", value: ip)
                        }
                        if let os = host.os {
                            LabeledContent("OS", value: os)
                        }
                    }
                    HStack {
                        Circle()
                            .fill(client.connected ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(client.connected ? "Connected" : "Disconnected")
                    }
                }

                Section("Settings") {
                    TextField("Display Name", text: $name)
                    TextField("Latency (ms)", text: $latency)
                        .keyboardType(.numberPad)
                }

                if let groups = rpcClient.serverStatus?.groups, groups.count > 1 {
                    Section("Group") {
                        Picker("Move to Group", selection: $selectedGroupId) {
                            ForEach(groups) { group in
                                Text(group.name.isEmpty ? "Group \(group.id.prefix(8))" : group.name)
                                    .tag(group.id)
                            }
                        }
                    }
                }

                Section {
                    Button("Delete Client", role: .destructive) {
                        Task {
                            do {
                                try await rpcClient.deleteClient(clientId: client.id)
                                await rpcClient.refreshStatus()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                    .disabled(client.connected)
                }
            }
            .navigationTitle("Edit Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
            .onAppear {
                name = client.config.name
                latency = String(client.config.latency)
                selectedGroupId = currentGroupId
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func saveChanges() {
        Task {
            do {
                // Save name if changed
                if name != client.config.name {
                    #if DEBUG
                    print("[ClientEdit] setClientName: clientId=\(client.id), name=\(name)")
                    #endif
                    try await rpcClient.setClientName(clientId: client.id, name: name)
                }
                // Save latency if changed
                if let newLatency = Int(latency), newLatency != client.config.latency {
                    #if DEBUG
                    print("[ClientEdit] setClientLatency: clientId=\(client.id), latency=\(newLatency)")
                    #endif
                    try await rpcClient.setClientLatency(clientId: client.id, latency: newLatency)
                }
                // Move to different group if changed
                if selectedGroupId != currentGroupId {
                    // Get current clients in target group and add this one
                    if let targetGroup = rpcClient.serverStatus?.groups.first(where: { $0.id == selectedGroupId }) {
                        var clientIds = targetGroup.clients.map(\.id)
                        clientIds.append(client.id)
                        #if DEBUG
                        print("[ClientEdit] setGroupClients: groupId=\(selectedGroupId), clientIds=\(clientIds)")
                        #endif
                        try await rpcClient.setGroupClients(groupId: selectedGroupId, clientIds: clientIds)
                    }
                }
                await rpcClient.refreshStatus()
                dismiss()
            } catch {
                #if DEBUG
                print("[ClientEdit] error: \(error.localizedDescription)")
                #endif
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

/// Sheet for editing group settings.
struct GroupEditSheet: View {
    let group: SnapcastGroup
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var name: String = ""
    @State private var selectedStreamId: String = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Info") {
                    LabeledContent("ID", value: String(group.id.prefix(8)))
                    LabeledContent("Clients", value: "\(group.clients.count)")
                }

                Section("Settings") {
                    TextField("Group Name", text: $name)
                }

                if let streams = rpcClient.serverStatus?.streams, !streams.isEmpty {
                    Section("Stream") {
                        Picker("Audio Stream", selection: $selectedStreamId) {
                            ForEach(streams) { stream in
                                HStack {
                                    Text(stream.id)
                                    if stream.status == "playing" {
                                        Image(systemName: "music.note")
                                    }
                                }
                                .tag(stream.id)
                            }
                        }
                    }
                }

                Section("Clients") {
                    ForEach(group.clients) { client in
                        HStack {
                            Circle()
                                .fill(client.connected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(client.config.name.isEmpty ? (client.host?.name ?? client.id) : client.config.name)
                        }
                    }
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
            .onAppear {
                name = group.name
                selectedStreamId = group.stream_id
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func saveChanges() {
        Task {
            do {
                // Save name if changed
                if name != group.name {
                    #if DEBUG
                    print("[GroupEdit] setGroupName: groupId=\(group.id), name=\(name)")
                    #endif
                    try await rpcClient.setGroupName(groupId: group.id, name: name)
                }
                // Save stream if changed
                if selectedStreamId != group.stream_id {
                    #if DEBUG
                    print("[GroupEdit] setGroupStream: groupId=\(group.id), streamId=\(selectedStreamId)")
                    #endif
                    try await rpcClient.setGroupStream(groupId: group.id, streamId: selectedStreamId)
                }
                await rpcClient.refreshStatus()
                dismiss()
            } catch {
                #if DEBUG
                print("[GroupEdit] error: \(error.localizedDescription)")
                #endif
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
