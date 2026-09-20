#!/usr/bin/env bash

# ============================================
# Integration Test: Process-Tree Timeout Cleanup
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

assert_false() {
    local desc="$1"
    shift
    if ! "$@"; then
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

echo "Running Integration Test: Process-Tree Timeout Cleanup..."

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_tree_test.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PARENT_PID_FILE="$TMP_DIR/parent.pid"
CHILD_PID_FILE="$TMP_DIR/child.pid"

# Mock stage that spawns a long-lived child process and waits on it
# shellcheck disable=SC2329
mock_stage_with_child() {
    printf '%s' "$BASHPID" > "$PARENT_PID_FILE"
    sleep 60 &
    local cpid=$!
    printf '%s' "$cpid" > "$CHILD_PID_FILE"
    wait "$cpid"
}

# 1. Run through run_with_timeout with 1 second timeout
status_code=0
run_with_timeout 1 mock_stage_with_child || status_code=$?

PARENT_PID="$(cat "$PARENT_PID_FILE" 2>/dev/null || echo "")"
CHILD_PID="$(cat "$CHILD_PID_FILE" 2>/dev/null || echo "")"
WATCHER_PID="$LAST_TIMEOUT_WATCHER_PID"

# 2. Verify wrapper returns exit code 124
assert_equals "run_with_timeout: returns exit code 124 on timeout" \
    "124" "$status_code"

# 3. Verify parent process was launched and subsequently terminated
assert_true "parent process: PID recorded" \
    test -n "$PARENT_PID"

assert_false "parent process: terminated and no longer running" \
    kill -0 "$PARENT_PID" 2>/dev/null

# 4. Verify spawned child process was launched and subsequently terminated (no orphan)
assert_true "child process: PID recorded" \
    test -n "$CHILD_PID"

assert_false "child process: terminated and not orphaned" \
    kill -0 "$CHILD_PID" 2>/dev/null

# 5. Verify ACTIVE_CHILD_PIDS is completely empty
assert_equals "parallel supervisor: ACTIVE_CHILD_PIDS is completely empty" \
    "0" "${#ACTIVE_CHILD_PIDS[@]}"

# 6. Verify timeout watcher is terminated and no longer running
assert_true "watcher process: PID recorded" \
    test -n "$WATCHER_PID"

assert_false "watcher process: terminated and no longer running" \
    kill -0 "$WATCHER_PID" 2>/dev/null

echo "Process-tree timeout cleanup integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
