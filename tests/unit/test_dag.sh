#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2086

# ============================================
# Phase 7.1 DAG Data Model and Validation Tests
# ============================================

set -euo pipefail

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

# Test: Stage ID validation
test_dag_validate_stage_id() {
    dag_validate_stage_id "subdomains" && assert_success "Valid stage ID accepted" || assert_failure "Valid stage ID rejected"
    dag_validate_stage_id "dns" && assert_success "Short stage ID accepted" || assert_failure "Short stage ID rejected"
    dag_validate_stage_id "stage_name" && assert_success "Underscore stage ID accepted" || assert_failure "Underscore stage ID rejected"
    dag_validate_stage_id "stage-name" && assert_success "Hyphen stage ID accepted" || assert_failure "Hyphen stage ID rejected"
    ! dag_validate_stage_id "" && assert_success "Empty stage ID rejected" || assert_failure "Empty stage ID accepted"
    ! dag_validate_stage_id "stage name" && assert_success "Stage ID with space rejected" || assert_failure "Stage ID with space accepted"
    ! dag_validate_stage_id "stage@name" && assert_success "Stage ID with @ rejected" || assert_failure "Stage ID with @ accepted"
}

# Test: Failure policy validation
test_dag_validate_failure_policy() {
    dag_validate_failure_policy "FAIL_FAST" && assert_success "FAIL_FAST accepted" || assert_failure "FAIL_FAST rejected"
    dag_validate_failure_policy "CONTINUE" && assert_success "CONTINUE accepted" || assert_failure "CONTINUE rejected"
    dag_validate_failure_policy "SKIP_DEPENDENTS" && assert_success "SKIP_DEPENDENTS accepted" || assert_failure "SKIP_DEPENDENTS rejected"
    dag_validate_failure_policy "RETRY" && assert_success "RETRY accepted" || assert_failure "RETRY rejected"
    ! dag_validate_failure_policy "INVALID" && assert_success "Invalid policy rejected" || assert_failure "Invalid policy accepted"
    ! dag_validate_failure_policy "" && assert_success "Empty policy rejected" || assert_failure "Empty policy accepted"
}

# Test: Condition validation
test_dag_validate_condition() {
    dag_validate_condition "true" && assert_success "true condition accepted" || assert_failure "true condition rejected"
    dag_validate_condition "has_subdomains" && assert_success "has_subdomains accepted" || assert_failure "has_subdomains rejected"
    dag_validate_condition "has_resolved_hosts" && assert_success "has_resolved_hosts accepted" || assert_failure "has_resolved_hosts rejected"
    dag_validate_condition "has_web_targets" && assert_success "has_web_targets accepted" || assert_failure "has_web_targets rejected"
    dag_validate_condition "has_live_urls" && assert_success "has_live_urls accepted" || assert_failure "has_live_urls rejected"
    dag_validate_condition "has_urls" && assert_success "has_urls accepted" || assert_failure "has_urls rejected"
    ! dag_validate_condition "invalid" && assert_success "Invalid condition rejected" || assert_failure "Invalid condition accepted"
    ! dag_validate_condition "" && assert_success "Empty condition rejected" || assert_failure "Empty condition accepted"
}

# Test: Parallel group validation
test_dag_validate_parallel_group() {
    dag_validate_parallel_group "passive" && assert_success "passive group accepted" || assert_failure "passive group rejected"
    dag_validate_parallel_group "dns_resolve" && assert_success "dns_resolve group accepted" || assert_failure "dns_resolve group rejected"
    dag_validate_parallel_group "port_scan" && assert_success "port_scan group accepted" || assert_failure "port_scan group rejected"
    dag_validate_parallel_group "http_probe" && assert_success "http_probe group accepted" || assert_failure "http_probe group rejected"
    dag_validate_parallel_group "crawling" && assert_success "crawling group accepted" || assert_failure "crawling group rejected"
    dag_validate_parallel_group "vuln_scan" && assert_success "vuln_scan group accepted" || assert_failure "vuln_scan group rejected"
    dag_validate_parallel_group "reporting" && assert_success "reporting group accepted" || assert_failure "reporting group rejected"
    ! dag_validate_parallel_group "invalid" && assert_success "Invalid group rejected" || assert_failure "Invalid group accepted"
    ! dag_validate_parallel_group "" && assert_success "Empty group rejected" || assert_failure "Empty group accepted"
}

