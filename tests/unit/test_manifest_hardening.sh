#!/usr/bin/env bash

# ============================================
# Unit Tests: Manifest JSON Hardening & Integrity
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/manifest.sh
source "$ROOT_DIR/lib/manifest.sh"

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

echo "Running Unit Tests: Manifest JSON Hardening & Integrity..."

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_manifest_harden.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MANIFEST_FILE="${TMP_DIR}/manifest.json"

# 1. Special Characters and Quotes in Target & Stages
# shellcheck disable=SC2016
TARGET_SPECIAL='target"with\quotes and $pecial!chars.com'
init_manifest "$TMP_DIR" "$TARGET_SPECIAL" 10 50 60 1 0 "subdomains,dns" "ports"
assert_true "init_manifest with special characters: valid JSON" \
    validate_json_file "$MANIFEST_FILE"

# 2. Get Stage Status & Overall Status
status_init="$(get_manifest_overall_status "$TMP_DIR")"
assert_equals "get_manifest_overall_status: initially running" "running" "$status_init"

status_sub="$(get_manifest_stage_status "$TMP_DIR" "subdomains")"
assert_equals "get_manifest_stage_status: initially pending" "pending" "$status_sub"

# 3. Rapid/Sequential Stage Updates
update_stage_manifest "$TMP_DIR" "subdomains" "running" 0 0 1
assert_equals "rapid updates: subdomains -> running" "running" "$(get_manifest_stage_status "$TMP_DIR" "subdomains")"

update_stage_manifest "$TMP_DIR" "subdomains" "success" 12 150 1
assert_equals "rapid updates: subdomains -> success" "success" "$(get_manifest_stage_status "$TMP_DIR" "subdomains")"
assert_true "rapid updates: manifest remains valid JSON" \
    validate_json_file "$MANIFEST_FILE"

update_stage_manifest "$TMP_DIR" "dns" "running" 0 0 1
update_stage_manifest "$TMP_DIR" "dns" "failed" 4 0 2
assert_equals "rapid updates: dns -> failed" "failed" "$(get_manifest_stage_status "$TMP_DIR" "dns")"
assert_true "dns failed: manifest remains valid JSON" \
    validate_json_file "$MANIFEST_FILE"

# 4. Atomic Rollback: Manifest is not corrupted when candidate is invalid JSON
ORIGINAL_CONTENT="$(cat "$MANIFEST_FILE")"
INVALID_CANDIDATE="$TMP_DIR/bad.json"
echo '{"corrupted": true, broken syntax' > "$INVALID_CANDIDATE"

# atomic_swap_manifest must reject invalid candidate
assert_false "atomic_swap_manifest: rejects malformed JSON" \
    atomic_swap_manifest "$INVALID_CANDIDATE" "$MANIFEST_FILE"

CURRENT_CONTENT="$(cat "$MANIFEST_FILE")"
assert_equals "atomic_swap_manifest: original manifest preserved verbatim on failure" \
    "$ORIGINAL_CONTENT" "$CURRENT_CONTENT"

# 5. finalize_manifest idempotency
finalize_manifest "$TMP_DIR" "failed"
assert_equals "finalize_manifest: sets status to failed" "failed" "$(get_manifest_overall_status "$TMP_DIR")"
assert_true "finalize_manifest: valid JSON" \
    validate_json_file "$MANIFEST_FILE"

# Finalize again with different status (e.g., aborted in cleanup after completing)
finalize_manifest "$TMP_DIR" "aborted"
assert_equals "finalize_manifest: can update status again cleanly" "aborted" "$(get_manifest_overall_status "$TMP_DIR")"
assert_true "finalize_manifest second call: valid JSON" \
    validate_json_file "$MANIFEST_FILE"

# 6. Status of non-existent stage returns unknown
assert_equals "get_manifest_stage_status: non-existent stage returns unknown" "unknown" "$(get_manifest_stage_status "$TMP_DIR" "nonexistent_stage")"

echo "Manifest hardening unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
