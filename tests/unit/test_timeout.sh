#!/usr/bin/env bash

# ============================================
# Unit Tests: run_with_timeout Execution
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/parallel.sh
source "$ROOT_DIR/lib/parallel.sh"

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

echo "Running Unit Tests: run_with_timeout Supervisor..."

# 1. Successful command returns 0
# shellcheck disable=SC2317,SC2329
cmd_success() {
    return 0
}
status_ok=0
run_with_timeout 2 cmd_success || status_ok=$?
assert_equals "run_with_timeout: successful command returns 0" "0" "$status_ok"

# 2. Non-zero command preserves specific exit code
# shellcheck disable=SC2317,SC2329
cmd_fail_37() {
    return 37
}
status_37=0
run_with_timeout 2 cmd_fail_37 || status_37=$?
assert_equals "run_with_timeout: preserves custom non-zero exit code (37)" "37" "$status_37"

# shellcheck disable=SC2317,SC2329
cmd_fail_1() {
    return 1
}
status_1=0
run_with_timeout 2 cmd_fail_1 || status_1=$?
assert_equals "run_with_timeout: preserves exit code 1" "1" "$status_1"

# 3. Timeout returns code 124
# shellcheck disable=SC2317,SC2329
cmd_hang() {
    sleep 5
}
status_to=0
run_with_timeout 1 cmd_hang || status_to=$?
assert_equals "run_with_timeout: timed out command returns exit code 124" "124" "$status_to"

# 4. SIGKILL fallback: process ignoring SIGTERM is killed and returns 124
# shellcheck disable=SC2317,SC2329
cmd_ignore_term() {
    trap '' TERM
    sleep 5
}
status_kill=0
run_with_timeout 1 cmd_ignore_term || status_kill=$?
assert_equals "run_with_timeout: SIGKILL fallback terminates TERM-ignoring command with 124" "124" "$status_kill"

# 5. Watcher cleanup: ACTIVE_CHILD_PIDS is cleared
assert_equals "run_with_timeout: ACTIVE_CHILD_PIDS array is completely empty after completion" \
    "0" "${#ACTIVE_CHILD_PIDS[@]}"

# 6. Zero or negative timeout bypasses watcher
# shellcheck disable=SC2317,SC2329
cmd_instant() {
    return 0
}
status_noto=0
run_with_timeout 0 cmd_instant || status_noto=$?
assert_equals "run_with_timeout: timeout 0 runs command directly returning 0" "0" "$status_noto"

echo "Timeout supervisor unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
