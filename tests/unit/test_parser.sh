#!/usr/bin/env bash

# ============================================
# Unit Tests: Parser & Normalized Data Models
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
# shellcheck source=../../lib/parser.sh
source "$ROOT_DIR/lib/parser.sh"

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
        echo -e "  ${RED}✗${RESET} $desc"
        echo "    Expected: $expected"
        echo "    Got:      $actual"
        FAILED=$(( FAILED + 1 ))
    fi
}

echo "Running Unit Tests: Parsers & Normalized Data Models..."

TARGET="target.com"
TMP_DIR="$(mktemp -d)"

# 1. Hosts JSONL Parser
hosts_in="$TMP_DIR/hosts.txt"
hosts_out="$TMP_DIR/hosts.jsonl"
cat << EOF > "$hosts_in"
api.target.com
dev.target.com
EOF

parse_hosts_jsonl "$hosts_in" "$hosts_out" "$TARGET" "test_source"

expected_jsonl_line1='{"host":"api.target.com","target":"target.com","source":"test_source"}'
actual_jsonl_line1="$(head -n 1 "$hosts_out")"
assert_equals "parse_hosts_jsonl: generates valid JSONL structure" \
    "$expected_jsonl_line1" "$actual_jsonl_line1"

# 2. DNSX Parser
dnsx_in="$TMP_DIR/dnsx.txt"
dnsx_out="$TMP_DIR/dnsx.jsonl"
cat << EOF > "$dnsx_in"
api.target.com [10.0.0.1]
dev.target.com [10.0.0.2, 10.0.0.3]
EOF

parse_dnsx_output "$dnsx_in" "$dnsx_out" "$TARGET"
expected_dnsx_line='{"host":"api.target.com","ip":"10.0.0.1","target":"target.com"}'
actual_dnsx_line="$(head -n 1 "$dnsx_out")"
assert_equals "parse_dnsx_output: extracts host and IP" \
    "$expected_dnsx_line" "$actual_dnsx_line"

# 3. Naabu Port Parser & Web Candidates Extractor
naabu_in="$TMP_DIR/naabu.txt"
naabu_out="$TMP_DIR/ports.jsonl"
web_out="$TMP_DIR/web_candidates.txt"
cat << EOF > "$naabu_in"
api.target.com:443
dev.target.com:8080
dev.target.com:22
evil-target.com:80
EOF

parse_naabu_output "$naabu_in" "$naabu_out" "$TARGET"
expected_port_line='{"host":"api.target.com","port":443,"protocol":"tcp","target":"target.com"}'
actual_port_line="$(head -n 1 "$naabu_out")"
assert_equals "parse_naabu_output: parses port and host" \
    "$expected_port_line" "$actual_port_line"

extract_web_ports_from_naabu "$naabu_in" "$web_out" "$TARGET" "80,443,8080,8443"
expected_web_candidates="$(printf "api.target.com\ndev.target.com:8080")"
actual_web_candidates="$(cat "$web_out")"
assert_equals "extract_web_ports_from_naabu: keeps standard & non-standard web ports, ignores SSH (22) and evil-target.com" \
    "$expected_web_candidates" "$actual_web_candidates"

# 4. Nuclei Findings Parser
nuclei_in="$ROOT_DIR/tests/fixtures/nuclei_sample.jsonl"
nuclei_summary="$TMP_DIR/summary.json"

parse_nuclei_findings "$nuclei_in" "$nuclei_summary" "$TARGET"

assert_true "parse_nuclei_findings: produces summary file" \
    test -f "$nuclei_summary"

grep -q '"total_findings": 4' "$nuclei_summary"
assert_true "parse_nuclei_findings: correct total findings count" \
    test $? -eq 0

grep -q '"critical": 1' "$nuclei_summary"
assert_true "parse_nuclei_findings: critical severity count is 1" \
    test $? -eq 0

grep -q '"high": 1' "$nuclei_summary"
assert_true "parse_nuclei_findings: high severity count is 1" \
    test $? -eq 0

# Cleanup
rm -rf "$TMP_DIR"

echo "Parser unit tests completed: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
    exit 1
fi
exit 0
