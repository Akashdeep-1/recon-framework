#!/usr/bin/env bash

# ============================================
# Integration Test: Retry and Timeout Behavior
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

assert_true() {
    local desc="$1"
    shift
    if "$@"; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc"
        FAILED=$(( FAILED + 1 ))
    fi
}

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

echo "Running Integration Test: Timeout & Retry Behavior..."

TARGET="retry-test.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_retry.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# 1. Test failure without retries (--retries 0)
export MOCK_FAIL_DNSX_FILE="${OUTPUT_DIR}/dnsx_attempts_0.txt"
export MOCK_FAIL_DNSX_COUNT=1

status_no_retry=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --stages subdomains,dns --retries 0 >/dev/null 2>&1 || status_no_retry=$?

assert_equals "recon.sh --retries 0: transient failure aborts pipeline" "1" "$status_no_retry"
unset MOCK_FAIL_DNSX_FILE MOCK_FAIL_DNSX_COUNT

# 2. Test success with retries (--retries 1)
TARGET_RETRY="retry-ok.com"
export MOCK_FAIL_DNSX_FILE="${OUTPUT_DIR}/dnsx_attempts_1.txt"
export MOCK_FAIL_DNSX_COUNT=1

status_with_retry=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET_RETRY" --stages subdomains,dns --retries 1 >/dev/null 2>&1 || status_with_retry=$?
WORKSPACE_RETRY="$OUTPUT_DIR/$TARGET_RETRY"
MANIFEST_RETRY="$WORKSPACE_RETRY/manifest.json"

assert_equals "recon.sh --retries 1: recovers from transient failure and exits 0" "0" "$status_with_retry"
assert_true "recon.sh --retries 1: logs retry attempt in log file" \
    grep -q "Retrying DNS Resolution (attempt 2/2)" "$WORKSPACE_RETRY/logs/recon.log"
assert_true "recon.sh --retries 1: dns stage recorded as success in manifest" \
    grep -q "\"dns\": { \"status\": \"success\"" "$MANIFEST_RETRY"
assert_true "recon.sh --retries 1: dns output created on retry" \
    test -s "$WORKSPACE_RETRY/dns/resolved.txt"

unset MOCK_FAIL_DNSX_FILE MOCK_FAIL_DNSX_COUNT

# 3. Test timeout behavior: hanging stage terminated when exceeding --timeout
TARGET_TIMEOUT="timeout-test.com"
mkdir -p "$OUTPUT_DIR/$TARGET_TIMEOUT/subdomains"
echo "target.timeout-test.com" > "$OUTPUT_DIR/$TARGET_TIMEOUT/subdomains/all.txt"
export MOCK_SLEEP_DNSX=5

status_timeout=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET_TIMEOUT" --stages dns --timeout 1 --retries 0 >/dev/null 2>&1 || status_timeout=$?
WORKSPACE_TIMEOUT="$OUTPUT_DIR/$TARGET_TIMEOUT"
MANIFEST_TIMEOUT="$WORKSPACE_TIMEOUT/manifest.json"

unset MOCK_SLEEP_DNSX

assert_true "recon.sh --timeout 1: aborts timed out stage with non-zero exit code" \
    test "$status_timeout" -ne 0
assert_true "recon.sh --timeout 1: manifest records dns stage as failed" \
    grep -q "\"dns\": { \"status\": \"failed\"" "$MANIFEST_TIMEOUT"
assert_true "recon.sh --timeout 1: overall manifest status is failed" \
    grep -q "\"status\": \"failed\"" "$MANIFEST_TIMEOUT"

echo "Timeout & retry integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
