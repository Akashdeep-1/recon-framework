#!/usr/bin/env bash

# ============================================
# Recon Framework - Parallel Execution Library
# ============================================

PARALLEL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$PARALLEL_LIB_DIR/logger.sh"
fi

# Track active background child PIDs for cleanup
declare -a ACTIVE_CHILD_PIDS=()

# Cleanup handler for active child processes on abort
cleanup_parallel_tasks() {
    if (( ${#ACTIVE_CHILD_PIDS[@]} > 0 )); then
        log_warn "Terminating background parallel tasks: ${ACTIVE_CHILD_PIDS[*]}"
        local pid
        for pid in "${ACTIVE_CHILD_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null || true
                local waited=0
                while kill -0 "$pid" 2>/dev/null && (( waited < 10 )); do
                    sleep 0.05 2>/dev/null || true
                    waited=$(( waited + 1 ))
                done
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
                wait "$pid" 2>/dev/null || true
            fi
        done
        ACTIVE_CHILD_PIDS=()
    fi
}

# Run two independent stages concurrently and wait for both to complete.
# Usage: run_parallel_stages "Stage1" "cmd1 arg1..." "Stage2" "cmd2 arg2..."
run_parallel_stages() {
    local name1="$1"
    local cmd1="$2"
    local name2="$3"
    local cmd2="$4"

    log_info "Launching parallel stages: [$name1] & [$name2]"

    local log1 log2
    log1="$(mktemp "${TMPDIR:-/tmp}/recon_parallel_1.XXXXXX" 2>/dev/null || printf '/tmp/recon_p1_%s.log' "$$")"
    log2="$(mktemp "${TMPDIR:-/tmp}/recon_parallel_2.XXXXXX" 2>/dev/null || printf '/tmp/recon_p2_%s.log' "$$")"

    # Launch task 1 in background
    bash -c "$cmd1" > "$log1" 2>&1 &
    local pid1=$!

    # Launch task 2 in background
    bash -c "$cmd2" > "$log2" 2>&1 &
    local pid2=$!

    ACTIVE_CHILD_PIDS=("$pid1" "$pid2")

    local status1=0 status2=0
    wait "$pid1" || status1=$?
    wait "$pid2" || status2=$?

    ACTIVE_CHILD_PIDS=()

    # Echo captured logs if verbose or on failure
    if [[ -s "$log1" ]]; then
        cat "$log1"
    fi
    if [[ -s "$log2" ]]; then
        cat "$log2"
    fi

    rm -f "$log1" "$log2" 2>/dev/null || true

    if (( status1 != 0 )); then
        log_error "Parallel stage [$name1] failed with exit code $status1."
        return "$status1"
    fi

    if (( status2 != 0 )); then
        log_error "Parallel stage [$name2] failed with exit code $status2."
        return "$status2"
    fi

    log_success "Parallel stages completed successfully: [$name1] & [$name2]"
    return 0
}
