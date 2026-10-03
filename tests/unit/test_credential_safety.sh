#!/usr/bin/env bash

# ============================================
# Recon Framework - Credential Safety Tests
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/jsonl_logger.sh
source "$ROOT_DIR/lib/jsonl_logger.sh"

PASSED=0
FAILED=0

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local desc="${3:-contains $needle}"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc (Substring '$needle' not found in output)"
        FAILED=$(( FAILED + 1 ))
    fi
}

assert_not_contains() {
    local needle="$1"
    local haystack="$2"
    local desc="${3:-does not contain $needle}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc (Unexpected substring '$needle' found in output)"
        FAILED=$(( FAILED + 1 ))
    fi
}

# Test: Authorization Bearer token redacted
test_redact_bearer_token() {
    local input='Authorization: Bearer SECRET123'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "SECRET123" "$redacted" "Bearer token redacted"
    assert_contains "[REDACTED]" "$redacted" "Redacted marker present"
}

# Test: API key redacted
test_redact_api_key() {
    local input='api_key=MYSECRETKEY'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "MYSECRETKEY" "$redacted" "API key redacted"
}

# Test: Password redacted
test_redact_password() {
    local input='password=MYPASSWORD123'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "MYPASSWORD123" "$redacted" "Password redacted"
}

# Test: Secret redacted
test_redact_secret() {
    local input='secret=MYSECRET'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "MYSECRET" "$redacted" "Secret redacted"
}

# Test: Token redacted
test_redact_token() {
    local input='token=MYTOKEN'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "MYTOKEN" "$redacted" "Token redacted"
}

# Test: Cookie redacted
test_redact_cookie() {
    local input='cookie=session=ABC123'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "ABC123" "$redacted" "Cookie redacted"
}

# Test: OAuth tokens redacted
test_redact_oauth() {
    local input='access_token=ACCESS123 refresh_token=REFRESH456 client_secret=CLIENT789'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "ACCESS123" "$redacted" "Access token redacted"
    assert_not_contains "REFRESH456" "$redacted" "Refresh token redacted"
    assert_not_contains "CLIENT789" "$redacted" "Client secret redacted"
}

# Test: URL with query params redacted
test_redact_url_params() {
    local input='https://example.com/api?api_key=SECRET&param=value'
    local redacted
    redacted="$(jsonl_redact "$input")"

    assert_not_contains "SECRET" "$redacted" "URL query param redacted"
}

# Test: JSONL logs don't leak secrets
test_jsonl_no_secret_leak() {
    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/test_leak.XXXXXX" 2>/dev/null || printf '/tmp/test_leak_%s' "$$")"
    jsonl_init "test-run" "$tmpfile"
    jsonl_run_start "example.com"
    jsonl_tool_start "subfinder" "subdomains" "example.com"
    jsonl_tool_complete "subfinder" "subdomains" "success" "100" "50"

    local content
    content="$(cat "$tmpfile")"

    assert_not_contains "SECRET" "$content" "No SECRET in logs"
    assert_not_contains "PASSWORD" "$content" "No PASSWORD in logs"
    assert_not_contains "TOKEN" "$content" "No TOKEN in logs"

    rm -f "$tmpfile"
}

# Run tests
echo "Running Credential Safety tests..."
test_redact_bearer_token
test_redact_api_key
test_redact_password
test_redact_secret
test_redact_token
test_redact_cookie
test_redact_oauth
test_redact_url_params
test_jsonl_no_secret_leak

if (( FAILED > 0 )); then
    echo "Credential Safety unit tests failed: $PASSED passed, $FAILED failed."
    exit 1
fi
echo "Credential Safety unit tests completed: $PASSED passed, 0 failed."
exit 0