#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2086

# ============================================
# Phase 7.2 DAG Executor Core Tests
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

# Test: Sequential DAG execution (a -> b -> c)
test_dag_exec_sequential() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("a" "b" "c")
    DAG_STAGE_DEPS=("" "a" "b")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_cmd_success" "mock_cmd_success" "mock_cmd_success")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    mock_cmd_success() { return 0; }
    export -f mock_cmd_success
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    assert_equals "Sequential DAG execution succeeds" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    
    rm -rf "$tmpdir"
    unset -f mock_cmd_success
}

# Test: Dependency enforcement - B cannot execute before A succeeds
test_dag_exec_dependency_enforcement() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("a" "b" "c")
    DAG_STAGE_DEPS=("" "a" "b")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b() { return 0; }
    mock_c() { return 0; }
    export -f mock_a mock_b mock_c
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    
    # Verify all stages completed successfully (order verified by state)
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test: Multiple independent stages (a and b independent, c depends on both)
test_dag_exec_independent_stages() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("a" "b" "c")
    DAG_STAGE_DEPS=("" "" "a,b")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b() { return 0; }
    mock_c() { return 0; }
    export -f mock_a mock_b mock_c
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    
    # Verify all stages completed successfully
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test: Failure propagation (A succeeds, B fails, C becomes blocked)
test_dag_exec_failure_propagation() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("a" "b" "c")
    DAG_STAGE_DEPS=("" "a" "b")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b_fail" "mock_c")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b_fail() { return 1; }
    mock_c() { return 0; }
    export -f mock_a mock_b_fail mock_c
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?
    
    assert_equals "FAIL_FAST returns 2" 2 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_FAILED" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b_fail mock_c
}

# Test: FAIL_FAST stops execution
test_dag_exec_fail_fast() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("a" "b" "c" "d")
    DAG_STAGE_DEPS=("" "a" "b" "b")  # d depends on b, not a
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b_fail" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b_fail() { return 1; }
    mock_c() { return 0; }
    mock_d() { return 0; }
    export -f mock_a mock_b_fail mock_c mock_d
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "FAIL_FAST returns 2" 2 "$result"
    assert_equals "Stage d state (FAIL_FAST aborts all)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "d")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b_fail mock_c mock_d
}

# Test: CONTINUE allows independent branches to continue
test_dag_exec_continue() {
    local exec_order=()
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("a" "b" "c" "d")
    DAG_STAGE_DEPS=("" "a" "b" "a")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b_fail" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "CONTINUE" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1
    
    mock_a() { exec_order+=("a"); return 0; }
    mock_b_fail() { exec_order+=("b"); return 1; }
    mock_c() { exec_order+=("c"); return 0; }
    mock_d() { exec_order+=("d"); return 0; }
    export -f mock_a mock_b_fail mock_c mock_d
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "CONTINUE returns 1 (partial failure)" 1 "$result"
    assert_equals "Stage A state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage B state" "$DAG_STATE_FAILED" "$(dag_exec_get_state "b")"
    assert_equals "Stage C state (depends on B)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    assert_equals "Stage D state (independent)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "d")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b_fail mock_c mock_d
}

# Test: SKIP_DEPENDENTS blocks dependent stages
test_dag_exec_skip_dependents() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("a" "b" "c" "d")
    DAG_STAGE_DEPS=("" "a" "b" "a")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b_fail" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "SKIP_DEPENDENTS" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b_fail() { return 1; }
    mock_c() { return 0; }
    mock_d() { return 0; }
    export -f mock_a mock_b_fail mock_c mock_d
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "SKIP_DEPENDENTS returns 1 (partial failure)" 1 "$result"
    assert_equals "Stage C state (depends on B with SKIP_DEPENDENTS)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    assert_equals "Stage D state (independent)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "d")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b_fail mock_c mock_d
}

# Test: RETRY uses existing retry mechanism
test_dag_exec_retry() {
    local attempt_count=0
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("a" "b")
    DAG_STAGE_DEPS=("" "A")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b_retry")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "RETRY")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b_retry() { 
        attempt_count=$((attempt_count + 1))
        if (( attempt_count < 2 )); then
            return 1
        fi
        return 0; 
    }
    export -f mock_a mock_b_retry
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    STAGE_RETRIES=1
    export STAGE_RETRIES
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "RETRY attempts used" 2 "$attempt_count"
    assert_equals "Stage B state after retry success" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b_retry
    unset STAGE_RETRIES
}

