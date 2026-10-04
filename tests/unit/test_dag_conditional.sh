#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2086

# ============================================
# Phase 7.3 DAG Runtime Conditional Execution Tests
# ============================================

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$TEST_DIR/../.."

# shellcheck source=../../config.sh
source "$ROOT_DIR/config.sh"
# shellcheck source=../../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=../../lib/dag.sh
source "$ROOT_DIR/lib/dag.sh"
# shellcheck source=../../lib/orchestration.sh
source "$ROOT_DIR/lib/orchestration.sh"
# shellcheck source=../../lib/dag_executor.sh
source "$ROOT_DIR/lib/dag_executor.sh"
# shellcheck source=../../lib/manifest.sh
source "$ROOT_DIR/lib/manifest.sh"
# shellcheck source=../../lib/jsonl_logger.sh
source "$ROOT_DIR/lib/jsonl_logger.sh"

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

assert_json_contains() {
    local desc="$1"
    local json="$2"
    local key="$3"
    local expected_value="$4"
    
    local actual_value
    actual_value=$(echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4)
    
    if [[ "$actual_value" == "$expected_value" ]]; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc (Expected: '$expected_value', Got: '$actual_value')"
        FAILED=$(( FAILED + 1 ))
    fi
}

# Helper to reset global DAG arrays
reset_dag_state() {
    DAG_STAGE_ID=()
    DAG_STAGE_LABEL=()
    DAG_STAGE_DEPS=()
    DAG_STAGE_INPUTS=()
    DAG_STAGE_OUTPUTS=()
    DAG_STAGE_CMD=()
    DAG_STAGE_CONDITION=()
    DAG_STAGE_FAILURE_POLICY=()
    DAG_STAGE_PARALLEL_GROUP=()
    DAG_STAGE_TIMEOUT=()
    DAG_STAGE_RETRIES=()
    DAG_STAGE_RATE_LIMIT=()
    DAG_LOADED=0
    DAG_EXEC_STAGE_STATES=()
    DAG_EXEC_WORKSPACE=""
    DAG_TOPO_ORDER=()
}

# Test: Condition evaluation skips stage when condition false (using canonical stages)
test_conditional_skip_no_subdomains() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution")
    DAG_STAGE_DEPS=("" "subdomains")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns")
    DAG_STAGE_CONDITION=("true" "has_subdomains")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_subdomains() { return 0; }
    mock_dns() { return 0; }
    export -f mock_subdomains mock_dns
    
    local tmpdir
    tmpdir=$(mktemp -d)
    # Don't create subdomains/all.txt - condition should fail
    
    # Initialize JSONL logging
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage subdomains should succeed, stage dns should be skipped
    assert_equals "Stage subdomains succeeds" 0 "$result"
    assert_equals "Stage subdomains state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "subdomains")"
    assert_equals "Stage dns skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "dns")"
    
    # Check JSONL for stage_skipped event
    if [[ -f "$jsonl_file" ]]; then
        local skipped_event
        skipped_event=$(grep '"event":"stage_skipped"' "$jsonl_file" || echo "")
        if [[ -n "$skipped_event" ]]; then
            assert_json_contains "JSONL contains stage_skipped event" "$skipped_event" "stage" "dns"
            assert_json_contains "JSONL skip reason contains condition" "$skipped_event" "reason" "condition_false"
        else
            assert_failure "JSONL should contain stage_skipped event"
        fi
    else
        assert_failure "JSONL file should exist"
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns
}

# Test: Condition evaluation runs stage when condition true
test_conditional_run_with_subdomains() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution")
    DAG_STAGE_DEPS=("" "subdomains")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns")
    DAG_STAGE_CONDITION=("true" "has_subdomains")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { return 0; }
    export -f mock_subdomains mock_dns
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains"
    
    # Initialize JSONL logging
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Both stages should succeed
    assert_equals "Stage subdomains succeeds" 0 "$result"
    assert_equals "Stage subdomains state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "subdomains")"
    assert_equals "Stage dns state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "dns")"
    
    # Check JSONL for stage_complete events
    if [[ -f "$jsonl_file" ]]; then
        local complete_events
        complete_events=$(grep '"event":"stage_complete"' "$jsonl_file" || echo "")
        local dns_complete
        dns_complete=$(echo "$complete_events" | grep '"stage":"dns"' || echo "")
        if [[ -n "$dns_complete" ]]; then
            assert_json_contains "Stage dns completed successfully" "$dns_complete" "status" "success"
        else
            assert_failure "JSONL should contain stage_complete for dns"
        fi
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns
}

