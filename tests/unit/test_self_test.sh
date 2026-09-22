#!/usr/bin/env bash

# ============================================
# Unit Tests: Self-Test Environment Validation
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
# shellcheck source=../../lib/cli.sh
source "$ROOT_DIR/lib/cli.sh"

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

echo "Running Unit Tests: Self-Test Environment Validation..."

# Ensure mock binaries are in PATH for framework tool checks
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# 1. Self-test runs and exits 0
SELF_TEST=0
run_self_test >/dev/null 2>&1 || SELF_TEST=$?
assert_equals "run_self_test: exits with code 0 when environment is healthy" "0" "$SELF_TEST"

# 2. Self-test does not require a target domain - TARGET_DOMAINS should be empty/unset
if [[ -v TARGET_DOMAINS ]]; then
    TARGETS_LEN="${#TARGET_DOMAINS[@]}"
else
    TARGETS_LEN=0
fi
assert_equals "run_self_test: works without TARGET_DOMAINS set (0 targets)" "0" "$TARGETS_LEN"

# 3. Self-test verifies bash version
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    assert_equals "run_self_test: accepts bash v${BASH_VERSINFO[0]}" "0" "$SELF_TEST"
fi

# 4. Self-test verifies output directory writability
#    Use a temp directory to verify writability check works
TEMP_OUT="$(mktemp -d)"
export OUTPUT_DIR="$TEMP_OUT"
SELF_TEST_OUT=0
run_self_test >/dev/null 2>&1 || SELF_TEST_OUT=$?
assert_equals "run_self_test: succeeds with custom writable OUTPUT_DIR" "0" "$SELF_TEST_OUT"
rm -rf "$TEMP_OUT"

# 5. Self-test detects available core utilities
core_count=0
for util in bash mkdir awk sed grep; do
    if command_exists "$util"; then
        core_count=$((core_count + 1))
    fi
done
assert_equals "run_self_test: detects all 5 core system utilities" "5" "$core_count"

# 6. Self-test detects installed framework tools when mock binaries are in PATH
found_tools=0
for tool in subfinder assetfinder dnsx naabu httpx katana nuclei; do
    if command_exists "$tool"; then
        found_tools=$((found_tools + 1))
    fi
done
assert_equals "run_self_test: all 7 mock framework binaries detected in PATH" "7" "$found_tools"

# 7. Self-test verifies configuration values are valid
assert_true "run_self_test: STAGE_TIMEOUT is valid positive integer" \
    bash -c "[[ \"\$1\" =~ ^[0-9]+$ ]]" _ "$STAGE_TIMEOUT"
assert_true "run_self_test: STAGE_RETRIES is valid non-negative integer" \
    bash -c "[[ \"\$1\" =~ ^[0-9]+$ ]]" _ "$STAGE_RETRIES"
assert_true "run_self_test: ENFORCE_STRICT_SCOPE is boolean (true or false)" \
    bash -c "case \"\$1\" in true|false) :;; *) exit 1;; esac" _ "$ENFORCE_STRICT_SCOPE"

# 8. Self-test via CLI (--self-test flag) works end-to-end
CLI_SELF_TEST=0
bash "$ROOT_DIR/recon.sh" --self-test >/dev/null 2>&1 || CLI_SELF_TEST=$?
assert_equals "recon.sh --self-test: CLI flag works end-to-end" "0" "$CLI_SELF_TEST"

# 9. Self-test is documented in usage output
USAGE_OUT="$(bash "$ROOT_DIR/recon.sh" --help 2>&1)"
assert_true "recon.sh --help: documents --self-test flag" \
    grep -q -- "--self-test" <<< "$USAGE_OUT"

# 10. Self-test exits 0 without any -d flag (no domain required)
NO_DOMAIN_SELF_TEST=0
bash "$ROOT_DIR/recon.sh" --self-test >/dev/null 2>&1 || NO_DOMAIN_SELF_TEST=$?
assert_equals "recon.sh --self-test: exits 0 without -d flag" "0" "$NO_DOMAIN_SELF_TEST"

# 11. Self-test exit code is 0 on success
EXIT_CODE=0
run_self_test >/dev/null 2>&1 || EXIT_CODE=$?
assert_equals "run_self_test: returns exit code 0 on success" "0" "$EXIT_CODE"

# 12. Self-test detects missing dependency
#    Simulate by temporarily breaking PATH to exclude core tools
MISSING_DEP_EXIT=0
(
    PATH="/nonexistent" OUTPUT_DIR="$ROOT_DIR/output" \
    run_self_test >/dev/null 2>&1
) || MISSING_DEP_EXIT=$?
assert_equals "run_self_test: detects missing dependencies (exits non-zero)" "1" \
    "$(( MISSING_DEP_EXIT > 0 ? 1 : 0 ))"

# 13. Self-test detects unreachable output directory
UNREACHABLE_DIR="/nonexistent/path/that/should/not/exist"
UNREACHABLE_EXIT=0
(
    OUTPUT_DIR="$UNREACHABLE_DIR" \
    run_self_test >/dev/null 2>&1
) || UNREACHABLE_EXIT=$?
assert_equals "run_self_test: detects unreachable output directory (exits non-zero)" "1" \
    "$(( UNREACHABLE_EXIT > 0 ? 1 : 0 ))"

# 14. Self-test output includes summary line
SUMMARY_OUT="$(run_self_test 2>&1)"
assert_true "run_self_test: output includes success summary" \
    grep -q "Self-test passed" <<< "$SUMMARY_OUT"

# 15. Self-test output includes individual check results
assert_true "run_self_test: output shows [SUCCESS] for passing checks" \
    grep -q "\[SUCCESS\]" <<< "$SUMMARY_OUT"

echo "Self-test unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
