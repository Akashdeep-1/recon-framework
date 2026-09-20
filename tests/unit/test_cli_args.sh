#!/usr/bin/env bash

# ============================================
# Unit Tests: CLI Argument Parsing & Overrides
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

echo "Running Unit Tests: CLI Argument Parsing..."

# 1. Help flag returns 0
status=0
out="$(bash "$ROOT_DIR/recon.sh" --help 2>&1)" || status=$?
assert_equals "recon.sh --help: returns 0" "0" "$status"
assert_true "recon.sh --help: includes usage info" \
    grep -q "Usage:" <<< "$out"

status_h=0
bash "$ROOT_DIR/recon.sh" -h >/dev/null 2>&1 || status_h=$?
assert_equals "recon.sh -h: returns 0" "0" "$status_h"

# 2. Missing domain returns 1
status_nodom=0
out_nodom="$(bash "$ROOT_DIR/recon.sh" 2>&1)" || status_nodom=$?
assert_equals "recon.sh without -d: exits with code 1" "1" "$status_nodom"
assert_true "recon.sh without -d: outputs missing target error" \
    grep -q "No target domain supplied" <<< "$out_nodom"

# 3. Missing argument to options returns 1
status_d_noarg=0
out_d_noarg="$(bash "$ROOT_DIR/recon.sh" -d 2>&1)" || status_d_noarg=$?
assert_equals "recon.sh -d without argument: exits with code 1" "1" "$status_d_noarg"
assert_true "recon.sh -d without argument: reports required argument" \
    grep -q "requires an argument" <<< "$out_d_noarg"

status_o_noarg=0
bash "$ROOT_DIR/recon.sh" -d example.com -o >/dev/null 2>&1 || status_o_noarg=$?
assert_equals "recon.sh -o without argument: exits with code 1" "1" "$status_o_noarg"

status_t_noarg=0
bash "$ROOT_DIR/recon.sh" -d example.com -t >/dev/null 2>&1 || status_t_noarg=$?
assert_equals "recon.sh -t without argument: exits with code 1" "1" "$status_t_noarg"

status_stages_noarg=0
bash "$ROOT_DIR/recon.sh" -d example.com --stages >/dev/null 2>&1 || status_stages_noarg=$?
assert_equals "recon.sh --stages without argument: exits with code 1" "1" "$status_stages_noarg"

# 4. Unknown option returns 1
status_unk=0
out_unk="$(bash "$ROOT_DIR/recon.sh" -d example.com --invalid-flag 2>&1)" || status_unk=$?
assert_equals "recon.sh --invalid-flag: exits with code 1" "1" "$status_unk"
assert_true "recon.sh --invalid-flag: reports unknown option" \
    grep -q "Unknown option" <<< "$out_unk"

# 5. Invalid domain format returns 1
status_inval=0
bash "$ROOT_DIR/recon.sh" -d "-invalid.com" >/dev/null 2>&1 || status_inval=$?
assert_equals "recon.sh -d -invalid.com: exits with code 1" "1" "$status_inval"

echo "CLI argument parsing unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
