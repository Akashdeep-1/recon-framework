#!/usr/bin/env bash

# ============================================
# Integration Test: Pipeline Crash Recovery & Resumption Integrity
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

echo "Running Integration Test: Pipeline Crash Recovery & Resumption Integrity..."

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_crash_rec.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TARGET="crash-recovery-test.com"
export OUTPUT_DIR="$TMP_DIR"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# -------------------------------------------------------------
# 1. Run stages subdomains,dns to establish initial partial run
# -------------------------------------------------------------
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --stages subdomains,dns >/dev/null 2>&1 || status=$?
assert_equals "initial partial run: completes successfully" "0" "$status"

WORKSPACE="$OUTPUT_DIR/$TARGET"
DNS_FILE="$WORKSPACE/dns/resolved.txt"

# Verify subdomains & dns marked success in manifest
assert_equals "manifest: subdomains is success" "success" "$(get_manifest_stage_status "$WORKSPACE" "subdomains")"
assert_equals "manifest: dns is success" "success" "$(get_manifest_stage_status "$WORKSPACE" "dns")"
assert_equals "manifest: ports is skipped" "skipped" "$(get_manifest_stage_status "$WORKSPACE" "ports")"

# -------------------------------------------------------------
# 2. Simulate crash during a stage: mark 'dns' as 'running' with partial artifact
# Resuming with -r must NOT skip 'dns' because manifest status was 'running' (interrupted)
# -------------------------------------------------------------
update_stage_manifest "$WORKSPACE" "dns" "running" 0 0 1
finalize_manifest "$WORKSPACE" "failed"

assert_equals "simulated crash: dns manifest status is running" "running" "$(get_manifest_stage_status "$WORKSPACE" "dns")"
assert_equals "simulated crash: overall status is failed" "failed" "$(get_manifest_overall_status "$WORKSPACE")"

# Append a distinctive marker to dns output
echo "pre-crash-marker.crash-recovery-test.com [10.0.0.99]" > "$DNS_FILE"

# Resume with -r --stages dns
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --stages dns -r >/dev/null 2>&1 || status=$?
assert_equals "resume interrupted stage: executes successfully" "0" "$status"

# The interrupted stage must have been re-executed: mock dnsx overwrites resolved.txt with fresh data
assert_false "resume interrupted stage: re-runs stage rather than skipping incomplete state" \
    grep -q "pre-crash-marker" "$DNS_FILE"

assert_equals "resume interrupted stage: manifest updated to success" "success" \
    "$(get_manifest_stage_status "$WORKSPACE" "dns")"

# -------------------------------------------------------------
# 3. Simulate corrupt/empty artifact: 0-byte subdomains/all.txt
# Resuming with -r must NOT resume because artifact is 0 bytes
# -------------------------------------------------------------
: > "$WORKSPACE/subdomains/all.txt"
update_stage_manifest "$WORKSPACE" "subdomains" "success" 0 0 1

# Resume with -r --stages subdomains
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --stages subdomains -r >/dev/null 2>&1 || status=$?
assert_equals "resume corrupted artifact: executes successfully" "0" "$status"

# Verify subdomains was regenerated (non-empty)
assert_true "resume corrupted artifact: re-generated non-empty output" \
    test -s "$WORKSPACE/subdomains/all.txt"

echo "Crash recovery integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
