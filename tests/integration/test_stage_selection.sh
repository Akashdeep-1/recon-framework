#!/usr/bin/env bash

# ============================================
# Integration Test: Stage Selection & Dependency Graph
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

echo "Running Integration Test: Stage Selection & Dependency Graph..."

TARGET="stages-test.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_stages.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# 1. Test running only --stages subdomains,dns
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --stages subdomains,dns >/dev/null 2>&1 || status=$?
WORKSPACE="$OUTPUT_DIR/$TARGET"
MANIFEST="$WORKSPACE/manifest.json"

assert_equals "recon.sh --stages subdomains,dns: exits with code 0" "0" "$status"
assert_true "recon.sh --stages subdomains,dns: subdomains output created" \
    test -s "$WORKSPACE/subdomains/all.txt"
assert_true "recon.sh --stages subdomains,dns: dns output created" \
    test -s "$WORKSPACE/dns/resolved.txt"
assert_false "recon.sh --stages subdomains,dns: ports output NOT created" \
    test -f "$WORKSPACE/ports/naabu.txt"
assert_false "recon.sh --stages subdomains,dns: live output NOT created" \
    test -f "$WORKSPACE/live/urls.txt"
assert_false "recon.sh --stages subdomains,dns: crawler output NOT created" \
    test -f "$WORKSPACE/urls/katana.txt"
assert_false "recon.sh --stages subdomains,dns: nuclei output NOT created" \
    test -f "$WORKSPACE/nuclei/findings.jsonl"

assert_true "recon.sh --stages subdomains,dns: manifest records subdomains success" \
    grep -q "\"subdomains\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --stages subdomains,dns: manifest records dns success" \
    grep -q "\"dns\": { \"status\": \"success\"" "$MANIFEST"
assert_true "recon.sh --stages subdomains,dns: manifest records ports skipped" \
    grep -q "\"ports\": { \"status\": \"skipped\"" "$MANIFEST"
assert_true "recon.sh --stages subdomains,dns: manifest records live skipped" \
    grep -q "\"live\": { \"status\": \"skipped\"" "$MANIFEST"
assert_true "recon.sh --stages subdomains,dns: manifest records crawling skipped" \
    grep -q "\"crawling\": { \"status\": \"skipped\"" "$MANIFEST"
assert_true "recon.sh --stages subdomains,dns: manifest records vuln skipped" \
    grep -q "\"vuln\": { \"status\": \"skipped\"" "$MANIFEST"
assert_true "recon.sh --stages subdomains,dns: manifest records reports skipped" \
    grep -q "\"reports\": { \"status\": \"skipped\"" "$MANIFEST"

# 2. Test stage name alias resolution: --stages subdomain,dnsx
TARGET_ALIAS="alias-test.com"
status_alias=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET_ALIAS" --stages subdomain,dnsx >/dev/null 2>&1 || status_alias=$?
WORKSPACE_ALIAS="$OUTPUT_DIR/$TARGET_ALIAS"

assert_equals "recon.sh --stages subdomain,dnsx: alias names accepted and exit 0" "0" "$status_alias"
assert_true "recon.sh --stages subdomain,dnsx: subdomains executed" \
    test -s "$WORKSPACE_ALIAS/subdomains/all.txt"
assert_true "recon.sh --stages subdomain,dnsx: dns executed" \
    test -s "$WORKSPACE_ALIAS/dns/resolved.txt"

# 3. Test dependency graph enforcement: downstream stage without upstream dependency fails
TARGET_DEP="dep-test.com"
status_dep=0
out_dep="$(bash "$ROOT_DIR/recon.sh" -d "$TARGET_DEP" --stages dns 2>&1)" || status_dep=$?
assert_equals "recon.sh --stages dns (missing subdomains): aborts with code 1" "1" "$status_dep"
assert_true "recon.sh --stages dns: logs dependency failure message" \
    grep -q "Dependency failure: Stage 'dns' requires 'subdomains'" <<< "$out_dep"

status_live_dep=0
out_live_dep="$(bash "$ROOT_DIR/recon.sh" -d "$TARGET_DEP" --stages live 2>&1)" || status_live_dep=$?
assert_equals "recon.sh --stages live (missing dns): aborts with code 1" "1" "$status_live_dep"
assert_true "recon.sh --stages live: logs dependency failure message" \
    grep -q "Dependency failure: Stage 'live' requires 'dns'" <<< "$out_live_dep"

status_vuln_dep=0
out_vuln_dep="$(bash "$ROOT_DIR/recon.sh" -d "$TARGET_DEP" --stages vuln 2>&1)" || status_vuln_dep=$?
assert_equals "recon.sh --stages vuln (missing urls): aborts with code 1" "1" "$status_vuln_dep"
assert_true "recon.sh --stages vuln: logs dependency failure message" \
    grep -q "Dependency failure: Stage 'vuln' requires 'crawling' or 'live'" <<< "$out_vuln_dep"

# 4. Test dependency satisfaction via existing file on disk
mkdir -p "$OUTPUT_DIR/$TARGET_DEP/subdomains"
echo "seed.dep-test.com" > "$OUTPUT_DIR/$TARGET_DEP/subdomains/all.txt"
status_preseed=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET_DEP" --stages dns >/dev/null 2>&1 || status_preseed=$?
assert_equals "recon.sh --stages dns (pre-existing subdomains/all.txt): succeeds with code 0" "0" "$status_preseed"

echo "Stage selection integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
