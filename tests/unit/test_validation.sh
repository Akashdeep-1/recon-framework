#!/usr/bin/env bash

# ============================================
# Unit Tests: Validation and Scope Enforcement
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

FAILED=0
PASSED=0

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


echo "Running Unit Tests: Validation & Scope Safety..."

# 1. Normalization
assert_equals "normalize_domain: trims whitespace and lowercases" \
    "example.com" "$(normalize_domain "  EXAMPLE.COM  ")"

assert_equals "normalize_domain: strips trailing dot" \
    "example.com" "$(normalize_domain "example.com.")"

# 2. Domain Validation
assert_true "validate_domain: allows standard domain" \
    validate_domain "example.com"

assert_true "validate_domain: allows subdomains" \
    validate_domain "sub.example.com"

assert_true "validate_domain: allows subdomains with underscores (_dmarc)" \
    validate_domain "_dmarc.example.com"

assert_false "validate_domain: rejects empty domain" \
    validate_domain ""

assert_false "validate_domain: rejects domain with space" \
    validate_domain "example .com"

assert_false "validate_domain: rejects leading hyphen in label" \
    validate_domain "-bad.example.com"

assert_false "validate_domain: rejects trailing hyphen in label" \
    validate_domain "bad-.example.com"

assert_false "validate_domain: rejects consecutive dots" \
    validate_domain "example..com"

assert_false "validate_domain: rejects single-label domain without TLD" \
    validate_domain "localhost"

assert_false "validate_domain: rejects numeric TLD" \
    validate_domain "example.123"

# 3. Scope Enforcement & Suffix Attacks
TARGET="target.com"

assert_true "is_in_scope: allows target domain itself" \
    is_in_scope "target.com" "$TARGET"

assert_true "is_in_scope: allows direct subdomain" \
    is_in_scope "sub.target.com" "$TARGET"

assert_true "is_in_scope: allows nested subdomain" \
    is_in_scope "deep.sub.target.com" "$TARGET"

assert_false "is_in_scope: REJECTS suffix collision attack (evil-target.com)" \
    is_in_scope "evil-target.com" "$TARGET"

assert_false "is_in_scope: REJECTS suffix trick (nottarget.com)" \
    is_in_scope "nottarget.com" "$TARGET"

assert_false "is_in_scope: REJECTS suffix trick (attacker-target.com)" \
    is_in_scope "attacker-target.com" "$TARGET"

assert_false "is_in_scope: REJECTS target as subdomain of attacker (target.com.attacker.com)" \
    is_in_scope "target.com.attacker.com" "$TARGET"

assert_false "is_in_scope: REJECTS sibling domain with different TLD (target.org)" \
    is_in_scope "target.org" "$TARGET"

assert_false "is_in_scope: REJECTS completely unrelated domain (google.com)" \
    is_in_scope "google.com" "$TARGET"

assert_false "is_in_scope: REJECTS candidate containing URL path (target.com/admin)" \
    is_in_scope "target.com/admin" "$TARGET"

# 4. URL Scope Enforcement
assert_true "is_url_in_scope: allows HTTP URL for target" \
    is_url_in_scope "http://target.com/index.html" "$TARGET"

assert_true "is_url_in_scope: allows HTTPS URL for subdomain with custom port" \
    is_url_in_scope "https://api.target.com:8443/v1/users" "$TARGET"

assert_false "is_url_in_scope: REJECTS URL on suffix-collision domain" \
    is_url_in_scope "https://evil-target.com/login" "$TARGET"

assert_false "is_url_in_scope: REJECTS URL on sibling domain" \
    is_url_in_scope "https://target.org/dashboard" "$TARGET"

# 5. File-based Scope Filtering
tmp_in="$(mktemp)"
tmp_out="$(mktemp)"

cat << EOF > "$tmp_in"
api.target.com
evil-target.com
DEV.TARGET.COM
target.com.attacker.com
target.com
not-target.com
api.target.com
EOF

filter_in_scope "$TARGET" "$tmp_in" "$tmp_out"

expected_filtered="$(printf "api.target.com\ndev.target.com\ntarget.com")"
actual_filtered="$(cat "$tmp_out")"

assert_equals "filter_in_scope: correctly purges suffix attacks, lowercases, and deduplicates" \
    "$expected_filtered" "$actual_filtered"

rm -f "$tmp_in" "$tmp_out"

echo "Validation unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
