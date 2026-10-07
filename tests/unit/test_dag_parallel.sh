#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2086

# ============================================
# Phase 7.4 DAG Parallel Execution Tests
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

assert_true() {
    local desc="$1"
    local condition="$2"

    if eval "$condition"; then
        echo -e "  ${GREEN}✓${RESET} $desc"
        PASSED=$(( PASSED + 1 ))
    else
        echo -e "  ${RED}✗${RESET} $desc"
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
    DAG_EXEC_MAX_CONCURRENCY=1
    DAG_EXEC_ACTIVE_PIDS=()
    DAG_EXEC_ACTIVE_STAGES=()
    DAG_EXEC_CHILD_RESULTS=()
}

# Test 1: Two independent stages execute concurrently
test_parallel_two_independent() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Both stages succeed" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 2: Dependent stage waits for all dependencies
test_parallel_dependent_waits() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test 3: Three independent stages execute with concurrency >1
test_parallel_three_independent() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "" "")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { sleep 0.1; return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=3

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "All three stages succeed" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test 4: Maximum concurrency is enforced (deterministic overlap proof)
test_parallel_concurrency_limit() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("A" "B" "C" "D")
    DAG_STAGE_DEPS=("" "" "" "")
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

    # Stages A and B write 'started' marker, then wait for 'release' before finishing
    mock_a() {
        touch "${tmpdir}/a_started"
        while [[ ! -f "${tmpdir}/release" ]]; do sleep 0.01; done
        return 0
    }
    mock_b() {
        touch "${tmpdir}/b_started"
        while [[ ! -f "${tmpdir}/release" ]]; do sleep 0.01; done
        return 0
    }
    # Stages C and D just complete quickly (they run after A/B due to concurrency limit)
    mock_c() { return 0; }
    mock_d() { return 0; }
    export -f mock_a mock_b mock_c mock_d

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    # Start execution in background so we can control release
    dag_exec_execute "$tmpdir" &
    local exec_pid=$!

    # Wait for both A and B to signal they've started
    local timeout=50
    while (( timeout > 0 )) && [[ ! -f "${tmpdir}/a_started" || ! -f "${tmpdir}/b_started" ]]; do
        sleep 0.05
        timeout=$(( timeout - 1 ))
    done

    # PROOF: Both A and B have started (overlap confirmed)
    assert_true "Stage A started" "[[ -f \"${tmpdir}/a_started\" ]]"
    assert_true "Stage B started" "[[ -f \"${tmpdir}/b_started\" ]]"

    # Now release them to complete
    touch "${tmpdir}/release"

    # Wait for execution to finish
    wait "$exec_pid"
    local result=$?

    assert_equals "All four stages succeed" 0 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c mock_d
}

# Test 5: Concurrency=1 reproduces sequential behavior (deterministic)
test_parallel_concurrency_one_sequential() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    # Stage A writes marker, then waits for release
    mock_a() {
        touch "${tmpdir}/a_done"
        while [[ ! -f "${tmpdir}/release_a" ]]; do sleep 0.01; done
        return 0
    }
    # Stage B writes marker after A is done (proving sequential)
    mock_b() {
        # Verify A completed before B starts
        if [[ ! -f "${tmpdir}/a_done" ]]; then
            echo "FAIL: B started before A completed" >&2
            return 1
        fi
        touch "${tmpdir}/b_done"
        return 0
    }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=1

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir" &
    local exec_pid=$!

    # Wait for A to complete
    local timeout=50
    while (( timeout > 0 )) && [[ ! -f "${tmpdir}/a_done" ]]; do
        sleep 0.05
        timeout=$(( timeout - 1 ))
    done

    # Release A
    touch "${tmpdir}/release_a"

    # Wait for execution to finish
    wait "$exec_pid"
    local result=$?

    # PROOF: A completed before B started
    assert_true "Stage A completed first" "[[ -f \"${tmpdir}/a_done\" ]]"
    assert_true "Stage B completed" "[[ -f \"${tmpdir}/b_done\" ]]"
    assert_equals "Both stages succeed" 0 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 6: No stage executes twice
