#!/usr/bin/env bash

# ============================================
# Integration Test: Multi-Target Scope Isolation
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

echo "Running Integration Test: Multi-Target Scope & Workspace Isolation..."

export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_multi_iso.XXXXXX" 2>/dev/null || mktemp -d)"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

TARGET_A="domain-alpha.com"
TARGET_B="domain-beta.org"

# Run mock framework against two targets with subdomains,dns stages
status=0
bash "$ROOT_DIR/recon.sh" -d "${TARGET_A},${TARGET_B}" -o "$OUTPUT_DIR" --stages subdomains,dns >/dev/null 2>&1 || status=$?

assert_equals "recon.sh multi-target: completes with exit code 0" "0" "$status"

WS_A="$OUTPUT_DIR/$TARGET_A"
WS_B="$OUTPUT_DIR/$TARGET_B"

# 1. Workspace isolation
assert_true "workspace A: directory created" \
    test -d "$WS_A"
assert_true "workspace B: directory created" \
    test -d "$WS_B"

# 2. Manifest isolation
assert_true "manifest A: exists" \
    test -f "$WS_A/manifest.json"
assert_true "manifest B: exists" \
    test -f "$WS_B/manifest.json"
assert_true "manifest A: target is domain-alpha.com" \
    grep -q "\"target\": \"${TARGET_A}\"" "$WS_A/manifest.json"
assert_true "manifest B: target is domain-beta.org" \
    grep -q "\"target\": \"${TARGET_B}\"" "$WS_B/manifest.json"
assert_true "manifest A: status is success" \
    grep -q '"status": "success"' "$WS_A/manifest.json"
assert_true "manifest B: status is success" \
    grep -q '"status": "success"' "$WS_B/manifest.json"

# 3. Log isolation
assert_true "logs A: exists and records target A" \
    grep -q "Target : ${TARGET_A}" "$WS_A/logs/recon.log"
assert_true "logs B: exists and records target B" \
    grep -q "Target : ${TARGET_B}" "$WS_B/logs/recon.log"
assert_false "logs A: does NOT contain Target : domain-beta.org" \
    grep -q "Target : ${TARGET_B}" "$WS_A/logs/recon.log"
assert_false "logs B: does NOT contain Target : domain-alpha.com" \
    grep -q "Target : ${TARGET_A}" "$WS_B/logs/recon.log"

# 4. Artifact & Scope isolation
assert_true "artifacts A: subdomains/all.txt contains target A subdomain" \
    grep -q "api.${TARGET_A}" "$WS_A/subdomains/all.txt"
assert_false "artifacts A: subdomains/all.txt does NOT contain target B subdomain" \
    grep -q "${TARGET_B}" "$WS_A/subdomains/all.txt"

assert_true "artifacts B: subdomains/all.txt contains target B subdomain" \
    grep -q "api.${TARGET_B}" "$WS_B/subdomains/all.txt"
assert_false "artifacts B: subdomains/all.txt does NOT contain target A subdomain" \
    grep -q "${TARGET_A}" "$WS_B/subdomains/all.txt"

# 5. Multi-target aggregated summary report
assert_true "multi-target summary: report created" \
    test -f "$OUTPUT_DIR/reports/multi_target_summary.md"
assert_true "multi-target summary: contains target A" \
    grep -q "${TARGET_A}" "$OUTPUT_DIR/reports/multi_target_summary.md"
assert_true "multi-target summary: contains target B" \
    grep -q "${TARGET_B}" "$OUTPUT_DIR/reports/multi_target_summary.md"

# 6. Failure isolation
# Test running two targets where the first fails a stage dependency.
FAIL_OUT="$(mktemp -d "${TMPDIR:-/tmp}/recon_multi_fail.XXXXXX" 2>/dev/null || mktemp -d)"
fail_status=0
# Running stage dns without subdomains causes dependency check to fail for the pipeline
bash "$ROOT_DIR/recon.sh" -d "target-fail.com,${TARGET_B}" -o "$FAIL_OUT" --stages dns >/dev/null 2>&1 || fail_status=$?

assert_true "failure isolation: overall run reports non-zero exit status" \
    test "$fail_status" -ne 0
assert_true "failure isolation: target 1 manifest records failed" \
    grep -q '"status": "failed"' "$FAIL_OUT/target-fail.com/manifest.json"
assert_true "failure isolation: target 2 workspace created" \
    test -d "$FAIL_OUT/$TARGET_B"

# Cleanup
rm -rf "$OUTPUT_DIR" "$FAIL_OUT" 2>/dev/null || true

echo "Multi-target scope & isolation integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
