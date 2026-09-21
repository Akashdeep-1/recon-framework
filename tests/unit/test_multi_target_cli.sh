#!/usr/bin/env bash

# ============================================
# Unit Tests: Multi-Target CLI & Deduplication
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

PASSED=0
FAILED=0


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

echo "Running Unit Tests: Multi-Target CLI Parsing..."

# 1. Comma-separated domains in -d
test_d_comma() {
    # shellcheck source=../../config.sh
    source "$ROOT_DIR/config.sh"
    # shellcheck source=../../lib/logger.sh
    source "$ROOT_DIR/lib/logger.sh"
    # shellcheck source=../../lib/validation.sh
    source "$ROOT_DIR/lib/validation.sh"
    # shellcheck source=../../lib/cli.sh
    source "$ROOT_DIR/lib/cli.sh"

    parse_cli_args -d "example.com,target.org,api.example.com"
    assert_equals "parse_cli_args: parses 3 comma-separated targets" "3" "${#TARGET_DOMAINS[@]}"
    assert_equals "parse_cli_args: target 1 is example.com" "example.com" "${TARGET_DOMAINS[0]}"
    assert_equals "parse_cli_args: target 2 is target.org" "target.org" "${TARGET_DOMAINS[1]}"
    assert_equals "parse_cli_args: target 3 is api.example.com" "api.example.com" "${TARGET_DOMAINS[2]}"
    assert_equals "parse_cli_args: backward-compatible DOMAIN is example.com" "example.com" "$DOMAIN"
}
test_d_comma

# 2. Repeated -d arguments
test_d_repeated() {
    # shellcheck source=../../config.sh
    source "$ROOT_DIR/config.sh"
    # shellcheck source=../../lib/logger.sh
    source "$ROOT_DIR/lib/logger.sh"
    # shellcheck source=../../lib/validation.sh
    source "$ROOT_DIR/lib/validation.sh"
    # shellcheck source=../../lib/cli.sh
    source "$ROOT_DIR/lib/cli.sh"

    parse_cli_args -d "alpha.com" -d "beta.org"
    assert_equals "parse_cli_args: parses repeated -d options" "2" "${#TARGET_DOMAINS[@]}"
    assert_equals "parse_cli_args: target 1 is alpha.com" "alpha.com" "${TARGET_DOMAINS[0]}"
    assert_equals "parse_cli_args: target 2 is beta.org" "beta.org" "${TARGET_DOMAINS[1]}"
}
test_d_repeated

# 3. Deduplication of identical targets
test_dedup() {
    # shellcheck source=../../config.sh
    source "$ROOT_DIR/config.sh"
    # shellcheck source=../../lib/logger.sh
    source "$ROOT_DIR/lib/logger.sh"
    # shellcheck source=../../lib/validation.sh
    source "$ROOT_DIR/lib/validation.sh"
    # shellcheck source=../../lib/cli.sh
    source "$ROOT_DIR/lib/cli.sh"

    parse_cli_args -d "example.com,EXAMPLE.COM,example.com.,sub.example.com"
    assert_equals "parse_cli_args: deduplicates identical normalized targets" "2" "${#TARGET_DOMAINS[@]}"
    assert_equals "parse_cli_args: target 1 is example.com" "example.com" "${TARGET_DOMAINS[0]}"
    assert_equals "parse_cli_args: target 2 is sub.example.com" "sub.example.com" "${TARGET_DOMAINS[1]}"
}
test_dedup

# 4. Target list file (-l)
test_list_file() {
    local tmp_file
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/recon_test_targets.XXXXXX")"
    cat << EOF > "$tmp_file"
# Comment line
example.com
  target.org  

# Another comment
api.example.com
EOF

    # shellcheck source=../../config.sh
    source "$ROOT_DIR/config.sh"
    # shellcheck source=../../lib/logger.sh
    source "$ROOT_DIR/lib/logger.sh"
    # shellcheck source=../../lib/validation.sh
    source "$ROOT_DIR/lib/validation.sh"
    # shellcheck source=../../lib/cli.sh
    source "$ROOT_DIR/lib/cli.sh"

    parse_cli_args -l "$tmp_file"
    rm -f "$tmp_file"

    assert_equals "parse_cli_args -l: parses targets from file" "3" "${#TARGET_DOMAINS[@]}"
    assert_equals "parse_cli_args -l: target 1 is example.com" "example.com" "${TARGET_DOMAINS[0]}"
    assert_equals "parse_cli_args -l: target 2 is target.org" "target.org" "${TARGET_DOMAINS[1]}"
    assert_equals "parse_cli_args -l: target 3 is api.example.com" "api.example.com" "${TARGET_DOMAINS[2]}"
}
test_list_file

# 5. Non-existent target file exits with code 1
test_missing_file() {
    local status=0
    bash "$ROOT_DIR/recon.sh" -l "/non/existent/targets.txt" >/dev/null 2>&1 || status=$?
    assert_equals "recon.sh -l nonexistent: exits with code 1" "1" "$status"
}
test_missing_file

# 6. Malformed target in comma list exits with code 1
test_malformed_target() {
    local status=0
    bash "$ROOT_DIR/recon.sh" -d "valid.com,-invalid.org" >/dev/null 2>&1 || status=$?
    assert_equals "recon.sh with invalid domain in list: exits with code 1" "1" "$status"
}
test_malformed_target

echo "Multi-target CLI unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
