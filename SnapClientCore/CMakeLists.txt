cmake_minimum_required(VERSION 3.21)
project(SnapClientCore C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# ── iOS cross-compilation ────────────────────────────────────────────
if(NOT DEFINED CMAKE_SYSTEM_NAME OR NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR
    "This CMakeLists.txt is for iOS only.\n"
    "Use: cmake -G Xcode -DCMAKE_SYSTEM_NAME=iOS "
    "-DCMAKE_OSX_ARCHITECTURES=arm64 "
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 ..")
endif()

set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum iOS version")
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architecture")

# ── Paths ────────────────────────────────────────────────────────────
set(SNAPCAST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/snapcast"
    CACHE PATH "Path to snapcast source tree")
set(BOOST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/boost"
    CACHE PATH "Path to Boost headers")
set(FLAC_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/flac"
    CACHE PATH "Path to libFLAC (built for iOS)")
set(OPUS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/opus"
    CACHE PATH "Path to libopus (built for iOS)")
set(OGG_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/ogg"
    CACHE PATH "Path to libogg (built for iOS)")

# ── Boost (header-only) ─────────────────────────────────────────────
include_directories(SYSTEM "${BOOST_ROOT}")

# ── Snapcast sources ────────────────────────────────────────────────
# Core client files (no main())
set(SNAPCLIENT_SOURCES
  ${SNAPCAST_DIR}/client/client_connection.cpp
  ${SNAPCAST_DIR}/client/controller.cpp
  ${SNAPCAST_DIR}/client/stream.cpp
  ${SNAPCAST_DIR}/client/time_provider.cpp
  ${SNAPCAST_DIR}/client/decoder/flac_decoder.cpp
  ${SNAPCAST_DIR}/client/decoder/pcm_decoder.cpp
  ${SNAPCAST_DIR}/client/decoder/opus_decoder.cpp
  ${SNAPCAST_DIR}/client/decoder/ogg_decoder.cpp
  ${SNAPCAST_DIR}/client/player/coreaudio_player.cpp
  ${SNAPCAST_DIR}/common/utils/logging.cpp
  ${SNAPCAST_DIR}/common/message/message.cpp
  ${SNAPCAST_DIR}/common/time_defs.cpp
)

# Include paths
include_directories(
  ${SNAPCAST_DIR}
  ${SNAPCAST_DIR}/client
  ${SNAPCAST_DIR}/common
  ${FLAC_ROOT}/include
  ${OPUS_ROOT}/include
  ${OGG_ROOT}/include
)

# ── Compile definitions ─────────────────────────────────────────────
add_compile_definitions(
  HAS_COREAUDIO          # Enable CoreAudio player backend
  HAS_FLAC               # Enable FLAC decoder
  HAS_OPUS               # Enable Opus decoder
  HAS_OGG                # Enable Ogg container support
  IOS                    # iOS-specific code paths
  BOOST_ASIO_NO_DEPRECATED
)

# ── Static library: snapclient core ─────────────────────────────────
add_library(snapclient_core STATIC ${SNAPCLIENT_SOURCES})

target_link_directories(snapclient_core PRIVATE
  ${FLAC_ROOT}/lib
  ${OPUS_ROOT}/lib
  ${OGG_ROOT}/lib
)

target_link_libraries(snapclient_core PRIVATE
  FLAC
  opus
  ogg
  "-framework AudioToolbox"
  "-framework CoreAudio"
  "-framework AVFAudio"
  "-framework Foundation"
)

# ── Bridge library (C interface for Swift) ───────────────────────────
add_library(snapclient_bridge STATIC
  ${CMAKE_CURRENT_SOURCE_DIR}/bridge/snapclient_bridge.cpp
)
target_link_libraries(snapclient_bridge PRIVATE snapclient_core)
target_include_directories(snapclient_bridge PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/bridge
)

# ── Install ──────────────────────────────────────────────────────────
install(TARGETS snapclient_core snapclient_bridge
  ARCHIVE DESTINATION lib
)
install(FILES bridge/snapclient_bridge.h
  DESTINATION include
)
