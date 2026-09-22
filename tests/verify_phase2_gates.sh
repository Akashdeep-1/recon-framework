#!/usr/bin/env bash

# ============================================
# Phase 2 Specific Verification Gates
# ============================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../lib/manifest.sh
source "$ROOT_DIR/lib/manifest.sh"

export PATH="$ROOT_DIR/tests/mock_bin:$PATH"

echo "=================================================="
echo "  SPECIFIC VERIFICATION PASS FOR PHASE 2 GATES   "
echo "=================================================="

# ----------------------------------------------------
# 1. Syntax Check (bash -n) on all scripts
# ----------------------------------------------------
echo -e "\n[Gate 1] Running bash -n on all repository scripts:"
SCRIPTS=(
    "recon.sh"
    "config.sh"
    "install.sh"
    lib/logger.sh
    lib/helpers.sh
    lib/filesystem.sh
    lib/validation.sh
    lib/parser.sh
    lib/parallel.sh
    lib/progress.sh
    lib/report.sh
    lib/manifest.sh
    lib/plugins.sh
    lib/orchestration.sh
    lib/cli.sh
    tests/run_tests.sh
    tests/verify_specifics.sh
    tests/unit/test_validation.sh
    tests/unit/test_parser.sh
    tests/unit/test_dependencies.sh
    tests/unit/test_timeout.sh
    tests/unit/test_cli_args.sh
    tests/unit/test_manifest.sh
    tests/unit/test_manifest_hardening.sh
    tests/unit/test_self_test.sh
    tests/integration/test_pipeline_e2e.sh
    tests/integration/test_pipeline_failure.sh
    tests/integration/test_pipeline_resumption.sh
    tests/integration/test_stage_selection.sh
    tests/integration/test_stage_skip.sh
    tests/integration/test_naabu_httpx_integration.sh
    tests/integration/test_retry_behavior.sh
    tests/integration/test_process_tree_timeout.sh
    tests/mock_bin/subfinder
    tests/mock_bin/assetfinder
    tests/mock_bin/dnsx
    tests/mock_bin/naabu
    tests/mock_bin/httpx
    tests/mock_bin/katana
    tests/mock_bin/nuclei
)

for s in "${SCRIPTS[@]}"; do
    bash -n "$ROOT_DIR/$s"
    echo "  PASS (syntax): $s"
done

# ----------------------------------------------------
# 2. ShellCheck Static Analysis
# ----------------------------------------------------
echo -e "\n[Gate 2] Running ShellCheck:"
SHELLCHECK_BIN=""
if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_BIN="shellcheck"
elif [[ -x "/c/Users/intel/AppData/Local/Programs/Python/Python312/Scripts/shellcheck.exe" ]]; then
    SHELLCHECK_BIN="/c/Users/intel/AppData/Local/Programs/Python/Python312/Scripts/shellcheck.exe"
elif python -m shellcheck --version >/dev/null 2>&1; then
    SHELLCHECK_BIN="python -m shellcheck"
fi

