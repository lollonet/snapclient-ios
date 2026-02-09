import SwiftUI
import UIKit

/// Reusable volume slider that handles its own editing state and syncs with server values.
///
/// Usage:
/// ```swift
/// SnapVolumeSlider(
///     value: client.config.volume.percent,
///     isMuted: client.config.volume.muted,
///     onCommit: { newPercent in
///         try await rpcClient.setClientVolume(...)
///     }
/// )
/// ```
struct SnapVolumeSlider: View {
    /// Current volume percent from server (0-100)
    let serverValue: Int

    /// Whether the source is muted
    var isMuted: Bool = false

    /// Called when user finishes dragging with the new value
    let onCommit: (Int) async throws -> Void

    /// Optional error handler
    var onError: ((Error) -> Void)?

    // MARK: - Private state

    @State private var sliderValue: Double = 0
    @State private var isEditing = false

    var body: some View {
        Slider(
            value: $sliderValue,
            in: 0...100,
            step: 1
        ) { editing in
            let wasEditing = isEditing
            isEditing = editing
            if wasEditing && !editing {
                // Haptic feedback on commit
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                commitChange()
            }
        }
        .tint(isMuted ? .secondary : .accentColor)
        .accessibilityValue("\(Int(sliderValue)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                sliderValue = min(100, sliderValue + 5)
                commitChange()
            case .decrement:
                sliderValue = max(0, sliderValue - 5)
                commitChange()
            @unknown default:
                break
            }
        }
        .onAppear {
            sliderValue = Double(serverValue)
        }
        .onChange(of: serverValue) { _, newValue in
            // Only sync from server when not actively editing
            if !isEditing {
                sliderValue = Double(newValue)
            }
        }
    }

    private func commitChange() {
        let newValue = Int(sliderValue)
        Task {
            do {
                try await onCommit(newValue)
            } catch {
                onError?(error)
            }
        }
    }
}

/// Volume slider with integrated percentage label and mute button.
struct SnapVolumeControl: View {
    /// Current volume percent from server (0-100)
    let serverValue: Int

    /// Whether the source is muted
    let isMuted: Bool

    /// Called when user finishes dragging with the new value
    let onVolumeCommit: (Int) async throws -> Void

    /// Called when mute button is tapped
    let onMuteToggle: () async throws -> Void

    /// Optional error handler
    var onError: ((Error) -> Void)?

    // MARK: - Private state

    @State private var sliderValue: Double = 0
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                SnapVolumeSlider(
                    serverValue: serverValue,
                    isMuted: isMuted,
                    onCommit: onVolumeCommit,
                    onError: onError
                )
            }
            .opacity(isMuted ? 0.4 : 1.0)

            HStack {
                Text("\(serverValue)%")
                    .font(.caption)
                    .monospacedDigit()
                    .accessibilityHidden(true)

                Spacer()

                Button {
                    Task {
                        do {
                            try await onMuteToggle()
                        } catch {
                            onError?(error)
                        }
                    }
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(isMuted ? .red : .accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Volume Slider") {
    VStack(spacing: 20) {
        SnapVolumeSlider(
            serverValue: 75,
            isMuted: false,
            onCommit: { _ in }
        )
        .padding()

        SnapVolumeSlider(
            serverValue: 50,
            isMuted: true,
            onCommit: { _ in }
        )
        .padding()
    }
}
