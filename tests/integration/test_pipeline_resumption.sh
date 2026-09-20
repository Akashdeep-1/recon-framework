#!/usr/bin/env bash

# ============================================
# Integration Test: Pipeline Resumption Mode
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

echo "Running Integration Test: Resumption Mode (-r)..."

TARGET="resumetarget.com"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recon_resume.XXXXXX" 2>/dev/null || mktemp -d)"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

# 1. Run pipeline to establish existing state
bash "$ROOT_DIR/recon.sh" -d "$TARGET" >/dev/null 2>&1

WORKSPACE="$OUTPUT_DIR/$TARGET"
DNS_OUTPUT="$WORKSPACE/dns/resolved.txt"

# Add a sentinel line to resolved.txt
echo "sentinel.resumetarget.com [10.99.99.99]" >> "$DNS_OUTPUT"

# 2. Run pipeline again with -r (resume mode)
bash "$ROOT_DIR/recon.sh" -d "$TARGET" -r >/dev/null 2>&1

# Verify sentinel line was NOT overwritten by re-running DNSX
assert_true "recon.sh -r: preserves existing stage outputs without re-running" \
    grep -q "sentinel.resumetarget.com" "$DNS_OUTPUT"

# Verify log records resumption skip
assert_true "recon.sh -r: logs stage skip in recon.log" \
    grep -q "resumed" "$WORKSPACE/logs/recon.log"

# Cleanup
rm -rf "$OUTPUT_DIR"

echo "Resumption integration tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
