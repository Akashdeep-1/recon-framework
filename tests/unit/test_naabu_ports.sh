#!/usr/bin/env bash
# ============================================
# Unit Tests: NAABU_PORTS Normalization & Validation
# ============================================
# Regression coverage for the naabu -top-ports configuration bug where the
# legacy "top-N" default was passed verbatim to naabu, producing:
#   "could not parse ports: invalid top ports option"
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

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

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

assert_return() {
    # assert_return <expected_code> <desc> <cmd...>
    local expected_code="$1"
    local desc="$2"
    shift 2
    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?
    if [[ "$expected_code" == "$actual_code" ]]; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc (Expected exit: $expected_code, Got: $actual_code)"
        FAILED=$(( FAILED + 1 ))
    fi
}

echo "Running Unit Tests: NAABU_PORTS Normalization & Validation..."

# --- Valid inputs: normalization produces a bare positive integer ---

assert_equals "normalize_naabu_ports: bare '100' remains '100'" \
    "100" "$(normalize_naabu_ports '100')"

assert_equals "normalize_naabu_ports: 'top-100' (legacy bug default) normalizes to '100'" \
    "100" "$(normalize_naabu_ports 'top-100')"

assert_equals "normalize_naabu_ports: 'top-1000' normalizes to '1000'" \
    "1000" "$(normalize_naabu_ports 'top-1000')"

assert_equals "normalize_naabu_ports: 'top-1' normalizes to '1'" \
    "1" "$(normalize_naabu_ports 'top-1')"

assert_equals "normalize_naabu_ports: '65535' remains '65535'" \
    "65535" "$(normalize_naabu_ports '65535')"

assert_equals "normalize_naabu_ports: leading-zero '007' canonicalizes to '7'" \
    "7" "$(normalize_naabu_ports '007')"

assert_equals "normalize_naabu_ports: empty/unset defaults to '100'" \
    "100" "$(normalize_naabu_ports '')"

# --- Invalid inputs: validation rejects and returns non-zero ---

assert_return 1 "normalize_naabu_ports: 'abc' rejected (non-numeric)" \
    normalize_naabu_ports "abc"

assert_return 1 "normalize_naabu_ports: 'top-' rejected (empty after prefix strip)" \
    normalize_naabu_ports "top-"

assert_return 1 "normalize_naabu_ports: 'top-abc' rejected (non-numeric after strip)" \
    normalize_naabu_ports "top-abc"

assert_return 1 "normalize_naabu_ports: '0' rejected (not positive)" \
    normalize_naabu_ports "0"

assert_return 1 "normalize_naabu_ports: 'top-0' rejected (not positive)" \
    normalize_naabu_ports "top-0"

assert_return 1 "normalize_naabu_ports: '-5' rejected (negative)" \
    normalize_naabu_ports "-5"

assert_return 1 "normalize_naabu_ports: '1.5' rejected (non-integer)" \
    normalize_naabu_ports "1.5"

assert_return 1 "normalize_naabu_ports: '100 200' rejected (whitespace)" \
    normalize_naabu_ports "100 200"

# --- Invalid input must not echo anything to stdout ---

out="$(normalize_naabu_ports 'abc' 2>/dev/null || true)"
assert_equals "normalize_naabu_ports: 'abc' prints nothing to stdout" \
    "" "$out"

echo "NAABU_PORTS unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