# Test: has_resolved_hosts condition
test_conditional_has_resolved_hosts() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery")
    DAG_STAGE_DEPS=("" "subdomains" "dns")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports")
    DAG_STAGE_CONDITION=("true" "true" "has_resolved_hosts")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { echo "sub.example.com 1.2.3.4" > "${DAG_EXEC_WORKSPACE}/dns/resolved.txt"; return 0; }
    mock_ports() { return 0; }
    export -f mock_subdomains mock_dns mock_ports
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage ports should run because dns has resolved hosts
    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage ports state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "ports")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports
}

# Test: has_resolved_hosts condition skips when no resolved hosts
test_conditional_has_resolved_hosts_skip() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery")
    DAG_STAGE_DEPS=("" "subdomains" "dns")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports")
    DAG_STAGE_CONDITION=("true" "true" "has_resolved_hosts")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { return 0; }  # No resolved hosts output
    mock_ports() { return 0; }
    export -f mock_subdomains mock_dns mock_ports
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage ports should be skipped because no resolved hosts
    assert_equals "Stage subdomains succeeds" 0 "$result"
    assert_equals "Stage dns succeeds" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "dns")"
    assert_equals "Stage ports skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "ports")"
    
    # Check JSONL for stage_skipped event
    if [[ -f "$jsonl_file" ]]; then
        local skipped_event
        skipped_event=$(grep '"event":"stage_skipped"' "$jsonl_file" | grep '"stage":"ports"' || echo "")
        if [[ -n "$skipped_event" ]]; then
            assert_json_contains "Stage ports skipped with reason" "$skipped_event" "stage" "ports"
        else
            assert_failure "JSONL should contain stage_skipped for ports"
        fi
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports
}

# Test: has_web_targets condition
test_conditional_has_web_targets() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports" "live")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery" "Live Discovery")
    DAG_STAGE_DEPS=("" "subdomains" "dns" "ports")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports" "mock_live")
    DAG_STAGE_CONDITION=("true" "true" "true" "has_web_targets")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { echo "sub.example.com 1.2.3.4" > "${DAG_EXEC_WORKSPACE}/dns/resolved.txt"; return 0; }
    mock_ports() { echo "sub.example.com:80" > "${DAG_EXEC_WORKSPACE}/ports/web_candidates.txt"; return 0; }
    mock_live() { return 0; }
    export -f mock_subdomains mock_dns mock_ports mock_live
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns" "${tmpdir}/ports"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage live should run because web targets exist
    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage live state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "live")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports mock_live
}

# Test: has_live_urls condition
test_conditional_has_live_urls() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports" "live" "crawling")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery" "Live Discovery" "Crawling")
    DAG_STAGE_DEPS=("" "subdomains" "dns" "ports" "live")
    DAG_STAGE_INPUTS=("input" "input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports" "mock_live" "mock_crawling")
    DAG_STAGE_CONDITION=("true" "true" "true" "true" "has_live_urls")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { echo "sub.example.com 1.2.3.4" > "${DAG_EXEC_WORKSPACE}/dns/resolved.txt"; return 0; }
    mock_ports() { echo "sub.example.com:80" > "${DAG_EXEC_WORKSPACE}/ports/web_candidates.txt"; return 0; }
    mock_live() { echo "http://sub.example.com" > "${DAG_EXEC_WORKSPACE}/live/urls.txt"; return 0; }
    mock_crawling() { return 0; }
    export -f mock_subdomains mock_dns mock_ports mock_live mock_crawling
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns" "${tmpdir}/ports" "${tmpdir}/live"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage crawling should run because live URLs exist
    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage crawling state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "crawling")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports mock_live mock_crawling
}

