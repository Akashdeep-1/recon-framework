#!/usr/bin/env bash

# ============================================
# Integration Test: Pipeline Failure Propagation
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

echo "Running Integration Test: Failure Handling & Error Propagation..."

TARGET="failure-test.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_fail.XXXXXX" 2>/dev/null || mktemp -d)"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# 1. Test DNSX failure halts pipeline with non-zero status
export MOCK_FAIL_DNSX=1
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" >/dev/null 2>&1 || status=$?
unset MOCK_FAIL_DNSX

assert_equals "recon.sh: DNSX failure causes pipeline to abort with non-zero exit code" \
    "1" "$status"

# 2. Test Subfinder failure in parallel passive stage halts pipeline
export MOCK_FAIL_SUBFINDER=1
status_sub=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" >/dev/null 2>&1 || status_sub=$?
unset MOCK_FAIL_SUBFINDER

assert_equals "recon.sh: Subfinder failure in parallel execution aborts pipeline" \
    "1" "$status_sub"

# Cleanup
rm -rf "$OUTPUT_DIR"

echo "Failure propagation integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
