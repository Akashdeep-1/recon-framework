#!/usr/bin/env bash
# shellcheck disable=SC2016

# ============================================
# Recon Framework - Output Sanitization Tests
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/report.sh
source "$ROOT_DIR/lib/report.sh"

PASSED=0
FAILED=0

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

# Test: HTML escaping
test_html_escape() {
    local input='<script>alert(1)</script>'
    local escaped
    escaped="$(report_html_escape "$input")"

    assert_contains "&lt;script&gt;alert(1)&lt;/script&gt;" "$escaped" "HTML tags escaped"
}

# Test: Markdown escaping
test_md_escape() {
    local input='*bold* _italic_ `code`'
    local escaped
    escaped="$(report_md_escape "$input")"

    assert_contains '\*bold\*' "$escaped" "Asterisks escaped"
    assert_contains '\_italic\_' "$escaped" "Underscores escaped"
    assert_contains '\`code\`' "$escaped" "Backticks escaped"
}

# Test: Sanitize for HTML
test_sanitize_html() {
    local input='<img src=x onerror=alert(1)>'
    local sanitized
    sanitized="$(report_sanitize "$input" "html")"

    assert_contains "&lt;img" "$sanitized" "HTML sanitized"
    assert_not_contains "<img" "$sanitized" "Raw HTML removed"
}

# Test: Sanitize for Markdown
test_sanitize_md() {
    local input='[link](javascript:alert(1))'
    local sanitized
    sanitized="$(report_sanitize "$input" "md")"

    assert_contains '\[' "$sanitized" "Brackets escaped"
    assert_contains '\(' "$sanitized" "Parentheses escaped"
}

# Test: Sanitize for plain text
test_sanitize_text() {
    local input=$'test\r\nvalue\twith\bcontrol'
    local sanitized
    sanitized="$(report_sanitize "$input" "text")"

    assert_not_contains $'\r' "$sanitized" "Carriage returns removed"
    assert_not_contains $'\b' "$sanitized" "Backspace removed"
}

# Test: Report generation with malicious content
test_report_malicious_content() {
    local workspace
    workspace="$(mktemp -d "${TMPDIR:-/tmp}/test_mal_rep.XXXXXX" 2>/dev/null || mktemp -d)"
    mkdir -p "$workspace/subdomains" "$workspace/dns" "$workspace/ports" "$workspace/live" "$workspace/urls" "$workspace/nuclei" "$workspace/reports"

    # Create malicious content
    echo '<script>alert(1)</script>.example.com' > "$workspace/subdomains/all.txt"
    echo '<script>alert(1)</script>.example.com 1.2.3.4' > "$workspace/dns/resolved.txt"
    echo '1.2.3.4:80 <script>alert(1)</script>' > "$workspace/ports/naabu.txt"
    echo 'http://<script>alert(1)</script>.example.com' > "$workspace/live/urls.txt"
    echo 'http://<script>alert(1)</script>.example.com/path' > "$workspace/urls/katana.txt"
    echo '{"template":"<script>alert(1)</script>"}' > "$workspace/nuclei/findings.jsonl"

    local md_file="$workspace/reports/summary.md"
    local html_file="$workspace/reports/summary.html"

    generate_markdown_report "$workspace" "example.com" "$md_file"
    generate_html_report "$workspace" "example.com" "$html_file"

    local md_content
    md_content="$(cat "$md_file")"
    assert_not_contains "<script>" "$md_content" "MD report sanitized"

    local html_content
    html_content="$(cat "$html_file")"
    assert_not_contains "<script>" "$html_content" "HTML report sanitized"

    rm -rf "$workspace"
}

# Test: Multi-target summary with malicious content
test_multi_target_malicious() {
    local output_base_dir
    output_base_dir="$(mktemp -d "${TMPDIR:-/tmp}/test_mal_multi.XXXXXX" 2>/dev/null || mktemp -d)"

    local target='<script>alert(1)</script>.example.com'
    local ws="$output_base_dir/$target"
    mkdir -p "$ws/subdomains" "$ws/dns" "$ws/ports" "$ws/live" "$ws/urls" "$ws/nuclei"
    echo '{}' > "$ws/manifest.json"

    generate_multi_target_summary "$output_base_dir" "$target"

    local summary_md="$output_base_dir/reports/multi_target_summary.md"
    local content
    content="$(cat "$summary_md")"

    assert_not_contains "<script>" "$content" "Multi-target summary sanitized"

    rm -rf "$output_base_dir"
}

# Run tests
echo "Running Output Sanitization tests..."
test_html_escape
test_md_escape
test_sanitize_html
test_sanitize_md
test_sanitize_text
test_report_malicious_content
test_multi_target_malicious

if (( FAILED > 0 )); then
    echo "Output Sanitization unit tests failed: $PASSED passed, $FAILED failed."
    exit 1
fi
echo "Output Sanitization unit tests completed: $PASSED passed, 0 failed."
exit 0