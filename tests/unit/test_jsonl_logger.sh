#!/usr/bin/env bash

# ============================================
# Recon Framework - JSONL Logger Tests
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

assert_success() {
    local desc="$1"
    echo -e "  ${GREEN}✓${RESET} $desc"
    PASSED=$(( PASSED + 1 ))
}

# Test: JSONL run_start event
test_jsonl_run_start() {
    local run_id
    run_id="$(jsonl_generate_run_id)"
    jsonl_init "$run_id"
    jsonl_run_start "example.com"

    local current_id
    current_id="$(jsonl_get_run_id)"
    if [[ "$current_id" =~ ^run-[0-9]+-[0-9]+$ ]]; then
        assert_success "Run ID format matches run-*"
    else
        assert_failure "Run ID format matches run-*"
    fi
}

# Test: JSONL tool events
test_jsonl_tool_events() {
    jsonl_init "test-run"
    jsonl_tool_start "subfinder" "subdomains" "example.com"
    jsonl_tool_complete "subfinder" "subdomains" "success" "4210" "127"
    jsonl_tool_error "assetfinder" "subdomains" "timeout" "5000"

    assert_success "Tool events emit without error"
}

# Test: JSONL stage events
test_jsonl_stage_events() {
    jsonl_init "test-run"
    jsonl_stage_start "subdomains" "example.com"
    jsonl_stage_complete "subdomains" "success" "4210" "127"

    assert_success "Stage events emit without error"
}

# Test: JSONL redaction
test_jsonl_redaction() {
    local test_str="Authorization: Bearer SECRET123 api_key=MYKEY password=PASS123"
    local redacted
    redacted="$(jsonl_redact "$test_str")"

    assert_not_contains "SECRET123" "$redacted" "Bearer token redacted"
    assert_not_contains "MYKEY" "$redacted" "API key redacted"
    assert_not_contains "PASS123" "$redacted" "Password redacted"
    assert_contains "[REDACTED]" "$redacted" "Redacted marker present"
}

# Test: JSONL parseable
test_jsonl_parseable() {
    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/test_jsonl.XXXXXX" 2>/dev/null || printf '/tmp/test_jsonl_%s' "$$")"
    jsonl_init "test-run" "$tmpfile"
    jsonl_run_start "example.com"
    jsonl_tool_start "subfinder" "subdomains" "example.com"
    jsonl_tool_complete "subfinder" "subdomains" "success" "100" "50"

    local parse_ok=1
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            if command -v jq >/dev/null 2>&1; then
                printf '%s\n' "$line" | jq empty >/dev/null 2>&1 || parse_ok=0
            elif [[ "$line" =~ ^\{.*\}$ ]]; then
                : # Valid JSON object structure
            else
                parse_ok=0
            fi
        fi
    done < "$tmpfile"

    rm -f "$tmpfile"
    assert_true "All JSONL lines are parseable" test "$parse_ok" -eq 1
}

# Run tests
echo "Running JSONL Logger tests..."
test_jsonl_run_start
test_jsonl_tool_events
test_jsonl_stage_events
test_jsonl_redaction
test_jsonl_parseable

if (( FAILED > 0 )); then
    echo "JSONL Logger unit tests failed: $PASSED passed, $FAILED failed."
    exit 1
fi
echo "JSONL Logger unit tests completed: $PASSED passed, 0 failed."
exit 0