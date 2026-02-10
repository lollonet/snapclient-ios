#!/bin/bash
#
# Run All Stability Tests
#
# This script runs both Swift and C++ stability tests to verify
# the hardened SnapForge engine under stress conditions.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         SnapForge Stability Test Suite                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Parse arguments
RUN_SWIFT=true
RUN_CPP=true
DEVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --swift-only)
            RUN_CPP=false
            shift
            ;;
        --cpp-only)
            RUN_SWIFT=false
            shift
            ;;
        --device)
            DEVICE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --swift-only    Run only Swift tests"
            echo "  --cpp-only      Run only C++ tests"
            echo "  --device ID     iOS device/simulator ID for Swift tests"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

SWIFT_RESULT=0
CPP_RESULT=0

# Run C++ Bridge Tests
if [ "$RUN_CPP" = true ]; then
    echo -e "${BLUE}═══ C++ Bridge Stability Tests ═══${NC}"
    echo ""

    if "$SCRIPT_DIR/run-bridge-tests.sh"; then
        echo -e "${GREEN}✅ C++ tests passed${NC}"
    else
        CPP_RESULT=1
        echo -e "${RED}❌ C++ tests failed${NC}"
    fi
    echo ""
fi

# Run Swift Tests
if [ "$RUN_SWIFT" = true ]; then
    echo -e "${BLUE}═══ Swift Stability Tests ═══${NC}"
    echo ""

    # Determine destination
    if [ -n "$DEVICE" ]; then
        DESTINATION="id=$DEVICE"
    else
        # Use simulator by default
        DESTINATION="platform=iOS Simulator,name=iPhone 15 Pro,OS=latest"
    fi

    echo "Destination: $DESTINATION"
    echo ""

    # First regenerate project with xcodegen to include test target
    if command -v xcodegen &> /dev/null; then
        echo "Regenerating Xcode project..."
        cd "$PROJECT_DIR"
        xcodegen generate --quiet
    fi

    # Run Swift tests
    cd "$PROJECT_DIR"
    if xcodebuild test \
        -project SnapClient.xcodeproj \
        -scheme SnapClientTests \
        -destination "$DESTINATION" \
        -only-testing:SnapClientTests/SnapClientStabilityTests \
        2>&1 | xcpretty --color; then
        echo -e "${GREEN}✅ Swift tests passed${NC}"
    else
        SWIFT_RESULT=1
        echo -e "${RED}❌ Swift tests failed${NC}"
    fi
    echo ""
fi

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Test Summary                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$RUN_CPP" = true ]; then
    if [ $CPP_RESULT -eq 0 ]; then
        echo -e "  C++ Bridge Tests:  ${GREEN}PASSED${NC}"
    else
        echo -e "  C++ Bridge Tests:  ${RED}FAILED${NC}"
    fi
fi

if [ "$RUN_SWIFT" = true ]; then
    if [ $SWIFT_RESULT -eq 0 ]; then
        echo -e "  Swift Tests:       ${GREEN}PASSED${NC}"
    else
        echo -e "  Swift Tests:       ${RED}FAILED${NC}"
    fi
fi

echo ""

# Exit with failure if any test failed
if [ $SWIFT_RESULT -ne 0 ] || [ $CPP_RESULT -ne 0 ]; then
    echo -e "${RED}⚠️  Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}🎉 All stability tests passed!${NC}"
    echo ""
    echo "The SnapForge engine has been verified to be:"
    echo "  ✓ Deadlock-free under concurrent access"
    echo "  ✓ Memory-safe during rapid lifecycle changes"
    echo "  ✓ Stable under callback contention"
    echo "  ✓ Leak-free with proper zombie cleanup"
    exit 0
fi
