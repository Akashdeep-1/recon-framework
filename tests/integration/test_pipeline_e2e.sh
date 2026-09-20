#!/usr/bin/env bash

# ============================================
# Integration Test: End-to-End Pipeline
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

echo "Running Integration Test: End-to-End Mock Pipeline..."

TARGET="mocktarget.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_e2e.XXXXXX" 2>/dev/null || mktemp -d)"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# Run the complete framework against mocktarget.com
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" >/dev/null 2>&1 || status=$?

WORKSPACE="$OUTPUT_DIR/$TARGET"

assert_true "recon.sh: pipeline completes with exit code 0" \
    test "$status" -eq 0

assert_true "recon.sh: creates persistent run log" \
    test -s "$WORKSPACE/logs/recon.log"

assert_true "recon.sh: creates merged subdomains file" \
    test -s "$WORKSPACE/subdomains/all.txt"

assert_false "recon.sh: scope enforcement filters out evil-mocktarget.com" \
    grep -q "evil-mocktarget.com" "$WORKSPACE/subdomains/all.txt"

assert_false "recon.sh: scope enforcement filters out thirdparty domains" \
    grep -q "thirdparty-cdn.com" "$WORKSPACE/subdomains/all.txt"

assert_true "recon.sh: generates hosts JSONL model" \
    test -s "$WORKSPACE/subdomains/hosts.jsonl"

assert_true "recon.sh: executes DNSX stage" \
    test -s "$WORKSPACE/dns/resolved.txt"

assert_true "recon.sh: executes Naabu port scan before crawler" \
    test -s "$WORKSPACE/ports/naabu.txt"

assert_true "recon.sh: generates ports JSONL model" \
    test -s "$WORKSPACE/ports/ports.jsonl"

assert_true "recon.sh: extracts candidate web ports for HTTPX" \
    test -s "$WORKSPACE/ports/web_candidates.txt"

assert_true "recon.sh: executes HTTPX probing" \
    test -s "$WORKSPACE/live/urls.txt"

assert_true "recon.sh: executes Katana crawling" \
    test -s "$WORKSPACE/urls/katana.txt"

assert_true "recon.sh: executes Nuclei scanning" \
    test -s "$WORKSPACE/nuclei/findings.jsonl"

assert_true "recon.sh: generates Markdown report" \
    test -s "$WORKSPACE/reports/summary.md"

assert_true "recon.sh: generates HTML report" \
    test -s "$WORKSPACE/reports/summary.html"

assert_true "recon.sh: generates run manifest" \
    test -s "$WORKSPACE/manifest.json"

assert_true "recon.sh: manifest records overall success" \
    grep -q "\"status\": \"success\"" "$WORKSPACE/manifest.json"

# Cleanup
rm -rf "$OUTPUT_DIR"

echo "End-to-End integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
