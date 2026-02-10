#!/bin/bash
#
# Run C++ Bridge Stability Tests
#
# This script builds and runs the bridge stress tests to verify
# thread-safety and deadlock-freedom of the snapclient bridge.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/tests"
TEST_SRC="$PROJECT_DIR/Tests/StabilityTests/BridgeStabilityTests.cpp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Building Bridge Stability Tests                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Ensure dependencies are built
if [ ! -f "$PROJECT_DIR/build/deps/snapclient_core/libsnapclient_bridge.a" ]; then
    echo -e "${YELLOW}⚠️  Bridge library not found. Building dependencies...${NC}"
    "$SCRIPT_DIR/build-deps.sh"
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Compiler flags
CXX="${CXX:-clang++}"
CXXFLAGS="-std=c++17 -O2 -g"
INCLUDES=(
    "-I$PROJECT_DIR/SnapClientCore/bridge"
    "-I$PROJECT_DIR/SnapClientCore/ios_player"
    "-I$PROJECT_DIR/SnapClientCore/ios_shim"
    "-I$PROJECT_DIR/SnapClientCore/vendor/snapcast"
    "-I$PROJECT_DIR/SnapClientCore/vendor/snapcast/client"
    "-I$PROJECT_DIR/SnapClientCore/vendor/snapcast/common"
    "-I$PROJECT_DIR/SnapClientCore/vendor/boost"
)
LIBS=(
    "-L$PROJECT_DIR/build/deps/snapclient_core"
    "-lsnapclient_bridge"
    "-lsnapclient_core"
    "-L$PROJECT_DIR/SnapClientCore/vendor/flac/lib"
    "-L$PROJECT_DIR/SnapClientCore/vendor/opus/lib"
    "-L$PROJECT_DIR/SnapClientCore/vendor/ogg/lib"
    "-lFLAC"
    "-lopus"
    "-logg"
    "-framework AudioToolbox"
    "-framework CoreFoundation"
    "-framework Foundation"
    "-lpthread"
)

echo "Compiling $TEST_SRC..."
echo ""

# Build the test binary
$CXX $CXXFLAGS \
    "${INCLUDES[@]}" \
    "$TEST_SRC" \
    "${LIBS[@]}" \
    -o "$BUILD_DIR/bridge_stability_tests"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build successful${NC}"
echo ""

# Run the tests
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Running Bridge Stability Tests                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

"$BUILD_DIR/bridge_stability_tests"

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✅ All bridge tests passed${NC}"
else
    echo -e "${RED}❌ Some tests failed (exit code: $exit_code)${NC}"
fi

exit $exit_code
