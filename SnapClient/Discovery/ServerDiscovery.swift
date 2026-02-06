import Foundation
import Network
import Combine

/// A Snapcast server discovered via mDNS/Bonjour.
struct DiscoveredServer: Identifiable, Hashable {
    let id: String          // mDNS service name
    let name: String        // Human-readable name
    let host: String        // Resolved hostname or IP
    let port: Int           // Audio port (typically 1704)
    let txtRecord: [String: String]

    var displayName: String {
        txtRecord["name"] ?? name
    }

    /// Control API port (JSON-RPC). Defaults to audio port + 76 (1704 -> 1780).
    var controlPort: Int {
        if let portStr = txtRecord["control_port"], let port = Int(portStr) {
            return port
        }
        return port + 76
    }
}

/// Discovers Snapcast servers on the local network using mDNS (Bonjour).
///
/// Snapserver advertises `_snapcast._tcp` on the local network.
/// This class uses Network.framework's `NWBrowser` to discover them.
@MainActor
final class ServerDiscovery: ObservableObject {

    // MARK: - Published state

    @Published private(set) var servers: [DiscoveredServer] = []
    @Published private(set) var isSearching = false

    // MARK: - Private

    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]

    // Snapcast mDNS service type
    private static let serviceType = "_snapcast._tcp"

    // MARK: - Public API

    /// Start browsing for Snapcast servers.
    func startBrowsing() {
        guard browser == nil else { return }

        let params = NWParameters()
        params.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(
            type: Self.serviceType,
            domain: nil
        )

        let newBrowser = NWBrowser(for: descriptor, using: params)

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        newBrowser.start(queue: .main)
        browser = newBrowser
        isSearching = true
    }

    /// Stop browsing.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    // MARK: - Private

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        // Resolve each discovered endpoint
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else {
                continue
            }

            let serviceId = "\(name).\(type).\(domain)"
            if connections[serviceId] != nil { continue }

            // Parse TXT record
            var txtDict: [String: String] = [:]
            if case let .bonjour(record) = result.metadata {
                for key in record.dictionary.keys {
                    if let value = record.dictionary[key] {
                        txtDict[key] = value
                    }
                }
            }
            let txt = txtDict  // Capture as immutable for sendable closure

            // Resolve the endpoint by creating a temporary connection
            let conn = NWConnection(to: result.endpoint, using: .tcp)
            connections[serviceId] = conn

            conn.stateUpdateHandler = { [weak self, serviceId, name, txt] state in
                switch state {
                case .ready:
                    // Extract resolved host and port
                    if let innerEndpoint = conn.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = innerEndpoint {
                        // Extract clean IP/hostname string without interface suffix
                        // NWEndpoint.Host can include "%interface" suffix which breaks DNS
                        let hostString: String
                        switch host {
                        case .ipv4(let addr):
                            // Convert raw bytes to dotted decimal string
                            // Must convert Data to [UInt8] for correct subscripting
                            let bytes = [UInt8](addr.rawValue)
                            hostString = String(format: "%d.%d.%d.%d",
                                bytes[0], bytes[1], bytes[2], bytes[3])
                            print("[Discovery] IPv4: \(hostString)")
                        case .ipv6(let addr):
                            // For IPv6, use description but strip %interface suffix
                            let raw = "\(addr)"
                            if let idx = raw.firstIndex(of: "%") {
                                hostString = String(raw[..<idx])
                            } else {
                                hostString = raw
                            }
                            print("[Discovery] IPv6: \(hostString)")
                        case .name(let hostname, _):
                            hostString = hostname
                            print("[Discovery] Name: \(hostname)")
                        @unknown default:
                            // Strip %interface suffix if present
                            let raw = "\(host)"
                            if let idx = raw.firstIndex(of: "%") {
                                hostString = String(raw[..<idx])
                            } else {
                                hostString = raw
                            }
                            print("[Discovery] Unknown: \(hostString)")
                        }
                        let server = DiscoveredServer(
                            id: serviceId,
                            name: name,
                            host: hostString,
                            port: Int(port.rawValue),
                            txtRecord: txt
                        )
                        Task { @MainActor in
                            self?.addServer(server)
                            self?.connections.removeValue(forKey: serviceId)
                        }
                    }
                    conn.cancel()
                case .failed, .cancelled:
                    Task { @MainActor in
                        self?.connections.removeValue(forKey: serviceId)
                    }
                default:
                    break
                }
            }

            conn.start(queue: .global(qos: .userInitiated))
        }

        // Remove servers that are no longer advertised
        let activeIds = Set(results.compactMap { result -> String? in
            guard case let .service(name, type, domain, _) = result.endpoint else {
                return nil
            }
            return "\(name).\(type).\(domain)"
        })
        servers.removeAll { !activeIds.contains($0.id) }
    }

    private func addServer(_ server: DiscoveredServer) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
    }
}