if [[ -n "$SHELLCHECK_BIN" ]]; then
    $SHELLCHECK_BIN \
        "$ROOT_DIR/recon.sh" \
        "$ROOT_DIR/config.sh" \
        "$ROOT_DIR/install.sh" \
        "$ROOT_DIR"/lib/*.sh \
        "$ROOT_DIR"/tests/run_tests.sh \
        "$ROOT_DIR"/tests/verify_specifics.sh \
        "$ROOT_DIR"/tests/unit/*.sh \
        "$ROOT_DIR"/tests/integration/*.sh \
        "$ROOT_DIR"/tests/mock_bin/*
    echo "  PASS: ShellCheck completed with 0 errors and 0 warnings."
else
    echo "  WARN: ShellCheck binary not found in PATH."
fi

# ----------------------------------------------------
# 3. git diff --check (Whitespace and formatting check)
# ----------------------------------------------------
echo -e "\n[Gate 3] Running git diff --check:"
( cd "$ROOT_DIR" && git diff --check )
echo "  PASS: git diff --check reported no whitespace/formatting defects."

# ----------------------------------------------------
# 4. Verification of CLI Stage Selection & Skip
# ----------------------------------------------------
echo -e "\n[Gate 4] Verifying Stage Selection & Skip:"
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT

bash "$ROOT_DIR/recon.sh" -d "gate-test.com" -o "$TMP_OUT" --stages subdomains,dns >/dev/null 2>&1
if [[ -f "$TMP_OUT/gate-test.com/subdomains/all.txt" && -f "$TMP_OUT/gate-test.com/dns/resolved.txt" && ! -f "$TMP_OUT/gate-test.com/ports/naabu.txt" ]]; then
    echo "  PASS: Stage selection ran selected stages and omitted unselected stages."
else
    echo "  FAIL: Stage selection mismatch."
    exit 1
fi

bash "$ROOT_DIR/recon.sh" -d "gate-skip.com" -o "$TMP_OUT" --skip nuclei,ports >/dev/null 2>&1
if [[ -f "$TMP_OUT/gate-skip.com/subdomains/all.txt" && ! -f "$TMP_OUT/gate-skip.com/ports/naabu.txt" && ! -f "$TMP_OUT/gate-skip.com/nuclei/findings.jsonl" ]]; then
    echo "  PASS: Stage skip bypassed nuclei and ports while executing remaining stages."
else
    echo "  FAIL: Stage skip mismatch."
    exit 1
fi

# ----------------------------------------------------
# 5. Verification of Custom Output Directory & Concurrency
# ----------------------------------------------------
echo -e "\n[Gate 5] Verifying Custom Output Directory & Concurrency/Rate-Limit:"
CUSTOM_DIR="$(mktemp -d)"
bash "$ROOT_DIR/recon.sh" -d "gate-custom.com" -o "$CUSTOM_DIR" -t 33 --rate-limit 88 --stages subdomains,dns >/dev/null 2>&1
if [[ -f "$CUSTOM_DIR/gate-custom.com/manifest.json" ]]; then
    grep -q '"threads": 33' "$CUSTOM_DIR/gate-custom.com/manifest.json"
    grep -q '"rate_limit": 88' "$CUSTOM_DIR/gate-custom.com/manifest.json"
    echo "  PASS: Custom directory created and concurrency/rate-limit passed to manifest."
else
    echo "  FAIL: Custom output directory or manifest missing."
    exit 1
fi
rm -rf "$CUSTOM_DIR"

# ----------------------------------------------------
# 6. Verification of Verbose Mode & Resume Mode
# ----------------------------------------------------
echo -e "\n[Gate 6] Verifying Verbose Mode & Resume Mode:"
RESUME_DIR="$(mktemp -d)"
bash "$ROOT_DIR/recon.sh" -d "gate-resume.com" -o "$RESUME_DIR" --stages subdomains,dns >/dev/null 2>&1
echo "sentinel.gate-resume.com [1.2.3.4]" >> "$RESUME_DIR/gate-resume.com/dns/resolved.txt"

# Run with -r --verbose
v_log="$(bash "$ROOT_DIR/recon.sh" -d "gate-resume.com" -o "$RESUME_DIR" -r --verbose --stages subdomains,dns 2>&1)"
if grep -q "sentinel.gate-resume.com" "$RESUME_DIR/gate-resume.com/dns/resolved.txt"; then
    echo "  PASS: Resume mode preserved existing artifact."
else
    echo "  FAIL: Resume mode did not preserve existing artifact."
    exit 1
fi

if grep -q "\[DEBUG\]" <<< "$v_log"; then
    echo "  PASS: Verbose mode printed [DEBUG] logs to console."
else
    echo "  FAIL: Verbose mode did not output debug statements."
    exit 1
fi
rm -rf "$RESUME_DIR"

# ----------------------------------------------------
# 7. Verification of Manifest & All 6 Stage Statuses
# ----------------------------------------------------
echo -e "\n[Gate 7] Verifying Manifest & Reliable Stage Statuses (all 6 statuses):"
TEST_M_DIR="$(mktemp -d)"
init_manifest "$TEST_M_DIR" "status.com" 50 150 300 1 0 "all" ""

# Status 1: pending
grep -q '"status": "pending"' "$TEST_M_DIR/manifest.json"
echo "  PASS: Status 'pending' verified."

# Status 2: running
update_stage_manifest "$TEST_M_DIR" "subdomains" "running" 0 0
grep -q '"subdomains": { "status": "running"' "$TEST_M_DIR/manifest.json"
echo "  PASS: Status 'running' verified."

# Status 3: success
update_stage_manifest "$TEST_M_DIR" "subdomains" "success" 5 10 1
grep -q '"subdomains": { "status": "success", "duration_seconds": 5, "output_count": 10, "attempts": 1 }' "$TEST_M_DIR/manifest.json"
echo "  PASS: Status 'success' verified."

# Status 4: skipped
update_stage_manifest "$TEST_M_DIR" "ports" "skipped" 0 0 0
grep -q '"ports": { "status": "skipped", "duration_seconds": 0, "output_count": 0, "attempts": 0 }' "$TEST_M_DIR/manifest.json"
echo "  PASS: Status 'skipped' verified."

# Status 5: resumed
update_stage_manifest "$TEST_M_DIR" "dns" "resumed" 0 4 0
grep -q '"dns": { "status": "resumed", "duration_seconds": 0, "output_count": 4, "attempts": 0 }' "$TEST_M_DIR/manifest.json"
echo "  PASS: Status 'resumed' verified."

# Status 6: failed
update_stage_manifest "$TEST_M_DIR" "live" "failed" 2 0 2
grep -q '"live": { "status": "failed", "duration_seconds": 2, "output_count": 0, "attempts": 2 }' "$TEST_M_DIR/manifest.json"
echo "  PASS: Status 'failed' verified."

# Manifest finalization and JSON validity
finalize_manifest "$TEST_M_DIR" "failed"
grep -q '"status": "failed"' "$TEST_M_DIR/manifest.json"
python -c "import json, sys; json.load(sys.stdin)" < "$TEST_M_DIR/manifest.json"
echo "  PASS: Manifest finalized and validated as syntactically correct JSON."
rm -rf "$TEST_M_DIR"

# ----------------------------------------------------
# 8. Verification of Naabu -> HTTPX Web Port Integration
# ----------------------------------------------------
echo -e "\n[Gate 8] Verifying Naabu -> HTTPX Web Port Integration:"
INTEG_DIR="$(mktemp -d)"
bash "$ROOT_DIR/recon.sh" -d "mocktarget.com" -o "$INTEG_DIR" --stages subdomains,dns,ports,live >/dev/null 2>&1
CANDIDATES="$INTEG_DIR/mocktarget.com/ports/web_candidates.txt"
LIVE_URLS="$INTEG_DIR/mocktarget.com/live/urls.txt"

if grep -q "dev.mocktarget.com:8080" "$CANDIDATES" && \
   grep -q "https://dev.mocktarget.com:8080" "$LIVE_URLS" && \
   ! grep -q ":22" "$CANDIDATES"; then
    echo "  PASS: Non-standard web ports correctly routed to HTTPX, non-web ports rejected."
else
    echo "  FAIL: Web port integration mismatch."
    exit 1
fi
rm -rf "$INTEG_DIR"

# ----------------------------------------------------
# 9. Verification of Timeout and Retries
# ----------------------------------------------------
echo -e "\n[Gate 9] Verifying Timeout and Retry Behavior:"
RETRY_DIR="$(mktemp -d)"

# Retry success
export MOCK_FAIL_DNSX_FILE="${RETRY_DIR}/attempts.txt"
export MOCK_FAIL_DNSX_COUNT=1
bash "$ROOT_DIR/recon.sh" -d "retry-gate.com" -o "$RETRY_DIR" --stages subdomains,dns --retries 1 >/dev/null 2>&1
grep -q '"dns": { "status": "success"' "$RETRY_DIR/retry-gate.com/manifest.json"
echo "  PASS: Stage succeeded on retry attempt."
unset MOCK_FAIL_DNSX_FILE MOCK_FAIL_DNSX_COUNT

# Timeout termination
mkdir -p "$RETRY_DIR/timeout-gate.com/subdomains"
echo "seed.timeout-gate.com" > "$RETRY_DIR/timeout-gate.com/subdomains/all.txt"
export MOCK_SLEEP_DNSX=5
t_stat=0
bash "$ROOT_DIR/recon.sh" -d "timeout-gate.com" -o "$RETRY_DIR" --stages dns --timeout 1 --retries 0 >/dev/null 2>&1 || t_stat=$?
unset MOCK_SLEEP_DNSX

if [[ "$t_stat" -ne 0 ]]; then
    grep -q '"dns": { "status": "failed"' "$RETRY_DIR/timeout-gate.com/manifest.json"
    echo "  PASS: Timed-out stage terminated and recorded as failed."
else
    echo "  FAIL: Timed-out stage did not fail."
    exit 1
fi
rm -rf "$RETRY_DIR"

echo -e "\n=================================================="
echo "  ALL PHASE 2 VERIFICATION GATES PASSED           "
echo "=================================================="
exit 0