# Test: Canonical DAG loading
test_dag_canonical_loading() {
    dag_load_canonical
    assert_equals "7 stages loaded" 7 "${#DAG_STAGE_ID[@]}"
    assert_equals "Stage 0 is subdomains" "subdomains" "${DAG_STAGE_ID[0]}"
    assert_equals "Stage 1 is dns" "dns" "${DAG_STAGE_ID[1]}"
    assert_equals "Stage 2 is ports" "ports" "${DAG_STAGE_ID[2]}"
    assert_equals "Stage 3 is live" "live" "${DAG_STAGE_ID[3]}"
    assert_equals "Stage 4 is crawling" "crawling" "${DAG_STAGE_ID[4]}"
    assert_equals "Stage 5 is vuln" "vuln" "${DAG_STAGE_ID[5]}"
    assert_equals "Stage 6 is reports" "reports" "${DAG_STAGE_ID[6]}"
}

# Test: Unique stage IDs
test_dag_unique_ids() {
    dag_load_canonical
    dag_validate_unique_ids && assert_success "Unique stage IDs validated" || assert_failure "Unique stage IDs failed"
}

# Test: Valid stage IDs
test_dag_valid_ids() {
    dag_load_canonical
    dag_validate_all_ids && assert_success "All stage IDs valid" || assert_failure "Stage ID validation failed"
}

# Test: Valid failure policies
test_dag_valid_failure_policies() {
    dag_load_canonical
    dag_validate_all_failure_policies && assert_success "All failure policies valid" || assert_failure "Failure policy validation failed"
}

# Test: Valid conditions
test_dag_valid_conditions() {
    dag_load_canonical
    dag_validate_all_conditions && assert_success "All conditions valid" || assert_failure "Condition validation failed"
}

# Test: Valid parallel groups
test_dag_valid_parallel_groups() {
    dag_load_canonical
    dag_validate_all_parallel_groups && assert_success "All parallel groups valid" || assert_failure "Parallel group validation failed"
}

# Test: Dependency validation
test_dag_dependencies() {
    dag_load_canonical
    dag_validate_dependencies && assert_success "Valid dependencies accepted" || assert_failure "Valid dependencies rejected"
}

