#!/usr/bin/env bash
#
# build-deps.sh — Build C/C++ dependencies for iOS (arm64)
#
# Downloads and builds: Boost (headers), libFLAC, libopus, libogg
# and clones the Snapcast source for the client core.
#
# Requirements: Xcode CLI tools, CMake, autotools, git
#
# Usage:
#   ./scripts/build-deps.sh          # Build everything
#   ./scripts/build-deps.sh clean    # Remove build artifacts
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/SnapClientCore/vendor"
BUILD_DIR="$ROOT_DIR/build/deps"

# ── Versions ────────────────────────────────────────────────────────
BOOST_VERSION="1.87.0"
BOOST_VERSION_UNDERSCORE="${BOOST_VERSION//./_}"
FLAC_VERSION="1.4.3"
OPUS_VERSION="1.5.2"
OGG_VERSION="1.3.5"
SNAPCAST_REPO="https://github.com/badaix/snapcast.git"
SNAPCAST_TAG="v0.34.0"

# ── iOS build settings ──────────────────────────────────────────────
IOS_DEPLOYMENT_TARGET="16.0"
IOS_ARCH="arm64"
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")

if [ -z "$IOS_SDK" ]; then
    echo "ERROR: Xcode iOS SDK not found. Install Xcode and CLI tools."
    exit 1
fi

CC_IOS="$(xcrun --sdk iphoneos --find clang)"
CXX_IOS="$(xcrun --sdk iphoneos --find clang++)"

IOS_CFLAGS="-arch $IOS_ARCH -isysroot $IOS_SDK -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"
IOS_LDFLAGS="-arch $IOS_ARCH -isysroot $IOS_SDK -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"

# On Apple Silicon, --host=aarch64-apple-darwin matches the build machine,
# so autotools won't cross-compile and tries to run iOS binaries (which hang).
# Force cross-compilation by making --build differ from --host.
IOS_HOST="aarch64-apple-darwin"
IOS_BUILD="x86_64-apple-darwin"

