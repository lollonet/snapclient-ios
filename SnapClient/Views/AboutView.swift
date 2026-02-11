import SwiftUI

/// About screen with app info, credits, and acknowledgments.
struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        NavigationStack {
            List {
                // MARK: - App Info
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "hifispeaker.2.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)

                            Text("SnapClient")
                                .font(.title.bold())

                            Text("Version \(appVersion) (\(buildNumber))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("iOS client for Snapcast multi-room audio")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                // MARK: - Links
                Section("Links") {
                    Link(destination: URL(string: "https://github.com/lollonet/snapclient-ios")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Source Code")
                                Text("github.com/lollonet/snapclient-ios")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                    }

                    Link(destination: URL(string: "https://github.com/lollonet/snapclient-ios/issues")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Report Issue / Feedback")
                                Text("GitHub Issues")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "ladybug")
                        }
                    }

                    Link(destination: URL(string: "https://github.com/badaix/snapcast")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Snapcast Project")
                                Text("github.com/badaix/snapcast")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "music.note.house")
                        }
                    }
                }

                // MARK: - Credits
                Section("Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Snapcast")
                            .font(.headline)
                        Text("Multi-room client-server audio player")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("by Johannes Pohl (badaix)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Open Source Libraries
                Section("Open Source Libraries") {
                    libraryRow(
                        name: "Snapcast",
                        description: "Multi-room audio synchronization",
                        license: "GPL-3.0"
                    )
                    libraryRow(
                        name: "Boost",
                        description: "C++ libraries (ASIO, Beast)",
                        license: "BSL-1.0"
                    )
                    libraryRow(
                        name: "OpenSSL",
                        description: "TLS/SSL cryptography",
                        license: "Apache-2.0"
                    )
                    libraryRow(
                        name: "FLAC",
                        description: "Free Lossless Audio Codec",
                        license: "BSD-3-Clause"
                    )
                    libraryRow(
                        name: "Opus",
                        description: "Audio codec",
                        license: "BSD-3-Clause"
                    )
                    libraryRow(
                        name: "Vorbis",
                        description: "Audio compression",
                        license: "BSD-3-Clause"
                    )
                    libraryRow(
                        name: "Ogg",
                        description: "Container format",
                        license: "BSD-3-Clause"
                    )
                }

                // MARK: - License
                Section("License") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MIT License")
                            .font(.headline)
                        Text("Copyright (c) 2026 SnapForge Contributors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("This app is open source. You are free to use, modify, and distribute it under the terms of the MIT License.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Build Info
                Section("Build Info") {
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                    if let snapcastVersion = snapcastCoreVersion() {
                        LabeledContent("Snapcast Core", value: snapcastVersion)
                    }
                }
            }
            .navigationTitle("About")
        }
    }

    @ViewBuilder
    private func libraryRow(name: String, description: String, license: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func snapcastCoreVersion() -> String? {
        guard let cStr = snapclient_version() else { return nil }
        return String(cString: cStr)
    }
}

#Preview {
    AboutView()
}
