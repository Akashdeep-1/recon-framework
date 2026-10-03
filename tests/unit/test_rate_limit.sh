#!/usr/bin/env bash

# ============================================
# Recon Framework - Rate Limit Tests
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/rate_limit.sh
source "$ROOT_DIR/lib/rate_limit.sh"

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

assert_success() {
    local desc="$1"
    echo -e "  ${GREEN}✓${RESET} $desc"
    PASSED=$(( PASSED + 1 ))
}

assert_failure() {
    local desc="$1"
    echo -e "  ${RED}✗${RESET} $desc"
    FAILED=$(( FAILED + 1 ))
}

# Test: Rate limit configuration from environment
test_rate_limit_config_env() {
    rate_limit_reset
    export RATE_LIMIT_GLOBAL=10
    export RATE_LIMIT_SUBFINDER=5

    rate_limit_configure 1

    local subfinder_rps
    subfinder_rps="$(rate_limit_get_rps "subfinder")"
    assert_equals "Per-tool override works" "5" "$subfinder_rps"

    local assetfinder_rps
    assetfinder_rps="$(rate_limit_get_rps "assetfinder")"
    assert_equals "Global rate limit applied" "10" "$assetfinder_rps"

    unset RATE_LIMIT_GLOBAL
    unset RATE_LIMIT_SUBFINDER
    rate_limit_reset
}

# Test: Rate limit validation
test_rate_limit_validation() {
    rate_limit_reset
    export RATE_LIMIT_NAABU=0
    if rate_limit_validate 2>/dev/null; then
        assert_failure "Should reject zero rate limit"
    else
        assert_success "Zero rate limit rejected"
    fi
    unset RATE_LIMIT_NAABU

    rate_limit_reset
    export RATE_LIMIT_HTTPX=-1
    if rate_limit_validate 2>/dev/null; then
        assert_failure "Should reject negative rate limit"
    else
        assert_success "Negative rate limit rejected"
    fi
    unset RATE_LIMIT_HTTPX

    rate_limit_reset
    export RATE_LIMIT_NUCLEI=abc
    if rate_limit_validate 2>/dev/null; then
        assert_failure "Should reject non-numeric rate limit"
    else
        assert_success "Non-numeric rate limit rejected"
    fi
    unset RATE_LIMIT_NUCLEI
    rate_limit_reset
}

# Test: Rate limit apply with mock tool
test_rate_limit_apply() {
    rate_limit_reset
    local mock_subfinder
    mock_subfinder="$(mktemp "${TMPDIR:-/tmp}/mock_sub.XXXXXX" 2>/dev/null || printf '/tmp/mock_sub_%s' "$$")"
    cat > "$mock_subfinder" << 'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        -rate-limit)
            echo "RATE_LIMIT_APPLIED=$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
EOF
    chmod +x "$mock_subfinder"

    export RATE_LIMIT_SUBFINDER=3
    rate_limit_configure 1

    local output
    output="$(rate_limit_apply subfinder "$mock_subfinder" -d example.com 2>&1 || true)"

    assert_contains "RATE_LIMIT_APPLIED=3" "$output" "Rate limit passed to subfinder"

    rm -f "$mock_subfinder"
    unset RATE_LIMIT_SUBFINDER
    rate_limit_reset
}

# Test: Unknown tool runs without rate limiting
test_rate_limit_unknown_tool() {
    local mock_unknown
    mock_unknown="$(mktemp "${TMPDIR:-/tmp}/mock_unk.XXXXXX" 2>/dev/null || printf '/tmp/mock_unk_%s' "$$")"
    cat > "$mock_unknown" << 'EOF'
#!/usr/bin/env bash
echo "unknown_tool called"
EOF
    chmod +x "$mock_unknown"

    local output
    output="$(rate_limit_apply unknown_tool "$mock_unknown" 2>&1)"

    assert_contains "unknown_tool called" "$output" "Unknown tool runs without rate limit"

    rm -f "$mock_unknown"
}

# Run tests
echo "Running Rate Limit tests..."
test_rate_limit_config_env
test_rate_limit_validation
test_rate_limit_apply
test_rate_limit_unknown_tool

if (( FAILED > 0 )); then
    echo "Rate Limit unit tests failed: $PASSED passed, $FAILED failed."
    exit 1
fi
echo "Rate Limit unit tests completed: $PASSED passed, 0 failed."
exit 0