# Test: has_urls condition with katana output
test_conditional_has_urls() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports" "live" "crawling" "vuln")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery" "Live Discovery" "Crawling" "Vulnerability Scanning")
    DAG_STAGE_DEPS=("" "subdomains" "dns" "ports" "live" "crawling")
    DAG_STAGE_INPUTS=("input" "input" "input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports" "mock_live" "mock_crawling" "mock_vuln")
    DAG_STAGE_CONDITION=("true" "true" "true" "true" "true" "has_urls")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "" "" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { echo "sub.example.com 1.2.3.4" > "${DAG_EXEC_WORKSPACE}/dns/resolved.txt"; return 0; }
    mock_ports() { echo "sub.example.com:80" > "${DAG_EXEC_WORKSPACE}/ports/web_candidates.txt"; return 0; }
    mock_live() { echo "http://sub.example.com" > "${DAG_EXEC_WORKSPACE}/live/urls.txt"; return 0; }
    mock_crawling() { echo "http://sub.example.com/path" > "${DAG_EXEC_WORKSPACE}/crawling/katana.txt"; return 0; }
    mock_vuln() { return 0; }
    export -f mock_subdomains mock_dns mock_ports mock_live mock_crawling mock_vuln
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns" "${tmpdir}/ports" "${tmpdir}/live" "${tmpdir}/crawling"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage vuln should run because URLs exist
    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage vuln state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "vuln")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports mock_live mock_crawling mock_vuln
}

# Test: has_urls condition skips when no URLs
test_conditional_has_urls_skip() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports" "live" "crawling" "vuln")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery" "Live Discovery" "Crawling" "Vulnerability Scanning")
    DAG_STAGE_DEPS=("" "subdomains" "dns" "ports" "live" "crawling")
    DAG_STAGE_INPUTS=("input" "input" "input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports" "mock_live" "mock_crawling" "mock_vuln")
    DAG_STAGE_CONDITION=("true" "true" "true" "true" "true" "has_urls")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "" "" "")
    DAG_LOADED=1
    
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { echo "sub.example.com 1.2.3.4" > "${DAG_EXEC_WORKSPACE}/dns/resolved.txt"; return 0; }
    mock_ports() { return 0; }  # No web candidates
    mock_live() { return 0; }  # No live URLs
    mock_crawling() { return 0; }  # No katana output
    mock_vuln() { return 0; }
    export -f mock_subdomains mock_dns mock_ports mock_live mock_crawling mock_vuln
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns" "${tmpdir}/ports" "${tmpdir}/live" "${tmpdir}/crawling"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage vuln should be skipped because no URLs
    assert_equals "Stages subdomains-live succeed" 0 "$result"
    assert_equals "Stage vuln skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "vuln")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports mock_live mock_crawling mock_vuln
}

# Test: Chain of conditions - skip propagates
test_conditional_chain_skip() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "ports" "live" "crawling" "vuln" "reports")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Port Discovery" "Live Discovery" "Crawling" "Vulnerability Scanning" "Reports")
    DAG_STAGE_DEPS=("" "subdomains" "dns" "ports" "live" "crawling" "vuln")
    DAG_STAGE_INPUTS=("input" "input" "input" "input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_ports" "mock_live" "mock_crawling" "mock_vuln" "mock_reports")
    DAG_STAGE_CONDITION=("true" "has_subdomains" "has_resolved_hosts" "has_web_targets" "has_live_urls" "has_urls" "has_urls")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "" "" "" "")
    DAG_LOADED=1
    
    # No mock outputs - all conditions should fail except first
    mock_subdomains() { return 0; }
    mock_dns() { return 0; }
    mock_ports() { return 0; }
    mock_live() { return 0; }
    mock_crawling() { return 0; }
    mock_vuln() { return 0; }
    mock_reports() { return 0; }
    export -f mock_subdomains mock_dns mock_ports mock_live mock_crawling mock_vuln mock_reports
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage subdomains runs, all others skipped
    assert_equals "Stage subdomains succeeds" 0 "$result"
    assert_equals "Stage subdomains state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "subdomains")"
    assert_equals "Stage dns skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "dns")"
    assert_equals "Stage ports skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "ports")"
    assert_equals "Stage live skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "live")"
    assert_equals "Stage crawling skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "crawling")"
    assert_equals "Stage vuln skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "vuln")"
    assert_equals "Stage reports skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "reports")"
    
    # Check JSONL has multiple skipped events
    if [[ -f "$jsonl_file" ]]; then
        local skipped_count
        skipped_count=$(grep -c '"event":"stage_skipped"' "$jsonl_file" || echo 0)
        assert_equals "6 stages skipped" 6 "$skipped_count"
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_ports mock_live mock_crawling mock_vuln mock_reports
}