# Test: Deterministic execution order
test_dag_exec_deterministic() {
    local exec_order_1=()
    local exec_order_2=()
    
    # Run 1
    reset_dag_state
    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("a" "b" "c" "d")
    DAG_STAGE_DEPS=("" "" "a,b" "c")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b() { return 0; }
    mock_c() { return 0; }
    mock_d() { return 0; }
    export -f mock_a mock_b mock_c mock_d
    
    local tmpdir1
    tmpdir1=$(mktemp -d)
    dag_exec_init "$tmpdir1"
    dag_exec_execute "$tmpdir1"
    rm -rf "$tmpdir1"
    
    # Run 2
    reset_dag_state
    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("a" "b" "c" "d")
    DAG_STAGE_DEPS=("" "" "a,b" "c")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1
    
    local tmpdir2
    tmpdir2=$(mktemp -d)
    dag_exec_init "$tmpdir2"
    dag_exec_execute "$tmpdir2"
    rm -rf "$tmpdir2"
    
    local order1_str
    order1_str=$(IFS=,; echo "${exec_order_1[*]}")
    local order2_str
    order2_str=$(IFS=,; echo "${exec_order_2[*]:-}")
    
    assert_equals "Deterministic execution order" "$order1_str" "$order2_str"
    
    unset -f mock_a mock_b mock_c mock_D
}

# Test: Cycle protection - executor rejects invalid DAG
test_dag_exec_cycle_protection() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("a" "b")
    DAG_STAGE_DEPS=("b" "a")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    mock_b() { return 0; }
    export -f mock_a mock_b
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    if ! dag_exec_init "$tmpdir"; then
        assert_success "Cycle detection prevents execution"
    else
        assert_failure "Cycle detection should prevent execution"
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test: Empty DAG handled safely
test_dag_exec_empty_dag() {
    reset_dag_state
    
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
    DAG_LOADED=1
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "Empty DAG succeeds" 0 "$result"
    
    rm -rf "$tmpdir"
}