# ── Helpers ─────────────────────────────────────────────────────────
info()  { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

clean() {
    info "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    rm -rf "$VENDOR_DIR/boost"
    rm -rf "$VENDOR_DIR/flac"
    rm -rf "$VENDOR_DIR/opus"
    rm -rf "$VENDOR_DIR/ogg"
    # Don't remove snapcast (it's large, keep it cached)
    info "Done. Run without 'clean' to rebuild."
}

if [ "${1:-}" = "clean" ]; then
    clean
    exit 0
fi

mkdir -p "$VENDOR_DIR" "$BUILD_DIR"

# ── 1. Boost (header-only) ──────────────────────────────────────────
boost_headers() {
    local dest="$VENDOR_DIR/boost"
    if [ -d "$dest/boost" ]; then
        info "Boost headers already present, skipping."
        return
    fi

    info "Downloading Boost $BOOST_VERSION headers..."
    local url="https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2"
    local archive="$BUILD_DIR/boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2"

    curl -L -o "$archive" "$url"
    mkdir -p "$dest"

    info "Extracting Boost headers (this takes a moment)..."
    tar -xjf "$archive" -C "$BUILD_DIR"
    cp -R "$BUILD_DIR/boost_${BOOST_VERSION_UNDERSCORE}/boost" "$dest/boost"

    info "Boost headers installed."
}

# ── 2. libogg ────────────────────────────────────────────────────────
build_ogg() {
    local dest="$VENDOR_DIR/ogg"
    if [ -f "$dest/lib/libogg.a" ]; then
        info "libogg already built, skipping."
        return
    fi

    info "Building libogg $OGG_VERSION for iOS..."
    local url="https://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.xz"
    local archive="$BUILD_DIR/libogg-${OGG_VERSION}.tar.xz"
    local src="$BUILD_DIR/libogg-${OGG_VERSION}"

    [ -f "$archive" ] || curl -L -o "$archive" "$url"
    [ -d "$src" ] || tar -xJf "$archive" -C "$BUILD_DIR"

    cd "$src"
    make distclean 2>/dev/null || true
    ./configure \
        --host="$IOS_HOST" \
        --build="$IOS_BUILD" \
        --prefix="$dest" \
        --enable-static \
        --disable-shared \
        CC="$CC_IOS" \
        CFLAGS="$IOS_CFLAGS" \
        LDFLAGS="$IOS_LDFLAGS"

    make -j"$(sysctl -n hw.ncpu)" install
    cd "$ROOT_DIR"

    info "libogg built."
}

# ── 3. libFLAC ───────────────────────────────────────────────────────
build_flac() {
    local dest="$VENDOR_DIR/flac"
    if [ -f "$dest/lib/libFLAC.a" ]; then
        info "libFLAC already built, skipping."
        return
    fi

    info "Building libFLAC $FLAC_VERSION for iOS..."
    local url="https://downloads.xiph.org/releases/flac/flac-${FLAC_VERSION}.tar.xz"
    local archive="$BUILD_DIR/flac-${FLAC_VERSION}.tar.xz"
    local src="$BUILD_DIR/flac-${FLAC_VERSION}"

    [ -f "$archive" ] || curl -L -o "$archive" "$url"
    [ -d "$src" ] || tar -xJf "$archive" -C "$BUILD_DIR"

    cd "$src"
    make distclean 2>/dev/null || true
    ./configure \
        --host="$IOS_HOST" \
        --build="$IOS_BUILD" \
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

    info "libFLAC built."
}

# ── 4. libopus ───────────────────────────────────────────────────────
build_opus() {
    local dest="$VENDOR_DIR/opus"
    if [ -f "$dest/lib/libopus.a" ]; then
        info "libopus already built, skipping."
        return
    fi

    info "Building libopus $OPUS_VERSION for iOS..."
    local url="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"
    local archive="$BUILD_DIR/opus-${OPUS_VERSION}.tar.gz"
    local src="$BUILD_DIR/opus-${OPUS_VERSION}"

    [ -f "$archive" ] || curl -L -o "$archive" "$url"
    [ -d "$src" ] || tar -xzf "$archive" -C "$BUILD_DIR"

    cd "$src"
    make distclean 2>/dev/null || true
    ./configure \
        --host="$IOS_HOST" \
        --build="$IOS_BUILD" \
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

    info "libopus built."
}

# ── 5. Snapcast source ──────────────────────────────────────────────
apply_ios_patches() {
    local dest="$1"
    local patch_dir="$ROOT_DIR/patches"

    if [ -f "$patch_dir/ios-time-fix.patch" ]; then
        info "Applying iOS time fix patch..."
        cd "$dest"
        # Apply patch (ignore if already applied)
        patch -p1 -N < "$patch_dir/ios-time-fix.patch" || true
        cd "$ROOT_DIR"
    fi

    if [ -f "$patch_dir/ios-controller.patch" ]; then
        info "Applying iOS controller patch..."
        cd "$dest"
        patch -p1 -N < "$patch_dir/ios-controller.patch" || true
        cd "$ROOT_DIR"
    fi

    if [ -f "$patch_dir/ios-time-sync-wait.patch" ]; then
        info "Applying iOS time sync wait patch..."
        cd "$dest"
        patch -p1 -N < "$patch_dir/ios-time-sync-wait.patch" || true
        cd "$ROOT_DIR"
    fi

    if [ -f "$patch_dir/ios-time-provider-reset.patch" ]; then
        info "Applying iOS time provider reset patch..."
        cd "$dest"
        patch -p1 -N < "$patch_dir/ios-time-provider-reset.patch" || true
        cd "$ROOT_DIR"
    fi
}

clone_snapcast() {
    local dest="$VENDOR_DIR/snapcast"
    if [ -d "$dest/.git" ]; then
        info "Snapcast source present. Checking out $SNAPCAST_TAG..."
        cd "$dest"
        git fetch --tags
        git checkout "$SNAPCAST_TAG"
        cd "$ROOT_DIR"
        apply_ios_patches "$dest"
        return
    fi

    info "Cloning Snapcast $SNAPCAST_TAG..."
    git clone --branch "$SNAPCAST_TAG" --depth 1 "$SNAPCAST_REPO" "$dest"
    apply_ios_patches "$dest"

    info "Snapcast source ready."
}

# ── 6. Build snapclient core for iOS ────────────────────────────────
build_snapclient_core() {
    info "Building snapclient core library for iOS..."

    local build="$BUILD_DIR/snapclient_core"
    mkdir -p "$build"

    cmake -B "$build" -S "$ROOT_DIR/SnapClientCore" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT_DIR/SnapClientCore/cmake/ios.toolchain.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DSNAPCAST_DIR="$VENDOR_DIR/snapcast" \
        -DBOOST_ROOT="$VENDOR_DIR/boost" \
        -DFLAC_ROOT="$VENDOR_DIR/flac" \
        -DOPUS_ROOT="$VENDOR_DIR/opus" \
        -DOGG_ROOT="$VENDOR_DIR/ogg"

    cmake --build "$build" --parallel

    info "snapclient core built."
    info "Libraries at: $build/"
}

# ── Run ──────────────────────────────────────────────────────────────
info "Building dependencies for iOS ($IOS_ARCH, deployment target $IOS_DEPLOYMENT_TARGET)"
info "Vendor dir: $VENDOR_DIR"
info ""

boost_headers
build_ogg
build_flac
build_opus
clone_snapcast
build_snapclient_core

info ""
info "All dependencies built successfully."
info ""
info "Next steps:"
info "  1. Open SnapClient.xcodeproj in Xcode"
info "  2. Set header search paths to: $VENDOR_DIR/*/include"
info "  3. Set library search paths to: $BUILD_DIR/snapclient_core/Release-iphoneos"
info "  4. Link against: libsnapclient_core.a libsnapclient_bridge.a"
info "  5. Build and run on device"
