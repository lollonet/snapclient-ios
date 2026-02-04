#!/usr/bin/env bash
#
# build-deps-sim.sh — Build C/C++ dependencies for iOS Simulator (arm64)
#
# Rebuilds: libogg, libFLAC, libopus for iOS Simulator
# and the snapclient core libraries.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/SnapClientCore/vendor"
BUILD_DIR="$ROOT_DIR/build/deps"

# ── Versions ────────────────────────────────────────────────────────
FLAC_VERSION="1.4.3"
OPUS_VERSION="1.5.2"
OGG_VERSION="1.3.5"

# ── iOS Simulator build settings ─────────────────────────────────────
IOS_DEPLOYMENT_TARGET="17.0"
IOS_ARCH="arm64"
IOS_SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || echo "")

if [ -z "$IOS_SIM_SDK" ]; then
    echo "ERROR: Xcode iOS Simulator SDK not found."
    exit 1
fi

CC_IOS="$(xcrun --sdk iphonesimulator --find clang)"
CXX_IOS="$(xcrun --sdk iphonesimulator --find clang++)"

IOS_CFLAGS="-arch $IOS_ARCH -isysroot $IOS_SIM_SDK -mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
IOS_LDFLAGS="-arch $IOS_ARCH -isysroot $IOS_SIM_SDK -mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"

# ── Helpers ─────────────────────────────────────────────────────────
info()  { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$VENDOR_DIR" "$BUILD_DIR"

# ── 1. libogg ────────────────────────────────────────────────────────
build_ogg() {
    local dest="$VENDOR_DIR/ogg"

    info "Building libogg $OGG_VERSION for iOS Simulator..."
    local src="$BUILD_DIR/libogg-${OGG_VERSION}"

    if [ ! -d "$src" ]; then
        error "Source not found: $src. Run build-deps.sh first."
    fi

    cd "$src"
    make clean || true
    ./configure \
        --host=aarch64-apple-darwin \
        --prefix="$dest" \
        --enable-static \
        --disable-shared \
        CC="$CC_IOS" \
        CFLAGS="$IOS_CFLAGS" \
        LDFLAGS="$IOS_LDFLAGS"

    make -j"$(sysctl -n hw.ncpu)" install
    cd "$ROOT_DIR"

    info "libogg built for simulator."
}

# ── 2. libFLAC ───────────────────────────────────────────────────────
build_flac() {
    local dest="$VENDOR_DIR/flac"

    info "Building libFLAC $FLAC_VERSION for iOS Simulator..."
    local src="$BUILD_DIR/flac-${FLAC_VERSION}"

    if [ ! -d "$src" ]; then
        error "Source not found: $src. Run build-deps.sh first."
    fi

    cd "$src"
    make clean || true
    ./configure \
        --host=aarch64-apple-darwin \
        --prefix="$dest" \
        --enable-static \
        --disable-shared \
        --disable-cpplibs \
        --disable-programs \
        --disable-examples \
        --with-ogg="$VENDOR_DIR/ogg" \
        CC="$CC_IOS" \
        CFLAGS="$IOS_CFLAGS" \
        LDFLAGS="$IOS_LDFLAGS" \
        OGG_CFLAGS="-I$VENDOR_DIR/ogg/include" \
        OGG_LIBS="-L$VENDOR_DIR/ogg/lib -logg"

    make -j"$(sysctl -n hw.ncpu)" install
    cd "$ROOT_DIR"

    info "libFLAC built for simulator."
}

# ── 3. libopus ───────────────────────────────────────────────────────
build_opus() {
    local dest="$VENDOR_DIR/opus"

    info "Building libopus $OPUS_VERSION for iOS Simulator..."
    local src="$BUILD_DIR/opus-${OPUS_VERSION}"

    if [ ! -d "$src" ]; then
        error "Source not found: $src. Run build-deps.sh first."
    fi

    cd "$src"
    make clean || true
    ./configure \
        --host=aarch64-apple-darwin \
        --prefix="$dest" \
        --enable-static \
        --disable-shared \
        --disable-extra-programs \
        --disable-doc \
        CC="$CC_IOS" \
        CFLAGS="$IOS_CFLAGS" \
        LDFLAGS="$IOS_LDFLAGS"

    make -j"$(sysctl -n hw.ncpu)" install
    cd "$ROOT_DIR"

    info "libopus built for simulator."
}

# ── 4. Build snapclient core for iOS Simulator ───────────────────────
build_snapclient_core() {
    info "Building snapclient core library for iOS Simulator..."

    local build="$BUILD_DIR/snapclient_core"
    rm -rf "$build"
    mkdir -p "$build"

    cmake -B "$build" -S "$ROOT_DIR/SnapClientCore" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT_DIR/SnapClientCore/cmake/ios-simulator.toolchain.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DSNAPCAST_DIR="$VENDOR_DIR/snapcast" \
        -DBOOST_ROOT="$VENDOR_DIR/boost" \
        -DFLAC_ROOT="$VENDOR_DIR/flac" \
        -DOPUS_ROOT="$VENDOR_DIR/opus" \
        -DOGG_ROOT="$VENDOR_DIR/ogg"

    cmake --build "$build" --parallel

    info "snapclient core built for simulator."
}

# ── Run ──────────────────────────────────────────────────────────────
info "Building dependencies for iOS Simulator ($IOS_ARCH, deployment target $IOS_DEPLOYMENT_TARGET)"
info ""

build_ogg
build_flac
build_opus
build_snapclient_core

info ""
info "All dependencies built for iOS Simulator."
