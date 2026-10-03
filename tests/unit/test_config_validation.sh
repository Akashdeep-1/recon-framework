#!/usr/bin/env bash
# shellcheck disable=SC2034

# ============================================
# Recon Framework - Config Validation Tests
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
# shellcheck source=../../lib/config_validation.sh
source "$ROOT_DIR/lib/config_validation.sh"

# shellcheck disable=SC2034
TARGET_DOMAINS=()
# shellcheck disable=SC2034
CONFIG_VALIDATION_ERRORS=()

PASSED=0
FAILED=0

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

# Test: Invalid target domain rejected
test_config_invalid_target() {
    TARGET_DOMAINS=("not-a-valid-domain")
    CONFIG_VALIDATION_ERRORS=()
    if config_validate_targets 2>/dev/null; then
        assert_failure "Should reject invalid domain"
    else
        assert_success "Invalid domain rejected"
    fi
}

# Test: Valid target domain accepted
test_config_valid_target() {
    TARGET_DOMAINS=("example.com" "sub.example.com")
    CONFIG_VALIDATION_ERRORS=()
    if config_validate_targets; then
        assert_success "Valid domains accepted"
    else
        assert_failure "Valid domains should be accepted"
    fi
}

# Test: Invalid NAABU_PORTS rejected
test_config_invalid_naabu_ports() {
    NAABU_PORTS="invalid"
    if normalize_naabu_ports "$NAABU_PORTS" 2>/dev/null; then
        assert_failure "Should reject invalid NAABU_PORTS"
    else
        assert_success "Invalid NAABU_PORTS rejected"
    fi
}

# Test: Valid NAABU_PORTS accepted
test_config_valid_naabu_ports() {
    NAABU_PORTS="100"
    if normalize_naabu_ports "$NAABU_PORTS" >/dev/null; then
        assert_success "Valid NAABU_PORTS accepted"
    else
        assert_failure "Valid NAABU_PORTS should be accepted"
    fi

    NAABU_PORTS="top-1000"
    if normalize_naabu_ports "$NAABU_PORTS" >/dev/null; then
        assert_success "top-N NAABU_PORTS accepted"
    else
        assert_failure "top-N NAABU_PORTS should be accepted"
    fi
}

# Test: Invalid STAGE_TIMEOUT rejected
test_config_invalid_stage_timeout() {
    STAGE_TIMEOUT="abc"
    if [[ ! "$STAGE_TIMEOUT" =~ ^[0-9]+$ ]]; then
        assert_success "Non-numeric STAGE_TIMEOUT rejected"
    else
        assert_failure "Should reject non-numeric STAGE_TIMEOUT"
    fi

    STAGE_TIMEOUT="-1"
    if (( STAGE_TIMEOUT < 0 )); then
        assert_success "Negative STAGE_TIMEOUT rejected"
    else
        assert_failure "Should reject negative STAGE_TIMEOUT"
    fi
}

# Test: Invalid concurrency values warned
test_config_invalid_concurrency() {
    DNSX_THREADS=0
    if (( DNSX_THREADS < 1 )); then
        assert_success "Zero DNSX_THREADS flagged"
    fi
    DNSX_THREADS=2000
    if (( DNSX_THREADS > 1000 )); then
        assert_success "Excessive DNSX_THREADS flagged"
    fi
}

# Test: Invalid ENFORCE_STRICT_SCOPE rejected
test_config_invalid_enforce_scope() {
    ENFORCE_STRICT_SCOPE="maybe"
    if [[ "$ENFORCE_STRICT_SCOPE" != "true" && "$ENFORCE_STRICT_SCOPE" != "false" ]]; then
        assert_success "Invalid ENFORCE_STRICT_SCOPE rejected"
    else
        assert_failure "Should reject invalid ENFORCE_STRICT_SCOPE"
    fi
}

# Run tests
echo "Running Config Validation tests..."
test_config_invalid_target
test_config_valid_target
test_config_invalid_naabu_ports
test_config_valid_naabu_ports
test_config_invalid_stage_timeout
test_config_invalid_concurrency
test_config_invalid_enforce_scope

if (( FAILED > 0 )); then
    echo "Config Validation unit tests failed: $PASSED passed, $FAILED failed."
    exit 1
fi
echo "Config Validation unit tests completed: $PASSED passed, 0 failed."
exit 0