# Test: Cycle detection - simple cycle A -> B -> A
test_dag_cycle_detection_simple() {
    # Override canonical stages with a cyclic graph
    DAG_STAGE_ID=("A" "B")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("B" "A")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("cmd_a" "cmd_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(300 300)
    DAG_STAGE_RETRIES=(1 1)
    DAG_STAGE_RATE_LIMIT=("" "")

    ! dag_detect_cycles && assert_success "Simple cycle A->B->A detected" || assert_failure "Simple cycle not detected"
}

# Test: Cycle detection - three stage cycle A -> B -> C -> A
test_dag_cycle_detection_three() {
    DAG_STAGE_ID=("A" "B" "C")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("C" "A" "B")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("cmd_a" "cmd_b" "cmd_c")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(300 300 300)
    DAG_STAGE_RETRIES=(1 1 1)
    DAG_STAGE_RATE_LIMIT=("" "" "")

    ! dag_detect_cycles && assert_success "Three-stage cycle A->B->C->A detected" || assert_failure "Three-stage cycle not detected"
}

# Test: Self-dependency rejection
test_dag_self_dependency() {
    DAG_STAGE_ID=("A")
    DAG_STAGE_LABEL=("A")
    DAG_STAGE_DEPS=("A")
    DAG_STAGE_INPUTS=("input")
    DAG_STAGE_OUTPUTS=("output")
    DAG_STAGE_CMD=("cmd_a")
    DAG_STAGE_CONDITION=("true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("")
    DAG_STAGE_TIMEOUT=(300)
    DAG_STAGE_RETRIES=(1)
    DAG_STAGE_RATE_LIMIT=("")

    ! dag_validate_dependencies && assert_success "Self-dependency rejected" || assert_failure "Self-dependency accepted"
}

# Test: Missing dependency rejection
test_dag_missing_dependency() {
    DAG_STAGE_ID=("A" "B")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("C" "")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("cmd_a" "cmd_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(300 300)
    DAG_STAGE_RETRIES=(1 1)
    DAG_STAGE_RATE_LIMIT=("" "")

    ! dag_validate_dependencies && assert_success "Missing dependency rejected" || assert_failure "Missing dependency accepted"
}

# Test: Canonical DAG has no cycles
test_dag_canonical_no_cycles() {
    dag_load_canonical
    dag_detect_cycles && assert_success "Canonical DAG has no cycles" || assert_failure "Canonical DAG has cycles"
}

# Test: Topological order is deterministic
test_dag_topo_order_deterministic() {
    dag_load_canonical
    dag_detect_cycles >/dev/null
    local order1
    order1=$(dag_get_topo_order | tr '\n' ',')
    dag_detect_cycles >/dev/null
    local order2
    order2=$(dag_get_topo_order | tr '\n' ',')
    assert_equals "Topological order deterministic" "$order1" "$order2"
}

# Test: Topological order contains all stages
test_dag_topo_order_complete() {
    dag_load_canonical
    dag_detect_cycles >/dev/null
    local order
    order=$(dag_get_topo_order | tr '\n' ' ')
    assert_equals "Topological order has 7 stages" 7 "$(echo $order | wc -w)"
}

# Test: Stage getter functions
test_dag_getters() {
    dag_load_canonical
    local idx
    idx=$(dag_get_stage_index "dns")
    assert_equals "dns index is 1" 1 "$idx"
    assert_equals "dns label" "DNS Resolution" "$(dag_get_stage_label "dns")"
    assert_equals "dns deps" "subdomains" "$(dag_get_stage_deps "dns")"
    assert_equals "dns condition" "has_subdomains" "$(dag_get_stage_condition "dns")"
    assert_equals "dns failure policy" "FAIL_FAST" "$(dag_get_stage_failure_policy "dns")"
    assert_equals "dns parallel group" "dns_resolve" "$(dag_get_stage_parallel_group "dns")"
    assert_equals "dns command" "run_dnsx" "$(dag_get_stage_cmd "dns")"
    assert_equals "dns inputs" "subdomains/all.txt" "$(dag_get_stage_inputs "dns")"
    assert_equals "dns outputs" "dns/resolved.txt dns/resolved.jsonl" "$(dag_get_stage_outputs "dns")"
    assert_equals "dns timeout" "300" "$(dag_get_stage_timeout "dns")"
    assert_equals "dns retries" "1" "$(dag_get_stage_retries "dns")"
    assert_equals "dns rate limit" "" "$(dag_get_stage_rate_limit "dns")"
}

# Test: Condition evaluation
test_dag_condition_evaluation() {
    dag_load_canonical
    local tmpdir
    tmpdir=$(mktemp -d)
    
    # Test true condition
    dag_evaluate_condition "true" "$tmpdir" && assert_success "true condition evaluates to true" || assert_failure "true condition failed"
    
    # Test has_subdomains without file (but stage selected)
    export CLI_STAGES="subdomains"
    dag_evaluate_condition "has_subdomains" "$tmpdir" && assert_success "has_subdomains true when stage selected" || assert_failure "has_subdomains failed when stage selected"
    unset CLI_STAGES
    
    # Test has_subdomains with file
    mkdir -p "$tmpdir/subdomains"
    echo "sub.example.com" > "$tmpdir/subdomains/all.txt"
    dag_evaluate_condition "has_subdomains" "$tmpdir" && assert_success "has_subdomains true with file" || assert_failure "has_subdomains failed with file"
    
    # Test has_resolved_hosts
    mkdir -p "$tmpdir/dns"
    echo "example.com 1.2.3.4" > "$tmpdir/dns/resolved.txt"
    dag_evaluate_condition "has_resolved_hosts" "$tmpdir" && assert_success "has_resolved_hosts true with file" || assert_failure "has_resolved_hosts failed"
    
    # Test has_web_targets
    mkdir -p "$tmpdir/ports"
    echo "example.com:80" > "$tmpdir/ports/web_candidates.txt"
    dag_evaluate_condition "has_web_targets" "$tmpdir" && assert_success "has_web_targets true with web_candidates" || assert_failure "has_web_targets failed with web_candidates"
    
    # Test has_live_urls
    mkdir -p "$tmpdir/live"
    echo "http://example.com" > "$tmpdir/live/urls.txt"
    dag_evaluate_condition "has_live_urls" "$tmpdir" && assert_success "has_live_urls true with urls.txt" || assert_failure "has_live_urls failed"
    
    # Test has_urls
    mkdir -p "$tmpdir/crawling"
    echo "http://example.com/path" > "$tmpdir/crawling/katana.txt"
    dag_evaluate_condition "has_urls" "$tmpdir" && assert_success "has_urls true with katana.txt" || assert_failure "has_urls failed"
    
    # Clean up
    rm -rf "$tmpdir"
    
    # Test invalid condition
    ! dag_evaluate_condition "invalid_condition" "/tmp" && assert_success "Invalid condition rejected" || assert_failure "Invalid condition accepted"
}

# Test: Duplicate dependency normalization
test_dag_duplicate_deps() {
    # The canonical DAG has "dns,ports" for live stage
    dag_load_canonical
    local deps
    deps=$(dag_get_stage_deps "live")
    assert_equals "live deps" "dns,ports" "$deps"
}

# Test: Full canonical DAG validation
test_dag_full_validation() {
    dag_load_canonical
    dag_validate_all && assert_success "Full canonical DAG validation passes" || assert_failure "Full canonical DAG validation failed"
}

# Test: Duplicate dependency handling
test_dag_duplicate_dependency_handling() {
    DAG_STAGE_ID=("A" "B" "C")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "A" "A,A")  # Duplicate A
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("cmd_a" "cmd_b" "cmd_c")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(300 300 300)
    DAG_STAGE_RETRIES=(1 1 1)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    
    # Should handle duplicates (normalize or reject)
    dag_validate_dependencies && assert_success "Duplicate dependencies handled" || assert_failure "Duplicate dependencies failed"
}

# Test: Invalid condition rejection
test_dag_invalid_condition_rejection() {
    dag_load_canonical
    # Temporarily override a condition
    DAG_STAGE_CONDITION[1]="invalid_condition"
    ! dag_validate_all_conditions && assert_success "Invalid condition rejected" || assert_failure "Invalid condition accepted"
}

# Test: Invalid failure policy rejection
test_dag_invalid_failure_policy_rejection() {
    dag_load_canonical
    DAG_STAGE_FAILURE_POLICY[1]="INVALID_POLICY"
    ! dag_validate_all_failure_policies && assert_success "Invalid failure policy rejected" || assert_failure "Invalid failure policy accepted"
}

# Test: Invalid parallel group rejection
test_dag_invalid_parallel_group_rejection() {
    dag_load_canonical
    DAG_STAGE_PARALLEL_GROUP[1]="invalid_group"
    ! dag_validate_all_parallel_groups && assert_success "Invalid parallel group rejected" || assert_failure "Invalid parallel group accepted"
}

# Test: Deterministic representation
test_dag_deterministic_representation() {
    dag_load_canonical
    dag_detect_cycles >/dev/null
    local order1 order2
    order1=$(dag_get_topo_order | tr '\n' ',')
    order2=$(dag_get_topo_order | tr '\n' ',')
    assert_equals "Deterministic topological order" "$order1" "$order2"
    
    # Verify stage data is consistent
    local label1 label2
    label1=$(dag_get_stage_label "dns")
    label2=$(dag_get_stage_label "dns")
    assert_equals "Stage label deterministic" "$label1" "$label2"
}

# Test: Backward compatibility - old manifests without DAG fields
test_dag_backward_compat() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local manifest="$tmpdir/manifest.json"
    
    # Old manifest without dag_version
    cat > "$manifest" << 'EOF'
{
  "target": "example.com",
  "status": "success",
  "stages": {
    "subdomains": {"status": "success"},
    "dns": {"status": "success"}
  }
}
EOF

    # Should not break - dag_version defaults to 0
    local version
    version=$(dag_manifest_get_version "$manifest")
    assert_equals "Old manifest dag_version defaults to 0" "0" "$version"
    
    ! dag_manifest_has_dag_metadata "$manifest" && assert_success "Old manifest has no DAG metadata" || assert_failure "Old manifest incorrectly has DAG metadata"
    
    rm -rf "$tmpdir"
}

# Test: New manifest with dag_version
test_dag_new_manifest() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local manifest="$tmpdir/manifest.json"
    
    cat > "$manifest" << 'EOF'
{
  "target": "example.com",
  "dag_version": 1,
  "stages": {
    "subdomains": {
      "status": "success",
      "deps": [],
      "condition": "true",
      "failure_policy": "FAIL_FAST",
      "parallel_group": "passive"
    }
  }
}
EOF

    local version
    version=$(dag_manifest_get_version "$manifest")
    assert_equals "New manifest dag_version is 1" "1" "$version"
    
    dag_manifest_has_dag_metadata "$manifest" && assert_success "New manifest has DAG metadata" || assert_failure "New manifest missing DAG metadata"
    
    rm -rf "$tmpdir"
}

# Run all tests
echo "Running Phase 7.1 DAG Data Model and Validation Tests..."

test_dag_validate_stage_id
test_dag_validate_failure_policy
test_dag_validate_condition
test_dag_validate_parallel_group
test_dag_canonical_loading
test_dag_unique_ids
test_dag_valid_ids
test_dag_valid_failure_policies
test_dag_valid_conditions
test_dag_valid_parallel_groups
test_dag_dependencies
test_dag_cycle_detection_simple
test_dag_cycle_detection_three
test_dag_self_dependency
test_dag_missing_dependency
test_dag_canonical_no_cycles
test_dag_topo_order_deterministic
test_dag_topo_order_complete
test_dag_getters
test_dag_condition_evaluation
test_dag_duplicate_deps
test_dag_full_validation
test_dag_duplicate_dependency_handling
test_dag_invalid_condition_rejection
test_dag_invalid_failure_policy_rejection
test_dag_invalid_parallel_group_rejection
test_dag_deterministic_representation
test_dag_backward_compat
test_dag_new_manifest

echo ""
echo "====================================="
echo "Phase 7.1 DAG Tests: $PASSED passed, $FAILED failed"
echo "====================================="

if (( FAILED > 0 )); then
    exit 1
fi
exit 0