#!/usr/bin/env bash

# ============================================
# Unit Tests: Pipeline State & Manifest
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

echo "Running Unit Tests: Manifest & Pipeline State..."

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_manifest_test.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TARGET="testmanifest.com"
MANIFEST_FILE="${TMP_DIR}/manifest.json"

# 1. Test init_manifest
init_manifest "$TMP_DIR" "$TARGET" 25 100 120 2 0 "subdomains,dns" "ports"
assert_true "init_manifest: creates manifest.json file" \
    test -f "$MANIFEST_FILE"

assert_true "init_manifest: output is valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

assert_true "init_manifest: records target domain" \
    grep -q "\"target\": \"$TARGET\"" "$MANIFEST_FILE"

assert_true "init_manifest: initial status is running" \
    grep -q "\"status\": \"running\"" "$MANIFEST_FILE"

assert_true "init_manifest: records config threads" \
    grep -q "\"threads\": 25" "$MANIFEST_FILE"

assert_true "init_manifest: records config rate_limit" \
    grep -q "\"rate_limit\": 100" "$MANIFEST_FILE"

assert_true "init_manifest: records config timeout" \
    grep -q "\"timeout\": 120" "$MANIFEST_FILE"

assert_true "init_manifest: records config retries" \
    grep -q "\"retries\": 2" "$MANIFEST_FILE"

assert_true "init_manifest: records selected stages" \
    grep -q "\"stages_selected\": \"subdomains,dns\"" "$MANIFEST_FILE"

assert_true "init_manifest: records skipped stages" \
    grep -q "\"stages_skipped\": \"ports\"" "$MANIFEST_FILE"

for stage in subdomains dns ports live crawling vuln reports; do
    assert_true "init_manifest: stage $stage is pending" \
        grep -q "\"$stage\": { \"status\": \"pending\"" "$MANIFEST_FILE"
done

# 2. Test update_stage_manifest: running
update_stage_manifest "$TMP_DIR" "subdomains" "running" 0 0
assert_true "update_stage_manifest: transitions to running" \
    grep -q "\"subdomains\": { \"status\": \"running\"" "$MANIFEST_FILE"
assert_true "update_stage_manifest running: remains valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

# 3. Test update_stage_manifest: success with duration and count
update_stage_manifest "$TMP_DIR" "subdomains" "success" 15 42 1
assert_true "update_stage_manifest: transitions to success with metrics" \
    grep -q "\"subdomains\": { \"status\": \"success\", \"duration_seconds\": 15, \"output_count\": 42, \"attempts\": 1 }" "$MANIFEST_FILE"
assert_true "update_stage_manifest success: remains valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

# 4. Test update_stage_manifest: skipped
update_stage_manifest "$TMP_DIR" "ports" "skipped" 0 0 0
assert_true "update_stage_manifest: transitions to skipped" \
    grep -q "\"ports\": { \"status\": \"skipped\", \"duration_seconds\": 0, \"output_count\": 0, \"attempts\": 0 }" "$MANIFEST_FILE"
assert_true "update_stage_manifest skipped: remains valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

# 5. Test update_stage_manifest: resumed
update_stage_manifest "$TMP_DIR" "dns" "resumed" 0 10 0
assert_true "update_stage_manifest: transitions to resumed" \
    grep -q "\"dns\": { \"status\": \"resumed\", \"duration_seconds\": 0, \"output_count\": 10, \"attempts\": 0 }" "$MANIFEST_FILE"
assert_true "update_stage_manifest resumed: remains valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

# 6. Test update_stage_manifest: failed
update_stage_manifest "$TMP_DIR" "live" "failed" 5 0 2
assert_true "update_stage_manifest: transitions to failed" \
    grep -q "\"live\": { \"status\": \"failed\", \"duration_seconds\": 5, \"output_count\": 0, \"attempts\": 2 }" "$MANIFEST_FILE"
assert_true "update_stage_manifest failed: remains valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

# 7. Test finalize_manifest: success
finalize_manifest "$TMP_DIR" "success"
assert_true "finalize_manifest: overall status is updated" \
    grep -q "\"status\": \"success\"" "$MANIFEST_FILE"

assert_true "finalize_manifest: end_time is populated" \
    grep -E -q "\"end_time\": \"[0-9]{4}-[0-9]{2}-[0-9]{2}" "$MANIFEST_FILE"

assert_true "finalize_manifest: final document is valid JSON" \
    python -m json.tool "$MANIFEST_FILE" >/dev/null

echo "Manifest unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
