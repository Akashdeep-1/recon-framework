#!/usr/bin/env bash
# ============================================
# Integration Test: NAABU_PORTS normalization end-to-end
# ============================================
# Regression coverage for the bug where the legacy "top-N" default
# (e.g. NAABU_PORTS=top-100) was passed verbatim to naabu's -top-ports flag,
# producing: "could not parse ports: invalid top ports option".
#
# Invokes the REAL run_naabu() (from lib/plugins.sh) with a mock naabu binary
# that captures the exact -top-ports argument it receives. This proves the
# fix end-to-end: the value handed to naabu is always a bare positive integer.
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/helpers.sh
source "$ROOT_DIR/lib/helpers.sh"
# shellcheck source=../../lib/filesystem.sh
source "$ROOT_DIR/lib/filesystem.sh"
# shellcheck source=../../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"
# shellcheck source=../../lib/parser.sh
source "$ROOT_DIR/lib/parser.sh"
# shellcheck source=../../lib/plugins.sh
source "$ROOT_DIR/lib/plugins.sh"

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

assert_equals_code() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc (Expected exit: $expected, Got: $actual)"
        FAILED=$(( FAILED + 1 ))
    fi
}

echo "Running Integration Test: NAABU_PORTS Normalization (real run_naabu + mock naabu)..."

TARGET="naabu-ports-test.com"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# Minimal resolved-hosts input file in the DNSX "host [ip]" format that
# run_naabu expects (only the first whitespace-separated field is used as host).
make_input_file() {
    local f="$1"
    cat > "$f" <<EOF
api.${TARGET} [10.0.0.1]
dev.${TARGET} [10.0.0.2]
evil-${TARGET} [10.0.0.3]
EOF
}

# Invoke the real run_naabu with a given NAABU_PORTS value and report what the
# mock naabu received for -top-ports. Echoes "<exit_code> <captured_value>".
run_run_naabu() {
    local ports_value="$1"
    local input_file ports_out capture_file status captured

    input_file="$(mktemp)"
    ports_out="$(mktemp)"
    capture_file="$(mktemp)"
    make_input_file "$input_file"

    export NAABU_PORTS="$ports_value"
    export MOCK_NAABU_PORTS_FILE="$capture_file"

    status=0
    run_naabu "$TARGET" "$input_file" "$ports_out" >/dev/null 2>&1 || status=$?

    unset NAABU_PORTS MOCK_NAABU_PORTS_FILE
    captured=""
    [[ -f "$capture_file" ]] && captured="$(cat "$capture_file")"
    rm -f "$input_file" "$ports_out" "$capture_file" 2>/dev/null || true
    printf '%s %s' "$status" "$captured"
}

# --- Scenario 1: legacy "top-100" default must be normalized to 100 ---
result="$(run_run_naabu 'top-100')"
status="${result%% *}"
captured="${result#* }"
assert_equals_code "run_naabu: NAABU_PORTS=top-100 succeeds" "0" "$status"
assert_equals "run_naabu: naabu received normalized -top-ports '100' (not 'top-100')" "100" "$captured"

# --- Scenario 2: bare numeric '100' passes through unchanged ---
result="$(run_run_naabu '100')"
status="${result%% *}"
captured="${result#* }"
assert_equals_code "run_naabu: NAABU_PORTS=100 succeeds" "0" "$status"
assert_equals "run_naabu: naabu received -top-ports '100'" "100" "$captured"

# --- Scenario 3: "top-1000" normalizes to 1000 ---
result="$(run_run_naabu 'top-1000')"
status="${result%% *}"
captured="${result#* }"
assert_equals_code "run_naabu: NAABU_PORTS=top-1000 succeeds" "0" "$status"
assert_equals "run_naabu: naabu received normalized -top-ports '1000'" "1000" "$captured"

# --- Scenario 4: invalid value aborts before naabu is invoked ---
result="$(run_run_naabu 'abc')"
status="${result%% *}"
captured="${result#* }"
assert_equals_code "run_naabu: NAABU_PORTS=abc returns non-zero" "1" "$status"
assert_equals "run_naabu: invalid 'abc' never reaches naabu (no capture)" "" "$captured"

# --- Scenario 5: zero is rejected before naabu is invoked ---
result="$(run_run_naabu '0')"
status="${result%% *}"
captured="${result#* }"
assert_equals_code "run_naabu: NAABU_PORTS=0 returns non-zero" "1" "$status"
assert_equals "run_naabu: invalid '0' never reaches naabu (no capture)" "" "$captured"

# --- Scenario 6: empty input defaults to 100 ---
result="$(run_run_naabu '')"
status="${result%% *}"
captured="${result#* }"
assert_equals_code "run_naabu: empty NAABU_PORTS defaults to 100 and succeeds" "0" "$status"
assert_equals "run_naabu: naabu received default -top-ports '100'" "100" "$captured"

echo "NAABU_PORTS integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
