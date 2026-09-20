#!/usr/bin/env bash

# ============================================
# Unit Tests: Dependency Checker & Installer
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"

PASSED=0
FAILED=0

assert_equals() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc (Expected: '$expected', Got: '$actual')"
        FAILED=$(( FAILED + 1 ))
    fi
}

echo "Running Unit Tests: Dependency Manager..."

# 1. Test missing dependencies returns non-zero exit code
status_missing=0
# Strip PATH of mock_bin and tools
PATH="/usr/bin:/bin" bash "$ROOT_DIR/install.sh" --check >/dev/null 2>&1 || status_missing=$?
assert_equals "install.sh --check: exits with status 1 when required tools are missing" \
    "1" "$status_missing"

# 2. Test installed dependencies returns zero exit code
MOCK_BIN="$ROOT_DIR/tests/mock_bin"
status_present=0
PATH="$MOCK_BIN:$PATH" bash "$ROOT_DIR/install.sh" --check >/dev/null 2>&1 || status_present=$?
assert_equals "install.sh --check: exits with status 0 when all required tools are present" \
    "0" "$status_present"

# 3. Test instructions mode returns 0
status_inst=0
bash "$ROOT_DIR/install.sh" --install-instructions >/dev/null 2>&1 || status_inst=$?
assert_equals "install.sh --install-instructions: returns exit status 0" \
    "0" "$status_inst"

echo "Dependency unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
