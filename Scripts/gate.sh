#!/usr/bin/env bash
# Gnomon phase-completion gate
# Runs: swiftlint (strict) + swiftformat --lint + xcodebuild build + test
# Exit code 0 on pass, non-zero on any failure.
#
# Usage: ./Scripts/gate.sh [--skip-tests]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SKIP_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

run_check() {
    local name="$1"
    shift
    echo ""
    echo -e "${YELLOW}▶ $name${NC}"
    if "$@"; then
        echo -e "${GREEN}✓ $name passed${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}✗ $name failed${NC}"
        FAIL=$((FAIL + 1))
    fi
}

# Ensure xcodegen has generated the project first
if [ ! -d "$PROJECT_DIR/Gnomon.xcodeproj" ]; then
    echo -e "${YELLOW}project.yml found but Gnomon.xcodeproj missing. Running xcodegen...${NC}"
    xcodegen generate
fi

# 1. SwiftLint (strict: warnings = errors)
run_check "SwiftLint" swiftlint --strict --quiet

# 2. SwiftFormat lint (check mode, don't modify)
run_check "SwiftFormat (lint mode)" swiftformat --lint .

# 3. Build
run_check "xcodebuild build" bash -c "set -o pipefail; xcodebuild -project Gnomon.xcodeproj -scheme Gnomon -destination 'platform=macOS' -configuration Debug build 2>&1 | xcbeautify --quiet"

# 4. Tests (unless skipped)
if [ "$SKIP_TESTS" -eq 0 ]; then
    run_check "xcodebuild test" bash -c "set -o pipefail; xcodebuild -project Gnomon.xcodeproj -scheme Gnomon -destination 'platform=macOS' -configuration Debug test 2>&1 | xcbeautify --quiet"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "Gate summary: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
