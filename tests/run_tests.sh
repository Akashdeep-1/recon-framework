#!/usr/bin/env bash

# ============================================
# Recon Framework - Master Test Runner
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/.."

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}============================================${RESET}"
echo -e "${CYAN}  Recon Framework - Automated Test Suite    ${RESET}"
echo -e "${CYAN}============================================${RESET}"
echo ""

SUITES=(
    "tests/unit/test_validation.sh"
    "tests/unit/test_parser.sh"
    "tests/unit/test_dependencies.sh"
    "tests/unit/test_timeout.sh"
    "tests/unit/test_cli_args.sh"
    "tests/unit/test_manifest.sh"
    "tests/integration/test_stage_selection.sh"
    "tests/integration/test_stage_skip.sh"
    "tests/integration/test_naabu_httpx_integration.sh"
    "tests/integration/test_retry_behavior.sh"
    "tests/integration/test_process_tree_timeout.sh"
    "tests/integration/test_pipeline_e2e.sh"
    "tests/integration/test_pipeline_failure.sh"
    "tests/integration/test_pipeline_resumption.sh"
)

TOTAL_SUITES=${#SUITES[@]}
SUITES_PASSED=0
SUITES_FAILED=0

for suite in "${SUITES[@]}"; do
    suite_path="$ROOT_DIR/$suite"
    echo -e "${CYAN}>>> Running: $suite${RESET}"

    if bash "$suite_path"; then
        echo -e "${GREEN}>>> PASSED: $suite${RESET}\n"
        SUITES_PASSED=$(( SUITES_PASSED + 1 ))
    else
        echo -e "${RED}>>> FAILED: $suite${RESET}\n"
        SUITES_FAILED=$(( SUITES_FAILED + 1 ))
    fi
done

echo -e "${CYAN}============================================${RESET}"
echo -e "Test Suites: ${GREEN}$SUITES_PASSED passed${RESET}, ${RED}$SUITES_FAILED failed${RESET}, $TOTAL_SUITES total"
echo -e "${CYAN}============================================${RESET}"

if (( SUITES_FAILED > 0 )); then
    exit 1
fi
exit 0
