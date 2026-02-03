# snapclient-ios

**iOS client for [Snapcast](https://github.com/badaix/snapcast)** — part of the [SnapForge](https://github.com/lollonet/snapforge) ecosystem.

Turns your iPhone or iPad into a synchronized multiroom audio endpoint. Connects to any Snapcast server and plays audio in perfect sync with all other clients in your network.

## Architecture

```
┌──────────────────────────────────────┐
│         SwiftUI Interface            │  Swift
│   Player │ Groups │ Server Browser   │
├──────────────────────────────────────┤
│   SnapClientEngine    (Swift)        │  Engine wrapper
│   ServerDiscovery     (NWBrowser)    │  mDNS / Bonjour
│   SnapcastRPCClient   (Swift)        │  JSON-RPC control
├──────────────────────────────────────┤
│   snapclient_bridge.h (C interface)  │  Bridge layer
├──────────────────────────────────────┤
│   snapclient C++ core                │  Audio engine
│   ├── client_connection              │  TCP protocol
│   ├── time_provider                  │  Clock sync
│   ├── decoder/ (FLAC, PCM, Opus)     │  Codec decoding
│   └── player/coreaudio_player        │  AudioQueue output
├──────────────────────────────────────┤
│   Boost (headers) │ libFLAC │ Opus   │  C/C++ deps
└──────────────────────────────────────┘
```

**Why this architecture?** The Snapcast C++ client core has years of battle-tested clock synchronization and buffer management. Reimplementing it would risk subtle timing bugs. Instead, we compile it as a static library and wrap it with a clean C interface that Swift calls directly. The UI, networking (JSON-RPC, mDNS), and app lifecycle are native Swift.

## Features

- **Synchronized playback** — sub-millisecond sync with all Snapcast clients
- **All codecs** — FLAC, PCM, Opus, Vorbis (via C++ core)
- **Server discovery** — automatic via mDNS/Bonjour (zero configuration)
- **Remote control** — manage all clients, groups, and streams via JSON-RPC
- **Background audio** — keeps playing when the app is minimized
- **iOS media controls** — Control Center and lock screen integration
- **Dark mode** — native iOS appearance support
- **VPN support** — works over cellular + VPN to home network

## Requirements

- macOS 14+ with Xcode 16+
- CMake 3.21+
- autotools (`brew install autoconf automake libtool`)
- iOS 16.0+ device (arm64)

## Building

### 1. Build C++ dependencies

```bash
./scripts/build-deps.sh
```

This downloads and cross-compiles for iOS arm64:
- Boost 1.87.0 (headers only)
- libogg 1.3.5
- libFLAC 1.4.3
- libopus 1.5.2
- Snapcast 0.34.0 (client core)

### 2. Open in Xcode

```bash
open SnapClient.xcodeproj
```

Select your iOS device and build (Cmd+R).

### 3. Or build from CLI

```bash
xcodebuild build \
  -project SnapClient.xcodeproj \
  -scheme SnapClient \
  -destination 'generic/platform=iOS' \
  -configuration Release
```

## Project Structure

```
snapclient-ios/
├── SnapClient/                  # Swift iOS app
│   ├── App/                     # App entry point, lifecycle
│   ├── Views/                   # SwiftUI views (Player, Groups, Servers)
│   ├── Engine/                  # SnapClientEngine (Swift ↔ C++ bridge)
│   │   └── Bridge/              # Bridging header
│   ├── Control/                 # JSON-RPC client for server control
│   └── Discovery/               # mDNS server discovery
├── SnapClientCore/              # C++ static library
│   ├── CMakeLists.txt           # iOS cross-compilation config
│   ├── bridge/                  # C bridge (snapclient_bridge.h/.cpp)
│   └── vendor/                  # Dependencies (git-ignored, built by script)
├── scripts/
│   └── build-deps.sh           # Build all C/C++ dependencies
├── .github/workflows/
│   └── build.yml               # CI: build deps, build app, lint
└── README.md
```

## How It Works

### Audio path (port 1704)
1. **TCP connection** to Snapserver on port 1704
2. **Hello** handshake (client identity, protocol version)
3. **Codec Header** received (FLAC/PCM/Opus stream format)
4. **Wire Chunks** decoded and queued for playback
5. **Time sync** messages exchanged periodically to maintain sub-ms sync
6. **CoreAudio** AudioQueue outputs PCM to the device speaker/headphones

### Control path (port 1780)
1. **TCP connection** to Snapserver JSON-RPC API on port 1780
2. **Server.GetStatus** retrieves all groups, clients, and streams
3. **Client.SetVolume**, **Group.SetMute**, etc. for real-time control
4. **Notifications** pushed by server for state changes

### Discovery
- Snapserver advertises `_snapcast._tcp` via mDNS
- iOS `NWBrowser` (Network.framework) discovers servers automatically
- No IP configuration required

## Development Roadmap

### Phase 1 — Core (current)
- [x] Project structure and build system
- [x] C bridge interface (`snapclient_bridge.h`)
- [x] Swift engine wrapper (`SnapClientEngine`)
- [x] mDNS discovery (`ServerDiscovery`)
- [x] JSON-RPC control client (`SnapcastRPCClient`)
- [x] SwiftUI views (Player, Groups, Servers)
- [ ] Wire up C++ core to bridge (compile snapclient for iOS)
- [ ] End-to-end audio playback test

### Phase 2 — MVP
- [ ] Background audio (AVAudioSession configuration)
- [ ] iOS media controls (MPNowPlayingInfoCenter)
- [ ] Automatic reconnection on network change
- [ ] Volume and latency adjustment via UI

### Phase 3 — Feature parity
- [ ] Group management (create, rename, assign clients)
- [ ] Stream selection per group
- [ ] Now Playing metadata display (artist, title, album art)
- [ ] Dark mode and theme support
- [ ] Haptic feedback

### Phase 4 — Distribution
- [ ] TestFlight beta
- [ ] App Store submission
- [ ] App icon and launch screen
- [ ] Privacy policy and App Store metadata

## Related Projects

| Component | Repository |
|-----------|-----------|
| **SnapForge** (meta-repo) | [lollonet/snapforge](https://github.com/lollonet/snapforge) |
| **snapMULTI** (server) | [lollonet/snapMULTI](https://github.com/lollonet/snapMULTI) |
| **rpi-snapclient-usb** (Pi client) | [lollonet/rpi-snapclient-usb](https://github.com/lollonet/rpi-snapclient-usb) |
| **SnapCTRL** (desktop controller) | [lollonet/snapctrl](https://github.com/lollonet/snapctrl) |
| **santcasp** (Snapcast fork) | [lollonet/santcasp](https://github.com/lollonet/santcasp) |
| **Snapcast** (upstream) | [badaix/snapcast](https://github.com/badaix/snapcast) |

## License

MIT — see [LICENSE](LICENSE).