# Test: has_web_targets with dns fallback (when no web_candidates but dns resolved)
test_conditional_has_web_targets_dns_fallback() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "live")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Live Discovery")
    DAG_STAGE_DEPS=("" "subdomains" "dns")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_live")
    DAG_STAGE_CONDITION=("true" "true" "has_web_targets")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    # DNS has resolved hosts but no web_candidates
    mock_subdomains() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_dns() { echo "sub.example.com 1.2.3.4" > "${DAG_EXEC_WORKSPACE}/dns/resolved.txt"; return 0; }
    mock_live() { return 0; }
    export -f mock_subdomains mock_dns mock_live
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains" "${tmpdir}/dns" "${tmpdir}/ports"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage live should run because has_web_targets uses DNS fallback
    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage live state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "live")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_live
}

# Test: has_web_targets condition skips when no web targets and no DNS
test_conditional_has_web_targets_skip() {
    reset_dag_state
    
    DAG_STAGE_ID=("subdomains" "dns" "live")
    DAG_STAGE_LABEL=("Subdomains" "DNS Resolution" "Live Discovery")
    DAG_STAGE_DEPS=("" "subdomains" "dns")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_subdomains" "mock_dns" "mock_live")
    DAG_STAGE_CONDITION=("true" "true" "has_web_targets")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    # No web targets, no DNS
    mock_subdomains() { return 0; }
    mock_dns() { return 0; }
    mock_live() { return 0; }
    export -f mock_subdomains mock_dns mock_live
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    # Stage live should be skipped
    assert_equals "Stage live skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "live")"
    
    rm -rf "$tmpdir"
    unset -f mock_subdomains mock_dns mock_live
}

# Test: JSONL telemetry for conditional execution
test_conditional_telemetry() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "a")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "has_subdomains")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }  # No subdomains
    mock_b() { return 0; }
    export -f mock_a mock_b
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    
    # Verify JSONL structure for conditional execution
    if [[ -f "$jsonl_file" ]]; then
        # Check for stage_skipped event with reason
        local skipped
        skipped=$(grep '"event":"stage_skipped"' "$jsonl_file" || echo "")
        if [[ -n "$skipped" ]]; then
            assert_json_contains "Skipped event has stage" "$skipped" "stage" "b"
            # Reason should mention condition
            if echo "$skipped" | grep -q '"reason"'; then
                assert_success "Skipped event contains reason field"
            else
                assert_failure "Skipped event missing reason field"
            fi
        else
            assert_failure "Missing stage_skipped event"
        fi
        
        # Check for condition_evaluated field or similar
        local skipped_with_condition
        skipped_with_condition=$(echo "$skipped" | grep -c "condition" || echo 0)
        if [[ "$skipped_with_condition" -gt 0 ]]; then
            assert_success "Skipped event references condition"
        else
            assert_failure "Skipped event should reference condition"
        fi
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test: Condition evaluation telemetry
test_condition_evaluation_telemetry() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "a")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "has_subdomains")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_a() { echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_b() { return 0; }
    export -f mock_a mock_b
    
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains"
    
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    
    # Verify condition_evaluated telemetry
    if [[ -f "$jsonl_file" ]]; then
        # Check for condition_evaluated event or stage_ready with condition info
        local condition_events
        condition_events=$(grep -c "condition_evaluated" "$jsonl_file" || echo 0)
        if [[ "$condition_events" -gt 0 ]]; then
            assert_success "Condition evaluation events found"
        else
            # Alternative: check stage_ready has condition info
            local ready_with_condition
            ready_with_condition=$(grep '"event":"stage_ready"' "$jsonl_file" | grep -c "condition" || echo 0)
            if [[ "$ready_with_condition" -gt 0 ]]; then
                assert_success "Stage ready events contain condition info"
            else
                assert_failure "Missing condition evaluation telemetry"
            fi
        fi
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Run all tests
echo "Running Phase 7.3 Runtime Conditional Execution Tests..."

test_conditional_skip_no_subdomains
test_conditional_run_with_subdomains
test_conditional_has_resolved_hosts
test_conditional_has_resolved_hosts_skip
test_conditional_has_web_targets
test_conditional_has_live_urls
test_conditional_has_urls
test_conditional_has_urls_skip
test_conditional_chain_skip
test_conditional_has_web_targets_dns_fallback
test_conditional_has_web_targets_skip
test_conditional_telemetry
test_condition_evaluation_telemetry

echo ""
echo "====================================="
echo "Phase 7.3 Runtime Conditional Tests: $PASSED passed, $FAILED failed"
echo "====================================="

if (( FAILED > 0 )); then
    exit 1
fi
exit 0