# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Initial iOS Client** - Feb 3
  - SwiftUI-based Snapcast client with server discovery
  - Real-time audio playback via AudioQueue Services
  - Volume and mute control per client

- **Auto-Connect and Dynamic RPC** ([#3](https://github.com/lollonet/snapclient-ios/pull/3)) - Feb 4
  - Automatically reconnect to last saved server on app launch
  - Dynamic RPC port discovery instead of hardcoded 1780

- **iOS Cross-Compilation** ([#4](https://github.com/lollonet/snapclient-ios/pull/4)) - Feb 4
  - CMake toolchain files for iOS device and simulator builds
  - XcodeGen-based project generation for reproducible builds
  - AudioQueue-based player implementation

- **Per-Client Mute Button** ([#11](https://github.com/lollonet/snapclient-ios/pull/11)) - Feb 7
  - Mute toggle button on each client row (speaker icon)
  - Visual dimming (opacity 0.5) when muted
  - Slider tint changes to secondary when muted

- **Now Playing Integration** ([#12](https://github.com/lollonet/snapclient-ios/pull/12)) - Feb 9
  - Lock screen / Control Center display with artist, title, album art
  - Play/Pause buttons in Control Center
  - Headphone and AirPods remote control support
  - Album artwork caching

### Changed
- **Modern UI Design** ([#18](https://github.com/lollonet/snapclient-ios/pull/18)) - Feb 10
  - Adaptive album art scaling (160-280pt based on screen width)
  - Progressive disclosure with collapsible technical details
  - Compact single-row client layout (~33% space savings)
  - Haptic feedback on volume slider release
  - Improved VoiceOver accessibility

### Fixed
- **Code Review Improvements** ([#2](https://github.com/lollonet/snapclient-ios/pull/2)) - Feb 4
  - Memory safety: unregister C callbacks before destroying client
  - Race condition: add `[weak self]` to RPC closures
  - Auto-reconnect on unexpected disconnect
  - Audio session interruption handling

- **Quality Improvements** ([#6](https://github.com/lollonet/snapclient-ios/pull/6)) - Feb 4
  - Bridge race condition in state notifications
  - Duplicate AudioQueueCreateTimeline call removed
  - Exponential backoff for reconnection (2s -> 60s cap)

- **Autotools Cross-Compilation** ([#7](https://github.com/lollonet/snapclient-ios/pull/7)) - Feb 5
  - Fix configure hanging on Apple Silicon when building vendor libs
  - Force cross-compilation mode with correct build/host triplets

- **WebSocket RPC** ([#8](https://github.com/lollonet/snapclient-ios/pull/8)) - Feb 5
  - Replace raw TCP with WebSocket for RPC client
  - Fixes "bad method" errors from Snapcast control server

- **iOS Platform Shims** ([#9](https://github.com/lollonet/snapclient-ios/pull/9)) - Feb 6
  - Fix popen/fork crash by overriding with safe stubs
  - Add IOKit stubs for MACOS code paths
  - Fix player instantiation (coreaudio vs ios)

- **Code Review Bug Fixes** ([#10](https://github.com/lollonet/snapclient-ios/pull/10)) - Feb 6
  - Main thread blocking: TCP connection moved to background
  - Race condition in C++ bridge notify_state()
  - Silent failures replaced with error alerts
  - Volume validation (clamp to 0-100)

- **Audio Stability** ([#19](https://github.com/lollonet/snapclient-ios/pull/19)) - Feb 10
  - AudioQueue callback deadlock resolved
  - Stuck C++ instance handling with zombie tracking
  - Strong reference cycles broken with weak self
  - Atomic flags for safe callback signaling

- **Deadlock-Free Audio Lifecycle** ([#20](https://github.com/lollonet/snapclient-ios/pull/20)) - Feb 10
  - Non-blocking MainActor invalidation
  - Real-time safe audio callback (no mutex in hot path)
  - Bridge lifecycle guard prevents callbacks after destroy
  - Clock drift fix (TimeProvider reset at connection start)
  - Incremental RPC updates (~90% network reduction)
  - UI performance: background image decompression

### Maintenance
- **CI/CD Setup** ([#5](https://github.com/lollonet/snapclient-ios/pull/5)) - Feb 4
  - GitHub Actions workflow for iOS builds
  - SwiftLint integration
  - Claude Code GitHub integration ([#1](https://github.com/lollonet/snapclient-ios/pull/1))

- **Stability Tests** - Feb 10
  - Swift XCTest stress tests for engine lifecycle
  - C++ bridge stability tests
  - Signing configuration for local development