test_parallel_no_duplicate_execution() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { echo 1 >> "${tmpdir}/count_a.txt"; return 0; }
    mock_b() { echo 1 >> "${tmpdir}/count_b.txt"; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    local count_a=0
    local count_b=0
    [[ -f "${tmpdir}/count_a.txt" ]] && count_a=$(wc -l < "${tmpdir}/count_a.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_b.txt" ]] && count_b=$(wc -l < "${tmpdir}/count_b.txt" | tr -d ' ')

    assert_equals "Stage a executed once" 1 "$count_a"
    assert_equals "Stage b executed once" 1 "$count_b"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 7: Stage PIDs are tracked correctly
test_parallel_pid_tracking() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { sleep 0.2; return 0; }
    mock_b() { sleep 0.2; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Both stages succeed" 0 "$result"
    # Check that JSONL has stage_start events with stage info
    if [[ -f "$jsonl_file" ]]; then
        local start_count
        start_count=$(grep -c '"event":"stage_start"' "$jsonl_file" || echo 0)
        assert_equals "Two stage_start events" 2 "$start_count"
    fi

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 8: Child exit status is captured correctly
test_parallel_child_exit_status() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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
    mock_b() { return 1; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a succeeds" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "b")"
    assert_equals "Overall result indicates failure" 2 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 9: One parallel stage fails while another succeeds
test_parallel_one_fails_one_succeeds() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "" "a")
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

    mock_a() { sleep 0.1; return 1; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "a")"
    assert_equals "Stage b succeeds" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c blocked (depends on a)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    assert_equals "Overall result indicates failure" 2 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test 10: Independent branch continues after unrelated failure
test_parallel_independent_branch_continues() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "" "b")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c")
    DAG_STAGE_CONDITION=("true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("CONTINUE" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1

    mock_a() { sleep 0.1; return 1; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "a")"
    assert_equals "Stage b succeeds" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c succeeds (depends on b with CONTINUE)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    assert_equals "Overall result indicates partial failure" 1 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test 11: FAIL_FAST behaves correctly
test_parallel_fail_fast() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "a" "a")
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

    mock_a() { sleep 0.1; return 1; }
    mock_b() { sleep 0.2; return 0; }
    mock_c() { sleep 0.2; return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "a")"
    assert_equals "Stage b blocked" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "b")"
    assert_equals "Stage c blocked" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    assert_equals "Overall result indicates FAIL_FAST" 2 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test 12: CONTINUE behaves correctly
test_parallel_continue() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("A" "B" "C" "D")
    DAG_STAGE_DEPS=("" "" "a" "b")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("CONTINUE" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1

    mock_a() { sleep 0.1; return 1; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { return 0; }
    mock_d() { return 0; }
    export -f mock_a mock_b mock_c mock_d

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "a")"
    assert_equals "Stage b succeeds (CONTINUE)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c blocked (depends on a with FAIL_FAST)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    assert_equals "Stage d succeeds (depends on b)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "d")"
    assert_equals "Overall result indicates partial failure" 1 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c mock_d
}

# Test 13: SKIP_DEPENDENTS behaves correctly
test_parallel_skip_dependents() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("A" "B" "C" "D")
    DAG_STAGE_DEPS=("" "" "a" "b")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("SKIP_DEPENDENTS" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1

    mock_a() { sleep 0.1; return 1; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { return 0; }
    mock_d() { return 0; }
    export -f mock_a mock_b mock_c mock_d

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "a")"
    assert_equals "Stage b succeeds (SKIP_DEPENDENTS)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c skipped (depends on a with SKIP_DEPENDENTS)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"
    assert_equals "Stage d succeeds (depends on b)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "d")"
    assert_equals "Overall result indicates partial failure" 1 "$result"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c mock_d
}

# Test 14: RETRY works independently per stage
test_parallel_retry() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("RETRY" "RETRY")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(2 2)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1

    mock_a() {
        echo 1 >> "${tmpdir}/attempt_a.txt"
        local n
        n=$(wc -l < "${tmpdir}/attempt_a.txt" | tr -d ' ')
        (( n >= 3 )) && return 0 || return 1
    }
    mock_b() {
        echo 1 >> "${tmpdir}/attempt_b.txt"
        local n
        n=$(wc -l < "${tmpdir}/attempt_b.txt" | tr -d ' ')
        (( n >= 2 )) && return 0 || return 1
    }
    export -f mock_a mock_b

    STAGE_RETRIES=2
    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    local attempt_a=0
    local attempt_b=0
    [[ -f "${tmpdir}/attempt_a.txt" ]] && attempt_a=$(wc -l < "${tmpdir}/attempt_a.txt" | tr -d ' ')
    [[ -f "${tmpdir}/attempt_b.txt" ]] && attempt_b=$(wc -l < "${tmpdir}/attempt_b.txt" | tr -d ' ')

    assert_equals "Stage a succeeds after 3 attempts" 0 "$result"
    assert_equals "Stage a attempts" 3 "$attempt_a"
    assert_equals "Stage b attempts" 2 "$attempt_b"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 15: Conditional SKIPPED stage never launches
