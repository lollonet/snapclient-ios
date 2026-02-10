#!/usr/bin/env bash
#
# Run Bridge Stability Tests
#
# NOTE: The bridge library is built for iOS device (arm64), not simulator.
# These tests must run on a physical iOS device, or you can rebuild
# the bridge for simulator using: ./scripts/build-deps.sh --simulator
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Bridge Stability Tests                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check library architecture
if [ -f "$PROJECT_DIR/build/deps/snapclient_core/libsnapclient_bridge.a" ]; then
    ARCH_INFO=$(lipo -info "$PROJECT_DIR/build/deps/snapclient_core/libsnapclient_bridge.a" 2>/dev/null || echo "unknown")
    echo "Bridge library: $ARCH_INFO"
else
    echo -e "${RED}❌ Bridge library not found. Run: ./scripts/build-deps.sh${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}⚠️  The bridge is built for iOS device, not simulator.${NC}"
echo ""
echo "To run these tests, you have two options:"
echo ""
echo "  1. Run on a physical iOS device:"
echo "     - Connect your device"
echo "     - Open SnapClient.xcodeproj in Xcode"
echo "     - Select your device as the destination"
echo "     - Run: Product → Test (⌘U)"
echo ""
echo "  2. Rebuild the bridge for simulator (if supported):"
echo "     - Run: ./scripts/build-deps.sh --simulator"
echo "     - Then run this script again"
echo ""
echo "  3. Run the C++ tests standalone (pattern verification only):"
echo "     - See: Tests/StabilityTests/BridgeStabilityTests.cpp"
echo "     - This file documents the test patterns"
echo ""

# Check if device is connected
DEVICES=$(xcrun xctrace list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v Simulator || true)

if [ -n "$DEVICES" ]; then
    echo -e "${GREEN}Detected iOS devices:${NC}"
    echo "$DEVICES"
    echo ""

    read -p "Run tests on connected device? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        DEVICE_ID=$(echo "$DEVICES" | head -1 | grep -oE '\([^)]+\)$' | tr -d '()')
        echo ""
        echo "Running tests on device: $DEVICE_ID"
        echo ""

        cd "$PROJECT_DIR"
        xcodebuild test \
            -project SnapClient.xcodeproj \
            -scheme SnapClient \
            -destination "id=$DEVICE_ID" \
            -only-testing:SnapClientTests/SnapClientStabilityTests \
            2>&1 | grep -E "(Test Case|passed|failed|Executed|🧪|📊|✅|❌)" || true

        echo ""
        echo -e "${GREEN}Tests completed. Check output above for results.${NC}"
    fi
else
    echo -e "${YELLOW}No iOS devices detected.${NC}"
    echo ""
    echo "Connect a device and run this script again, or use Xcode directly."
fi
