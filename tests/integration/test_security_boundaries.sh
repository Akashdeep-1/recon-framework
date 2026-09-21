#!/usr/bin/env bash

# ============================================
# Integration Test: Security Boundaries & Input Sanitization
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"

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

echo "Running Integration Test: Security Boundaries & Input Sanitization..."

TARGET="authorized-target.com"

# 1. Path Traversal Rejections
assert_false "rejects path traversal in domain: ../../../evil.com" \
    validate_domain "../../../evil.com"
assert_false "rejects path traversal with backslashes: ..\\..\\evil.com" \
    validate_domain "..\\..\\evil.com"
assert_false "rejects forward slashes in domain: domain/subdir.com" \
    validate_domain "domain/subdir.com"

# 2. Command Injection & Special Character Rejections in Domain
# shellcheck disable=SC2016
assert_false "rejects semicolon command injection: target.com;id" \
    validate_domain "target.com;id"
# shellcheck disable=SC2016
assert_false "rejects backtick command injection: target.com\`id\`" \
    validate_domain 'target.com`id`'
# shellcheck disable=SC2016
assert_false "rejects dollar command injection: target.com\$(id)" \
    validate_domain 'target.com$(id)'
assert_false "rejects pipe character in domain: target.com|id" \
    validate_domain "target.com|id"
assert_false "rejects newline / CRLF in domain" \
    validate_domain $'target.com\nnewline.com'

# 3. Scope Enforcement: Exact, Suffix, Sibling Bypasses
assert_true "in-scope: authorized-target.com" \
    is_in_scope "authorized-target.com" "$TARGET"
assert_true "in-scope: api.authorized-target.com" \
    is_in_scope "api.authorized-target.com" "$TARGET"
assert_true "in-scope: deep.dev.authorized-target.com" \
    is_in_scope "deep.dev.authorized-target.com" "$TARGET"

assert_false "out-of-scope: attacker-authorized-target.com" \
    is_in_scope "attacker-authorized-target.com" "$TARGET"
assert_false "out-of-scope: authorized-target.com.attacker.com" \
    is_in_scope "authorized-target.com.attacker.com" "$TARGET"
assert_false "out-of-scope: fakeauthorized-target.com" \
    is_in_scope "fakeauthorized-target.com" "$TARGET"
assert_false "out-of-scope: authorized-target.net" \
    is_in_scope "authorized-target.net" "$TARGET"
assert_false "out-of-scope: sibling domain with target substring" \
    is_in_scope "not-authorized-target.com" "$TARGET"

# 4. Scope Enforcement: Credentials / Userinfo URL edge cases
assert_false "URL scope rejects userinfo confusion: http://authorized-target.com@attacker.com" \
    is_url_in_scope "http://authorized-target.com@attacker.com" "$TARGET"
assert_false "URL scope rejects credential trick: https://user:pass@evil.com/path" \
    is_url_in_scope "https://user:pass@evil.com/path" "$TARGET"
assert_true "URL scope accepts userinfo on valid host: http://user:pass@api.authorized-target.com/path" \
    is_url_in_scope "http://user:pass@api.authorized-target.com/path" "$TARGET"

# 5. CLI Numeric Option Boundary Validation
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_sec_test.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" -t "-5" >/dev/null 2>&1 || status=$?
assert_equals "rejects negative threads (-t -5): exits with code 1" "1" "$status"

status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" -t "abc" >/dev/null 2>&1 || status=$?
assert_equals "rejects non-numeric threads (-t abc): exits with code 1" "1" "$status"

status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --rate-limit "-10" >/dev/null 2>&1 || status=$?
assert_equals "rejects negative rate-limit: exits with code 1" "1" "$status"

status=0
bash "$ROOT_DIR/recon.sh" -d "$TARGET" --timeout "-30" >/dev/null 2>&1 || status=$?
assert_equals "rejects negative timeout: exits with code 1" "1" "$status"

echo "Security boundaries integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