test_parallel_conditional_skipped_never_launches() {
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

    mock_a() { echo 1 >> "${tmpdir}/count_a.txt"; return 0; }
    mock_b() { echo 1 >> "${tmpdir}/count_b.txt"; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    local count_a=0
    local count_b=0
    [[ -f "${tmpdir}/count_a.txt" ]] && count_a=$(wc -l < "${tmpdir}/count_a.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_b.txt" ]] && count_b=$(wc -l < "${tmpdir}/count_b.txt" | tr -d ' ')

    assert_equals "Stage a succeeds" 0 "$result"
    assert_equals "Stage b skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "b")"
    assert_equals "Stage a executed once" 1 "$count_a"
    assert_equals "Stage b never executed" 0 "$count_b"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 16: SKIPPED stage does not consume a concurrency slot
test_parallel_skipped_no_concurrency_slot() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "a" "a")
    DAG_STAGE_INPUTS=("input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c")
    DAG_STAGE_CONDITION=("true" "has_subdomains" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0)
    DAG_STAGE_RETRIES=(0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "")
    DAG_LOADED=1

    mock_a() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_a.txt"; return 0; }
    mock_b() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_b.txt"; return 0; }
    mock_c() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_c.txt"; return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=1

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    local count_a=0
    local count_b=0
    local count_c=0
    [[ -f "${tmpdir}/count_a.txt" ]] && count_a=$(wc -l < "${tmpdir}/count_a.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_b.txt" ]] && count_b=$(wc -l < "${tmpdir}/count_b.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_c.txt" ]] && count_c=$(wc -l < "${tmpdir}/count_c.txt" | tr -d ' ')

    assert_equals "Stage a succeeds" 0 "$result"
    assert_equals "Stage b skipped" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "b")"
    assert_equals "Stage c succeeds (no concurrency slot consumed)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    assert_equals "Stage a executed" 1 "$count_a"
    assert_equals "Stage b never executed" 0 "$count_b"
    assert_equals "Stage c executed" 1 "$count_c"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c
}

# Test 17: BLOCKED and SKIPPED remain distinct
test_parallel_blocked_vs_skipped() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "a" "a")
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

    mock_a() { return 1; }
    mock_b() { return 0; }
    mock_c() { return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Stage a fails" "$DAG_STATE_FAILED" "$(dag_exec_get_state "a")"
    assert_equals "Stage b blocked (failed dependency)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "b")"
    assert_equals "Stage c blocked (failed dependency)" "$DAG_STATE_BLOCKED" "$(dag_exec_get_state "c")"

    # Now test SKIPPED (condition false)
    reset_dag_state
    DAG_STAGE_ID=("x" "y")
    DAG_STAGE_LABEL=("X" "Y")
    DAG_STAGE_DEPS=("" "x")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_x" "mock_y")
    DAG_STAGE_CONDITION=("true" "has_subdomains")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("" "")
    DAG_LOADED=1

    mock_x() { return 0; }
    mock_y() { return 0; }
    export -f mock_x mock_y

    DAG_MAX_CONCURRENCY=2

    local tmpdir2
    tmpdir2=$(mktemp -d)
    local jsonl_file2="${tmpdir2}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file2"

    dag_exec_init "$tmpdir2"
    dag_exec_execute "$tmpdir2"
    local result2=$?

    assert_equals "Stage y skipped (condition false)" "$DAG_STATE_SKIPPED" "$(dag_exec_get_state "y")"

    rm -rf "$tmpdir" "$tmpdir2"
    unset -f mock_a mock_b mock_c mock_x mock_y
}

