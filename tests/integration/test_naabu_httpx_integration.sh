#!/usr/bin/env bash

# ============================================
# Integration Test: Naabu -> HTTPX Web Port Integration
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

echo "Running Integration Test: Naabu -> HTTPX Integration..."

TARGET="mocktarget.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_naabu_httpx.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# Run through live stage
status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --stages subdomains,dns,ports,live >/dev/null 2>&1 || status=$?
WORKSPACE="$OUTPUT_DIR/$TARGET"
WEB_CANDIDATES="$WORKSPACE/ports/web_candidates.txt"
HTTP_TARGETS="$WORKSPACE/live/targets.txt"
CLEAN_URLS="$WORKSPACE/live/urls.txt"

assert_equals "recon.sh: completes subdomains,dns,ports,live with code 0" "0" "$status"

# 1. Verify web_candidates.txt includes in-scope non-standard and standard web ports
assert_true "web_candidates: includes 8080 endpoint" \
    grep -q "dev.mocktarget.com:8080" "$WEB_CANDIDATES"

assert_true "web_candidates: includes 8443 endpoint" \
    grep -q "portal.mocktarget.com:8443" "$WEB_CANDIDATES"

assert_true "web_candidates: includes port 80/443 without explicit port or normalized" \
    grep -q "api.mocktarget.com" "$WEB_CANDIDATES"

# 2. Verify non-web ports are rejected from web_candidates
assert_false "web_candidates: rejects SSH port 22" \
    grep -q ":22" "$WEB_CANDIDATES"

# 3. Verify out-of-scope targets are rejected from web_candidates
assert_false "web_candidates: rejects out-of-scope evil-mocktarget.com" \
    grep -q "evil-mocktarget.com" "$WEB_CANDIDATES"

# 4. Verify live targets combined DNS + web candidates
assert_true "live/targets.txt: contains non-standard port 8080 target" \
    grep -q "dev.mocktarget.com:8080" "$HTTP_TARGETS"

assert_true "live/targets.txt: contains non-standard port 8443 target" \
    grep -q "portal.mocktarget.com:8443" "$HTTP_TARGETS"

# 5. Verify HTTPX probed the non-standard web ports
assert_true "live/urls.txt: contains probed URL for port 8080" \
    grep -q "https://dev.mocktarget.com:8080" "$CLEAN_URLS"

assert_true "live/urls.txt: contains probed URL for port 8443" \
    grep -q "https://portal.mocktarget.com:8443" "$CLEAN_URLS"

assert_false "live/urls.txt: does NOT contain port 22" \
    grep -q ":22" "$CLEAN_URLS"

echo "Naabu -> HTTPX integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