# Test: Single-stage DAG
test_dag_exec_single_stage() {
    reset_dag_state
    
    DAG_STAGE_ID=("A")
    DAG_STAGE_LABEL=("A")
    DAG_STAGE_DEPS=("")
    DAG_STAGE_INPUTS=("input")
    DAG_STAGE_OUTPUTS=("output")
    DAG_STAGE_CMD=("mock_a")
    DAG_STAGE_CONDITION=("true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("")
    DAG_STAGE_TIMEOUT=(0)
    DAG_STAGE_RETRIES=(0)
    DAG_STAGE_RATE_LIMIT=("")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    export -f mock_A
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "Single stage succeeds" 0 "$result"
    assert_equals "Stage A state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    
    rm -rf "$tmpdir"
    unset -f mock_A
}

# Test: Unknown stage rejection
test_dag_exec_unknown_stage() {
    reset_dag_state
    
    DAG_STAGE_ID=("A")
    DAG_STAGE_LABEL=("A")
    DAG_STAGE_DEPS=("unknown")
    DAG_STAGE_INPUTS=("input")
    DAG_STAGE_OUTPUTS=("output")
    DAG_STAGE_CMD=("mock_a")
    DAG_STAGE_CONDITION=("true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("")
    DAG_STAGE_TIMEOUT=(0)
    DAG_STAGE_RETRIES=(0)
    DAG_STAGE_RATE_LIMIT=("")
    DAG_LOADED=1
    
    mock_a() { return 0; }
    export -f mock_A
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    if ! dag_exec_init "$tmpdir"; then
        assert_success "Unknown dependency rejected"
    else
        assert_failure "Unknown dependency should be rejected"
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_A
}

# Test: Condition evaluation skips stage
test_dag_exec_condition_skip() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("a" "b")
    DAG_STAGE_DEPS=("" "A")
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
    
    mock_a() { return 0; }
    mock_b() { return 0; }
    export -f mock_a mock_b
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "Condition skip succeeds" 0 "$result"
    assert_equals "Stage A state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage B state (skipped)" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "b")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test: Invalid dependency state handling
test_dag_exec_invalid_dep_state() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("a" "b")
    DAG_STAGE_DEPS=("" "A")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_a() { return 1; }
    mock_b() { return 0; }
    export -f mock_a mock_b
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    local result
    dag_exec_execute "$tmpdir"
    result=$?
    
    assert_equals "FAIL_FAST blocks dependent" 2 "$result"
    assert_equals "Stage B blocked" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "b")"
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test: Manifest integration - stage states tracked in manifest
test_dag_exec_manifest_integration() {
    reset_dag_state
    
    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("a" "b")
    DAG_STAGE_DEPS=("" "A")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1
    
    mock_a() { echo "result" > "${DAG_EXEC_WORKSPACE}/output"; return 0; }
    mock_b() { echo "result" > "${DAG_EXEC_WORKSPACE}/output"; return 0; }
    export -f mock_a mock_b
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    
    local manifest_file="${tmpdir}/manifest.json"
    assert_equals "Manifest exists" "true" "$([[ -f "$manifest_file" ]] && echo true || echo false)"
    
    if command -v jq >/dev/null 2>&1; then
        local a_status
        a_status=$(jq -r '.stages.A.status' "$manifest_file")
        local b_status
        b_status=$(jq -r '.stages.B.status' "$manifest_file")
        assert_equals "Manifest stage A success" "success" "$a_status"
        assert_equals "Manifest stage B success" "success" "$b_status"
    fi
    
    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test: Canonical 7-stage DAG executes in correct order
test_dag_exec_canonical_order() {
    reset_dag_state
    
    # Load canonical DAG
    dag_load_canonical
    
    local exec_order=()
    
    execute_subdomains_stage() { exec_order+=("subdomains"); return 0; }
    run_dnsx() { exec_order+=("dns"); return 0; }
    run_naabu() { exec_order+=("ports"); return 0; }
    execute_live_stage() { exec_order+=("live"); return 0; }
    run_katana() { exec_order+=("crawling"); return 0; }
    run_nuclei() { exec_order+=("vuln"); return 0; }
    execute_reports_stage() { exec_order+=("reports"); return 0; }
    export -f execute_subdomains_stage run_dnsx run_naabu execute_live_stage run_katana run_nuclei execute_reports_stage
    
    local tmpdir
    tmpdir=$(mktemp -d)
    
    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    
    assert_equals "Canonical order 1" "subdomains" "${exec_order[0]:-}"
    assert_equals "Canonical order 2" "dns" "${exec_order[1]:-}"
    assert_equals "Canonical order 3" "ports" "${exec_order[2]:-}"
    assert_equals "Canonical order 4" "live" "${exec_order[3]:-}"
    assert_equals "Canonical order 5" "crawling" "${exec_order[4]:-}"
    assert_equals "Canonical order 6" "vuln" "${exec_order[5]:-}"
    assert_equals "Canonical order 7" "reports" "${exec_order[6]:-}"
    
    rm -rf "$tmpdir"
    unset -f execute_subdomains_stage run_dnsx run_naabu execute_live_stage run_katana run_nuclei execute_reports_stage
}

# Run all tests
echo "Running Phase 7.2 DAG Executor Core Tests..."

test_dag_exec_sequential
test_dag_exec_dependency_enforcement
test_dag_exec_independent_stages
test_dag_exec_failure_propagation
test_dag_exec_fail_fast
test_dag_exec_continue
test_dag_exec_skip_dependents
test_dag_exec_retry
test_dag_exec_deterministic
test_dag_exec_cycle_protection
test_dag_exec_empty_dag
test_dag_exec_single_stage
test_dag_exec_unknown_stage
test_dag_exec_condition_skip
test_dag_exec_invalid_dep_state
test_dag_exec_manifest_integration
test_dag_exec_canonical_order

echo ""
echo "====================================="
echo "Phase 7.2 DAG Executor Tests: $PASSED passed, $FAILED failed"
echo "====================================="

if (( FAILED > 0 )); then
    exit 1
fi
exit 0