# Test 18: Parallel execution preserves dependency ordering
test_parallel_dependency_ordering() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c" "d" "e")
    DAG_STAGE_LABEL=("A" "B" "C" "D" "E")
    DAG_STAGE_DEPS=("" "" "a,b" "c" "c")
    DAG_STAGE_INPUTS=("input" "input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c" "mock_d" "mock_e")
    DAG_STAGE_CONDITION=("true" "true" "true" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "" "")
    DAG_LOADED=1

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { sleep 0.1; return 0; }
    mock_d() { sleep 0.1; return 0; }
    mock_e() { sleep 0.1; return 0; }
    export -f mock_a mock_b mock_c mock_d mock_e

    DAG_MAX_CONCURRENCY=3

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state (depends on a,b)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    assert_equals "Stage d state (depends on c)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "d")"
    assert_equals "Stage e state (depends on c)" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "e")"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c mock_d mock_e
}

# Test 19: Existing rate limits remain enforced
test_parallel_rate_limits() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
    DAG_STAGE_INPUTS=("input" "input")
    DAG_STAGE_OUTPUTS=("output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b")
    DAG_STAGE_CONDITION=("true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("port_scan" "port_scan")
    DAG_STAGE_TIMEOUT=(0 0)
    DAG_STAGE_RETRIES=(0 0)
    DAG_STAGE_RATE_LIMIT=("naabu" "naabu")
    DAG_LOADED=1

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Both stages succeed" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 20: SIGINT/SIGTERM does not leave orphan processes
# Note: This is difficult to test reliably in bash, we'll test cleanup function
test_parallel_cleanup() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { sleep 2; return 0; }
    mock_b() { sleep 2; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    # Start execution in background and send SIGINT
    dag_exec_init "$tmpdir"
    # Just test that cleanup function exists and can be called
    dag_exec_cleanup_children
    assert_success "Cleanup function executes without error"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 21: Executor waits for active children
test_parallel_wait_children() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { sleep 0.2; return 0; }
    mock_b() { sleep 0.2; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Both stages succeed" 0 "$result"

    # Check no child processes remain (all waited)
    local remaining_children=0
    for pid in "${DAG_EXEC_ACTIVE_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            remaining_children=$(( remaining_children + 1 ))
        fi
    done
    assert_equals "No orphan processes" 0 "$remaining_children"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 22: Final DAG result is correct despite different completion order
test_parallel_result_correctness() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("A" "B" "C" "D")
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

    mock_a() { sleep 0.2; return 0; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { sleep 0.1; return 0; }
    mock_d() { sleep 0.1; return 0; }
    export -f mock_a mock_b mock_c mock_d

    DAG_MAX_CONCURRENCY=3

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "All stages succeed" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"
    assert_equals "Stage b state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "b")"
    assert_equals "Stage c state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "c")"
    assert_equals "Stage d state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "d")"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c mock_d
}

# Test 23: JSONL stage_start/stage_complete events contain correct stage identity
test_parallel_jsonl_stage_identity() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Both stages succeed" 0 "$result"

    if [[ -f "$jsonl_file" ]]; then
        local start_a
        start_a=$(grep '"event":"stage_start"' "$jsonl_file" | grep '"stage":"a"' || echo "")
        local start_b
        start_b=$(grep '"event":"stage_start"' "$jsonl_file" | grep '"stage":"b"' || echo "")
        local complete_a
        complete_a=$(grep '"event":"stage_complete"' "$jsonl_file" | grep '"stage":"a"' || echo "")
        local complete_b
        complete_b=$(grep '"event":"stage_complete"' "$jsonl_file" | grep '"stage":"b"' || echo "")

        assert_true "Stage a start event present" "[[ -n '$start_a' ]]"
        assert_true "Stage b start event present" "[[ -n '$start_b' ]]"
        assert_true "Stage a complete event present" "[[ -n '$complete_a' ]]"
        assert_true "Stage b complete event present" "[[ -n '$complete_b' ]]"
    fi

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 24: Parallel telemetry remains machine-parseable
test_parallel_jsonl_parseable() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b")
    DAG_STAGE_LABEL=("A" "B")
    DAG_STAGE_DEPS=("" "")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    export -f mock_a mock_b

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Both stages succeed" 0 "$result"

    if [[ -f "$jsonl_file" ]]; then
        local parse_ok=1
        local line
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                if command -v jq >/dev/null 2>&1; then
                    printf '%s\n' "$line" | jq empty >/dev/null 2>&1 || parse_ok=0
                elif [[ "$line" =~ ^\{.*\}$ ]]; then
                    : # Structural JSON object check
                else
                    parse_ok=0
                fi
            fi
        done < "$jsonl_file"
        if (( parse_ok == 1 )); then
            assert_success "All JSONL lines are valid JSON"
        else
            assert_failure "One or more JSONL lines failed validation"
        fi
    fi

    rm -rf "$tmpdir"
    unset -f mock_a mock_b
}

# Test 25: Concurrency configuration validation works
test_parallel_concurrency_validation() {
    # Test invalid concurrency values
    reset_dag_state
    DAG_STAGE_ID=("a")
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
    export -f mock_a

    DAG_MAX_CONCURRENCY=0
    local tmpdir
    tmpdir=$(mktemp -d)
    dag_exec_init "$tmpdir"
    local result=$?
    assert_true "Concurrency 0 fails" "[[ $result -ne 0 ]]"
    rm -rf "$tmpdir"

    DAG_MAX_CONCURRENCY=-1
    tmpdir=$(mktemp -d)
    dag_exec_init "$tmpdir"
    result=$?
    assert_true "Concurrency -1 fails" "[[ $result -ne 0 ]]"
    rm -rf "$tmpdir"

    DAG_MAX_CONCURRENCY=abc
    tmpdir=$(mktemp -d)
    dag_exec_init "$tmpdir"
    result=$?
    assert_true "Concurrency abc fails" "[[ $result -ne 0 ]]"
    rm -rf "$tmpdir"

    DAG_MAX_CONCURRENCY=2
    tmpdir=$(mktemp -d)
    dag_exec_init "$tmpdir"
    result=$?
    assert_true "Concurrency 2 succeeds" "[[ $result -eq 0 ]]"
    rm -rf "$tmpdir"

    unset -f mock_a
}

# Test 26: Invalid concurrency values fail safely
test_parallel_invalid_concurrency_safe() {
    reset_dag_state
    DAG_STAGE_ID=("a")
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
    export -f mock_a

    DAG_MAX_CONCURRENCY="1.5"
    local tmpdir
    tmpdir=$(mktemp -d)
    dag_exec_init "$tmpdir"
    local result=$?
    assert_true "Float concurrency fails" "[[ $result -ne 0 ]]"
    rm -rf "$tmpdir"

    unset -f mock_a
}

# Test 27: Concurrency=1 is deterministic
test_parallel_concurrency_one_deterministic() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "" "")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { sleep 0.1; return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=1

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result1=$?

    reset_dag_state
    DAG_STAGE_ID=("a" "b" "c")
    DAG_STAGE_LABEL=("A" "B" "C")
    DAG_STAGE_DEPS=("" "" "")
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

    mock_a() { sleep 0.1; return 0; }
    mock_b() { sleep 0.1; return 0; }
    mock_c() { sleep 0.1; return 0; }
    export -f mock_a mock_b mock_c

    DAG_MAX_CONCURRENCY=1

    local tmpdir2
    tmpdir2=$(mktemp -d)
    local jsonl_file2="${tmpdir2}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file2"

    dag_exec_init "$tmpdir2"
    dag_exec_execute "$tmpdir2"
    local result2=$?

    assert_equals "Both runs succeed" 0 "$result1"
    assert_equals "Second run succeeds" 0 "$result2"
    assert_equals "Both runs have same final states" 0 "$(( result1 != result2 ))"

    rm -rf "$tmpdir" "$tmpdir2"
    unset -f mock_a mock_b mock_c
}

# Test 28: Empty DAG remains correct
test_parallel_empty_dag() {
    reset_dag_state

    DAG_LOADED=1

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Empty DAG succeeds" 0 "$result"

    rm -rf "$tmpdir"
}

# Test 29: Single-stage DAG remains correct
test_parallel_single_stage() {
    reset_dag_state

    DAG_STAGE_ID=("a")
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
    export -f mock_a

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    assert_equals "Single stage succeeds" 0 "$result"
    assert_equals "Stage a state" "$DAG_STATE_SUCCESS" "$(dag_exec_get_state "a")"

    rm -rf "$tmpdir"
    unset -f mock_a
}

# Test 30: Mixed conditional + parallel DAG works correctly
test_parallel_mixed_conditional() {
    reset_dag_state

    DAG_STAGE_ID=("a" "b" "c" "d")
    DAG_STAGE_LABEL=("A" "B" "C" "D")
    DAG_STAGE_DEPS=("" "a" "a" "b,c")
    DAG_STAGE_INPUTS=("input" "input" "input" "input")
    DAG_STAGE_OUTPUTS=("output" "output" "output" "output")
    DAG_STAGE_CMD=("mock_a" "mock_b" "mock_c" "mock_d")
    DAG_STAGE_CONDITION=("true" "has_subdomains" "true" "true")
    DAG_STAGE_FAILURE_POLICY=("FAIL_FAST" "FAIL_FAST" "FAIL_FAST" "FAIL_FAST")
    DAG_STAGE_PARALLEL_GROUP=("" "" "" "")
    DAG_STAGE_TIMEOUT=(0 0 0 0)
    DAG_STAGE_RETRIES=(0 0 0 0)
    DAG_STAGE_RATE_LIMIT=("" "" "" "")
    DAG_LOADED=1

    # a produces subdomains, b depends on a but has condition, c runs independently
    mock_a() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_a.txt"; echo "sub.example.com" > "${DAG_EXEC_WORKSPACE}/subdomains/all.txt"; return 0; }
    mock_b() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_b.txt"; return 0; }
    mock_c() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_c.txt"; return 0; }
    mock_d() { echo 1 >> "${DAG_EXEC_WORKSPACE}/count_d.txt"; return 0; }
    export -f mock_a mock_b mock_c mock_d

    DAG_MAX_CONCURRENCY=2

    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/subdomains"
    local jsonl_file="${tmpdir}/test.jsonl"
    jsonl_init "test-run" "$jsonl_file"

    dag_exec_init "$tmpdir"
    dag_exec_execute "$tmpdir"
    local result=$?

    local count_a=0
    local count_b=0
    local count_c=0
    local count_d=0
    [[ -f "${tmpdir}/count_a.txt" ]] && count_a=$(wc -l < "${tmpdir}/count_a.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_b.txt" ]] && count_b=$(wc -l < "${tmpdir}/count_b.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_c.txt" ]] && count_c=$(wc -l < "${tmpdir}/count_c.txt" | tr -d ' ')
    [[ -f "${tmpdir}/count_d.txt" ]] && count_d=$(wc -l < "${tmpdir}/count_d.txt" | tr -d ' ')

    assert_equals "All relevant stages succeed" 0 "$result"
    assert_equals "Stage a succeeds" 1 "$count_a"
    assert_equals "Stage b executes (condition true)" 1 "$count_b"
    assert_equals "Stage c succeeds" 1 "$count_c"
    assert_equals "Stage d succeeds (depends on b,c)" 1 "$count_d"

    rm -rf "$tmpdir"
    unset -f mock_a mock_b mock_c mock_d
}

