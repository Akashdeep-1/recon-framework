#!/usr/bin/env bash

# ============================================
# Independent Specific Verification Suite
# ============================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"
# shellcheck source=../lib/parallel.sh
source "$ROOT_DIR/lib/parallel.sh"

TARGET="target.com"
echo "=================================================="
echo "  SPECIFIC VERIFICATION PASS FOR PHASE 1 GATES   "
echo "=================================================="

# 1. Scope filtering bypass tests
echo -e "\n[1] Verifying Suffix & Sibling Bypass Resistance:"
for bypass in "evil-target.com" "target.com.attacker.com" "attacker-target.com" "fake-target.com" "not-target.com"; do
    if is_in_scope "$bypass" "$TARGET"; then
        echo "FAIL: Scope check bypassed by $bypass"
        exit 1
    else
        echo "PASS: Rejected scope bypass: $bypass"
    fi
done

# 2. Uppercase targets normalization
echo -e "\n[2] Verifying Uppercase Target Normalization:"
for raw in "TARGET.COM" "SUB.TARGET.COM" "API.DEV.TARGET.COM"; do
    norm="$(normalize_domain "$raw")"
    if [[ "$norm" =~ [A-Z] ]]; then
        echo "FAIL: Failed to lowercase $raw -> $norm"
        exit 1
    fi
    if ! is_in_scope "$norm" "$TARGET"; then
        echo "FAIL: Normalized uppercase domain $norm rejected by is_in_scope"
        exit 1
    fi
    echo "PASS: Normalizes '$raw' -> '$norm' (in-scope: true)"
done

# 3. Trailing-dot target normalization
echo -e "\n[3] Verifying Trailing-Dot Target Normalization:"
for raw in "target.com." "api.target.com." "deep.sub.target.com."; do
    norm="$(normalize_domain "$raw")"
    if [[ "$norm" == *. ]]; then
        echo "FAIL: Failed to strip trailing dot from $raw -> $norm"
        exit 1
    fi
    if ! is_in_scope "$norm" "$TARGET"; then
        echo "FAIL: Trailing-dot domain $norm rejected by is_in_scope"
        exit 1
    fi
    echo "PASS: Normalizes '$raw' -> '$norm' (in-scope: true)"
done

# 4. Blank lines and duplicate hosts filtering
echo -e "\n[4] Verifying Blank Lines & Duplicate Hosts in filter_in_scope:"
tmp_in="$(mktemp)"
tmp_out="$(mktemp)"

cat << EOF > "$tmp_in"

api.target.com

   
API.TARGET.COM
api.target.com
evil-target.com
target.com.attacker.com
dev.target.com
dev.target.com.
EOF

filter_in_scope "$TARGET" "$tmp_in" "$tmp_out"
actual_count="$(wc -l < "$tmp_out" | tr -d ' ')"
echo "Filtered host count: $actual_count"
cat "$tmp_out"

if [[ "$actual_count" -ne 2 ]]; then
    echo "FAIL: Expected exactly 2 unique in-scope hosts, got $actual_count"
    exit 1
fi
if grep -q "evil-target.com" "$tmp_out" || grep -q "attacker.com" "$tmp_out"; then
    echo "FAIL: Out-of-scope host leaked into output"
    exit 1
fi
echo "PASS: Blank lines removed, duplicates merged, out-of-scope dropped."
rm -f "$tmp_in" "$tmp_out"

# 5. Tool failure propagation
echo -e "\n[5] Verifying Tool Failure Propagation:"
export PATH="$ROOT_DIR/tests/mock_bin:$PATH"
export OUTPUT_DIR
OUTPUT_DIR="$(mktemp -d)"

export MOCK_FAIL_DNSX=1
fail_status=0
bash "$ROOT_DIR/recon.sh" -d "failcheck.com" >/dev/null 2>&1 || fail_status=$?
unset MOCK_FAIL_DNSX

if [[ "$fail_status" -ne 0 ]]; then
    echo "PASS: Pipeline exited with non-zero code ($fail_status) on tool failure."
else
    echo "FAIL: Pipeline exited with 0 despite tool failure."
    exit 1
fi
rm -rf "$OUTPUT_DIR"

# 6. Resume behavior
echo -e "\n[6] Verifying Resume Behavior (-r):"
OUTPUT_DIR="$(mktemp -d)"
RESUME_TARGET="resumetest.com"
bash "$ROOT_DIR/recon.sh" -d "$RESUME_TARGET" >/dev/null 2>&1

WORKSPACE="$OUTPUT_DIR/$RESUME_TARGET"
SENTINEL="sentinel.resumetest.com [10.254.254.254]"
echo "$SENTINEL" >> "$WORKSPACE/dns/resolved.txt"

# Run again with -r
bash "$ROOT_DIR/recon.sh" -d "$RESUME_TARGET" -r >/dev/null 2>&1

if grep -q "sentinel.resumetest.com" "$WORKSPACE/dns/resolved.txt"; then
    echo "PASS: Existing stage results preserved when running with -r."
else
    echo "FAIL: Sentinel line was overwritten in resume mode."
    exit 1
fi
rm -rf "$OUTPUT_DIR"

# 7. SIGINT Cleanup
echo -e "\n[7] Verifying SIGINT Process Cleanup Logic:"
# Launch a background sleeper via parallel mechanism and trigger cleanup
(
    sleep 30 &
    child_pid=$!
    # shellcheck disable=SC2034
    ACTIVE_CHILD_PIDS=("$child_pid")
    cleanup_parallel_tasks >/dev/null 2>&1
    if kill -0 "$child_pid" 2>/dev/null; then
        echo "FAIL: Child process $child_pid was not terminated."
        kill -9 "$child_pid" 2>/dev/null || true
        exit 1
    else
        echo "PASS: Child process $child_pid successfully terminated by cleanup."
    fi
)

# 8. Log file creation & Report generation
echo -e "\n[8] Verifying Log File Creation & Report Generation:"
OUTPUT_DIR="$(mktemp -d)"
VERIFY_TARGET="reportcheck.com"
bash "$ROOT_DIR/recon.sh" -d "$VERIFY_TARGET" >/dev/null 2>&1

WORKSPACE="$OUTPUT_DIR/$VERIFY_TARGET"
if [[ -s "$WORKSPACE/logs/recon.log" ]]; then
    echo "PASS: Persistent log file created and populated ($WORKSPACE/logs/recon.log)."
    head -n 3 "$WORKSPACE/logs/recon.log"
else
    echo "FAIL: Persistent log file missing or empty."
    exit 1
fi

if [[ -s "$WORKSPACE/reports/summary.md" && -s "$WORKSPACE/reports/summary.html" ]]; then
    echo "PASS: Both summary.md and summary.html were generated."
else
    echo "FAIL: Summary reports missing or empty."
    exit 1
fi
rm -rf "$OUTPUT_DIR"

echo -e "\n=================================================="
echo "  ALL 12 SPECIFIC VERIFICATION CHECKS PASSED      "
echo "=================================================="
exit 0
