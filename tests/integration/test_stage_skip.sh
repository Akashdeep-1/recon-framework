#!/usr/bin/env bash

# ============================================
# Integration Test: Stage Exclusion (--skip)
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

echo "Running Integration Test: Stage Exclusion (--skip)..."

TARGET="skip-test.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_skip.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# Run pipeline skipping nuclei and ports
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --skip nuclei,ports >/dev/null 2>&1 || status=$?
WORKSPACE="$OUTPUT_DIR/$TARGET"
MANIFEST="$WORKSPACE/manifest.json"

assert_equals "recon.sh --skip nuclei,ports: completes with code 0" "0" "$status"

# Active stages should have run
assert_true "recon.sh --skip nuclei,ports: subdomains output created" \
    test -s "$WORKSPACE/subdomains/all.txt"
assert_true "recon.sh --skip nuclei,ports: dns output created" \
    test -s "$WORKSPACE/dns/resolved.txt"
assert_true "recon.sh --skip nuclei,ports: live output created" \
    test -s "$WORKSPACE/live/urls.txt"
assert_true "recon.sh --skip nuclei,ports: crawler output created" \
    test -s "$WORKSPACE/urls/katana.txt"
assert_true "recon.sh --skip nuclei,ports: reports summary created" \
    test -s "$WORKSPACE/reports/summary.md"

# Skipped stages should NOT have output
assert_false "recon.sh --skip nuclei,ports: ports output NOT created" \
    test -f "$WORKSPACE/ports/naabu.txt"
assert_false "recon.sh --skip nuclei,ports: nuclei output NOT created" \
    test -f "$WORKSPACE/nuclei/findings.jsonl"

# Manifest status verification
assert_true "recon.sh --skip nuclei,ports: manifest records ports skipped" \
    grep -q "\"ports\": { \"status\": \"skipped\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: manifest records vuln skipped" \
    grep -q "\"vuln\": { \"status\": \"skipped\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: manifest records subdomains success" \
    grep -q "\"subdomains\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: manifest records dns success" \
    grep -q "\"dns\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: manifest records live success" \
    grep -q "\"live\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: manifest records crawling success" \
    grep -q "\"crawling\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: manifest records reports success" \
    grep -q "\"reports\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --skip nuclei,ports: overall manifest status is success" \
    grep -q "\"status\": \"success\"" "$MANIFEST"

echo "Stage exclusion integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