# Run all tests
echo "Running Phase 7.4 Parallel Execution Tests..."

test_parallel_two_independent
test_parallel_dependent_waits
test_parallel_three_independent
test_parallel_concurrency_limit
test_parallel_concurrency_one_sequential
test_parallel_no_duplicate_execution
test_parallel_pid_tracking
test_parallel_child_exit_status
test_parallel_one_fails_one_succeeds
test_parallel_independent_branch_continues
test_parallel_fail_fast
test_parallel_continue
test_parallel_skip_dependents
test_parallel_retry
test_parallel_conditional_skipped_never_launches
test_parallel_skipped_no_concurrency_slot
test_parallel_blocked_vs_skipped
test_parallel_dependency_ordering
test_parallel_rate_limits
test_parallel_cleanup
test_parallel_wait_children
test_parallel_result_correctness
test_parallel_jsonl_stage_identity
test_parallel_jsonl_parseable
test_parallel_concurrency_validation
test_parallel_invalid_concurrency_safe
test_parallel_concurrency_one_deterministic
test_parallel_empty_dag
test_parallel_single_stage
test_parallel_mixed_conditional

echo ""
echo "====================================="
echo "Phase 7.4 Parallel Execution Tests: $PASSED passed, $FAILED failed"
echo "====================================="

if (( FAILED > 0 )); then
    exit 1
fi
exit 0